"""
E'lonlar: /listings/*

Mijoz o'z so'zlari bilan nima kerakligini yozadi, egasi "olaman" deydi,
mijoz tasdiqlaydi. Ma'lumotnoma va savdo yo'q — bu zayavkadan farqi.

DIQQAT: aniq yo'llar parametrli yo'ldan OLDIN turishi shart. /listings/mine
va /listings/feed — /listings/{listing_id} dan yuqorida, aks holda FastAPI
"mine" so'zini son deb o'qishga urinadi. Loyihada bu xato uch marta bo'lgan.
"""
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from sqlalchemy.orm import Session

from app.core import media
from app.core.account_state import assert_not_frozen
from app.core.roles import role_checker
from app.db.session import get_db
from app.models.listing import Listing
from app.models.user import User
from app.routes.auth import get_current_user
from app.schemas.listing import ListingCreate, ListingRead
from app.services import listing_service, pricing_service

router = APIRouter()


def _as_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _to_read(db: Session, listing: Listing, viewer: User) -> ListingRead:
    data = ListingRead.model_validate(listing)

    client = db.query(User).filter(User.id == listing.client_id).first()
    data.client_name = client.full_name if client else None

    if listing.taken_by:
        taker = db.query(User).filter(User.id == listing.taken_by).first()
        data.taker_name = taker.full_name if taker else None

    data.taken_by_me = listing.taken_by == viewer.id
    data.contact_phone = (
        listing.contact_phone
        if listing_service.can_see_phone(listing, viewer)
        else None
    )

    v_lat, v_lon = _as_float(viewer.search_latitude), _as_float(viewer.search_longitude)
    l_lat, l_lon = _as_float(listing.latitude), _as_float(listing.longitude)
    if None not in (v_lat, v_lon, l_lat, l_lon):
        data.distance_km = float(pricing_service.distance_km(v_lat, v_lon, l_lat, l_lon))

    return data


# ------------------------------------------------- aniq yo'llar avval

@router.get("/mine", response_model=List[ListingRead])
def my_listings(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
):
    """Faqat o'z e'lonlari."""
    items = listing_service.list_mine(db, current_user, skip, limit)
    return [_to_read(db, item, current_user) for item in items]


@router.get("/feed", response_model=List[ListingRead])
def feed(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    equipment_type: Optional[str] = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
):
    """
    Taxta: ochiq e'lonlar va ko'ruvchi olgan e'lonlar.

    O'z e'lonlari bu yerga tushmaydi — ular /listings/mine da.
    """
    items = listing_service.list_feed(db, current_user, equipment_type, skip, limit)
    return [_to_read(db, item, current_user) for item in items]


@router.post("/photos")
def upload_photo(
    file: UploadFile = File(...),
    current_user=Depends(get_current_user),
):
    """
    Rasmni yuklaydi va manzilini qaytaradi.

    E'lon YARATILGUNCHA yuklanadi: mijoz avval rasm tanlaydi, keyin
    "joylash" bosadi. Shuning uchun manzil e'longa emas, ilovaga qaytadi va
    e'lon yaratishda photos ro'yxatida keladi.
    """
    assert_not_frozen(current_user)
    return {"url": media.save_upload(file, "listings")}


# ---------------------------------------------------------------- amallar

@router.post("/", response_model=ListingRead)
def create_listing(
    data: ListingCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    listing = listing_service.create_listing(db, current_user, data)
    return _to_read(db, listing, current_user)


@router.get("/{listing_id}", response_model=ListingRead)
def get_listing(
    listing_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    listing = listing_service.get_listing(db, listing_id, current_user)
    return _to_read(db, listing, current_user)


@router.post("/{listing_id}/take", response_model=ListingRead)
def take(
    listing_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(role_checker(["owner", "admin"])),
):
    """Egasi e'lonni oladi. Kim birinchi bo'lsa — o'shaniki."""
    listing = listing_service.take_listing(db, listing_id, current_user)
    return _to_read(db, listing, current_user)


@router.post("/{listing_id}/confirm", response_model=ListingRead)
def confirm(
    listing_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Mijoz egasini tasdiqlaydi — shundan keyin telefonlar ochiladi."""
    listing = listing_service.confirm_listing(db, listing_id, current_user)
    return _to_read(db, listing, current_user)


@router.post("/{listing_id}/reject", response_model=ListingRead)
def reject(
    listing_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Mijozga ega yoqmadi — e'lon yana ochiq bo'ladi."""
    listing = listing_service.reject_taker(db, listing_id, current_user)
    return _to_read(db, listing, current_user)


@router.post("/{listing_id}/finish", response_model=ListingRead)
def finish(
    listing_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    listing = listing_service.finish_listing(db, listing_id, current_user)
    return _to_read(db, listing, current_user)


@router.post("/{listing_id}/cancel", response_model=ListingRead)
def cancel(
    listing_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    listing = listing_service.cancel_listing(db, listing_id, current_user)
    return _to_read(db, listing, current_user)
