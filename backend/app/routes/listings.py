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
from app.db.session import get_db
from app.models.listing import Listing
from app.models.user import User
from app.routes.auth import get_current_user
from app.schemas.listing import (
    ListingCreate,
    ListingOfferCreate,
    ListingOfferRead,
    ListingRead,
)
from app.services import listing_service, pricing_service

router = APIRouter()


def _as_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _to_read(
    db: Session,
    listing: Listing,
    viewer: User,
    counts: Optional[dict] = None,
    marks: Optional[dict] = None,
) -> ListingRead:
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

    # Ro'yxat uchun sanoqlar oldindan beriladi (bitta so'rovda); bitta e'lon
    # so'ralganda shu yerda sanaladi.
    if counts is None:
        counts = listing_service.reaction_counts(db, [listing.id])[listing.id]
    if marks is None:
        marks = listing_service.viewer_marks(db, viewer.id, [listing.id])[listing.id]

    data.likes_count = counts["likes"]
    data.saves_count = counts["saves"]
    data.offers_count = counts["offers"]
    data.liked_by_me = marks["liked"]
    data.saved_by_me = marks["saved"]
    data.offered_by_me = marks["offered"]

    return data


def _to_read_many(db: Session, listings: List[Listing], viewer: User) -> List[ListingRead]:
    """
    Ro'yxat uchun: sanoqlar BITTA so'rovda olinadi.

    Har bir kartochka uchun alohida sanash 20 ta e'londa oltmishga yaqin
    so'rov berardi.
    """
    ids = [item.id for item in listings]
    counts = listing_service.reaction_counts(db, ids)
    marks = listing_service.viewer_marks(db, viewer.id, ids)
    return [
        _to_read(db, item, viewer, counts.get(item.id), marks.get(item.id))
        for item in listings
    ]


def _offer_to_read(db: Session, offer, listing: Listing, viewer: User) -> ListingOfferRead:
    data = ListingOfferRead.model_validate(offer)
    user = db.query(User).filter(User.id == offer.user_id).first()
    data.user_name = user.full_name if user else None

    # Telefon — faqat muallifga va faqat qabul qilingandan keyin, xuddi
    # e'lonning o'zidagi qoida bo'yicha: "taklif berdi" hali kelishuv emas.
    may_see = viewer.role == "admin" or (
        viewer.id == listing.client_id and offer.status == "accepted"
    )
    data.user_phone = (user.phone if user else None) if may_see else None
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
    return _to_read_many(db, items, current_user)


@router.get("/saved", response_model=List[ListingRead])
def saved_listings(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
):
    """
    Saqlanganlar — xatcho'p bosilgan e'lonlar.

    Yo'l "/{listing_id}" dan OLDIN turishi shart, aks holda FastAPI "saved"
    so'zini son deb o'qishga urinadi.
    """
    items = listing_service.list_saved(db, current_user, skip, limit)
    return _to_read_many(db, items, current_user)


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
    return _to_read_many(db, items, current_user)


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
    current_user=Depends(get_current_user),
):
    """
    E'lonni olish. Kim birinchi bo'lsa — o'shaniki.

    ROL TEKSHIRILMAYDI, va bu ataylab. Ilgari bu yerda faqat "owner" turardi,
    ya'ni e'longa javob berish faqat texnika egasiga ochiq edi. E'lonlar esa
    ikki tomonlama: mijoz ham ("gruzchik kerak"), ega ham ("ertaga ekskavator
    bo'sh") joylay oladi — demak javob beruvchi ham har ikkisi bo'lishi kerak,
    aks holda eganing e'loniga hech kim javob bera olmasdi.

    Cheklov bittasi va u xizmatda: o'z e'longni o'zing ololmaysan.
    """
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


# ------------------------------------------------------- takliflar (narx)

@router.post("/{listing_id}/offers", response_model=ListingOfferRead)
def create_offer(
    listing_id: int,
    data: ListingOfferCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    O'z narxini taklif qilish.

    "Olaman" tugmasi joyida qoladi — u muallif byudjetiga rozilik. Taklif
    esa boshqa summa: muallif kelganlaridan birini tanlaydi.

    ROL TEKSHIRILMAYDI: e'lon ikki tomonlama, taklifni ham mijoz, ham ega
    bera oladi. Cheklov bittasi — o'z e'loningga taklif berib bo'lmaydi.
    """
    offer = listing_service.make_offer(
        db, listing_id, current_user, data.price, data.comment
    )
    listing = db.query(Listing).filter(Listing.id == listing_id).first()
    return _offer_to_read(db, offer, listing, current_user)


@router.get("/{listing_id}/offers", response_model=List[ListingOfferRead])
def list_offers(
    listing_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    Takliflar. Hammasini faqat muallif va admin ko'radi.

    Ijrochiga faqat o'zinikisi qaytadi: aks holda u raqiblarining narxini
    ko'rib, ularni bir so'mga arzonlatib qo'yardi.
    """
    listing = db.query(Listing).filter(Listing.id == listing_id).first()
    if listing is None:
        raise HTTPException(404, "E'lon topilmadi")
    offers = listing_service.list_offers(db, listing_id, current_user)
    return [_offer_to_read(db, offer, listing, current_user) for offer in offers]


@router.delete("/{listing_id}/offers/mine")
def withdraw_offer(
    listing_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Taklifni qaytarib olish."""
    listing_service.withdraw_offer(db, listing_id, current_user)
    return {"status": "ok"}


@router.post("/{listing_id}/offers/{offer_id}/accept", response_model=ListingRead)
def accept_offer(
    listing_id: int,
    offer_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    Muallif taklifni tanladi: e'lon tasdiqlanadi va telefonlar ochiladi.

    Oraliq "taken" holati kerak emas — tanlash muallifning o'zi tomonidan
    qilinadi, ya'ni bu allaqachon tasdiq.
    """
    listing = listing_service.accept_offer(db, listing_id, offer_id, current_user)
    return _to_read(db, listing, current_user)


# --------------------------------------------- yoqtirish va saqlash

def _reaction(db: Session, listing_id: int, user: User, kind: str, on: bool) -> ListingRead:
    """
    Yoqtirish/saqlashni o'zgartirib, e'lonni qaytaradi.

    DIQQAT: bu yerda listing_service.get_listing ISHLATILMAYDI. U ko'rishlar
    sanog'ini oshiradi, ya'ni har bir yurakcha bosilganda e'lon yana bir
    marta "ko'rilgan" bo'lib qolardi va statistika yolg'on ko'rsatardi.
    """
    listing_service.set_reaction(db, listing_id, user, kind, on)
    listing = db.query(Listing).filter(Listing.id == listing_id).first()
    if listing is None:
        raise HTTPException(404, "E'lon topilmadi")
    return _to_read(db, listing, user)


@router.post("/{listing_id}/like", response_model=ListingRead)
def like(
    listing_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    return _reaction(db, listing_id, current_user, "like", True)


@router.delete("/{listing_id}/like", response_model=ListingRead)
def unlike(
    listing_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    return _reaction(db, listing_id, current_user, "like", False)


@router.post("/{listing_id}/save", response_model=ListingRead)
def save(
    listing_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    return _reaction(db, listing_id, current_user, "save", True)


@router.delete("/{listing_id}/save", response_model=ListingRead)
def unsave(
    listing_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    return _reaction(db, listing_id, current_user, "save", False)
