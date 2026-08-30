"""
Zayavkalar: /requests/*

Mijoz zayavka beradi, egalar taklif yuboradi, mijoz bittasini tanlaydi.
Tanlangan paytda odatdagi buyurtma yaratiladi.

DIQQAT: aniq yo'llar parametrli yo'ldan OLDIN turishi shart. /requests/feed
va /requests/area — /requests/{request_id} dan yuqorida, aks holda FastAPI
"feed" so'zini son deb o'qishga urinadi. Loyihada bu xato ikki marta
bo'lgan.
"""
from decimal import Decimal
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.roles import role_checker
from app.db.session import get_db
from app.models.equipment import Equipment
from app.models.equipment_request import EquipmentRequest, RequestOffer
from app.models.user import User
from app.routes.auth import get_current_user
from app.schemas.equipment_request import (
    AcceptOfferResult,
    OfferCreate,
    OfferRead,
    RequestCreate,
    RequestRead,
    RequestWithOffers,
    SearchAreaRead,
    SearchAreaUpdate,
)
from app.services import pricing_service, request_service

router = APIRouter()


# ------------------------------------------------------------- yordamchi

def _as_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _offers_count(db: Session, request_id: int) -> int:
    return (
        db.query(RequestOffer)
        .filter(RequestOffer.request_id == request_id, RequestOffer.status == "pending")
        .count()
    )


def _to_read(db: Session, request: EquipmentRequest, viewer: User = None) -> RequestRead:
    data = RequestRead.model_validate(request)
    data.offers_count = _offers_count(db, request.id)

    if viewer is not None:
        v_lat = _as_float(viewer.search_latitude)
        v_lon = _as_float(viewer.search_longitude)
        r_lat = _as_float(request.delivery_latitude)
        r_lon = _as_float(request.delivery_longitude)
        if None not in (v_lat, v_lon, r_lat, r_lon):
            data.distance_km = float(
                pricing_service.distance_km(v_lat, v_lon, r_lat, r_lon)
            )
    return data


def _offer_to_read(db: Session, offer: RequestOffer, days: int) -> OfferRead:
    data = OfferRead.model_validate(offer)
    equipment = db.query(Equipment).filter(Equipment.id == offer.equipment_id).first()
    if equipment is not None:
        data.equipment_type = equipment.type
        data.equipment_model = equipment.model
    owner = db.query(User).filter(User.id == offer.owner_id).first()
    if owner is not None:
        data.owner_name = owner.full_name
    data.estimated_subtotal = Decimal(str(offer.price_per_day)) * days
    return data


def _get_request(db: Session, request_id: int) -> EquipmentRequest:
    request = (
        db.query(EquipmentRequest).filter(EquipmentRequest.id == request_id).first()
    )
    if request is None:
        raise HTTPException(404, "Zayavka topilmadi")
    return request


# ------------------------------------------------- qidiruv radiusi (area)
# Bu yo'llar /{request_id} dan OLDIN turishi shart.

@router.get("/area", response_model=SearchAreaRead)
def get_search_area(current_user=Depends(get_current_user)):
    """Foydalanuvchining qidiruv nuqtasi va radiusi."""
    return SearchAreaRead(
        latitude=_as_float(current_user.search_latitude),
        longitude=_as_float(current_user.search_longitude),
        radius_km=current_user.search_radius_km or 100,
    )


@router.put("/area", response_model=SearchAreaRead)
def set_search_area(
    data: SearchAreaUpdate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    Radiusni o'zgartirish.

    Ega uchun: shu radiusdagi zayavkalar haqida xabar keladi.
    Mijoz uchun: katalog va xarita shu radius bo'yicha filtrlanadi.
    """
    user = db.query(User).filter(User.id == current_user.id).one()
    user.search_latitude = data.latitude
    user.search_longitude = data.longitude
    user.search_radius_km = data.radius_km
    db.commit()
    db.refresh(user)
    return SearchAreaRead(
        latitude=_as_float(user.search_latitude),
        longitude=_as_float(user.search_longitude),
        radius_km=user.search_radius_km,
    )


# ------------------------------------------------------- egaga: lenta
# Ham /{request_id} dan oldin.

@router.get("/feed", response_model=List[RequestRead])
def owner_feed(
    db: Session = Depends(get_db),
    current_user=Depends(role_checker(["owner", "admin"])),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
):
    """Egaga: turi mos va radiusiga tushadigan ochiq zayavkalar."""
    items = request_service.list_open_for_owner(db, current_user, skip, limit)
    return [_to_read(db, r, current_user) for r in items]


# ----------------------------------------------------- mijozga: zayavkalar

@router.post("/", response_model=RequestRead)
def create_request(
    data: RequestCreate,
    db: Session = Depends(get_db),
    current_user=Depends(role_checker(["client", "admin"])),
):
    request = request_service.create_request(db, current_user, data)
    return _to_read(db, request)


@router.get("/", response_model=List[RequestRead])
def my_requests(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
):
    """Faqat o'z zayavkalari. Boshqalarnikini bu yerdan ko'rib bo'lmaydi."""
    items = request_service.list_client_requests(db, current_user.id, skip, limit)
    return [_to_read(db, r) for r in items]


@router.get("/{request_id}", response_model=RequestWithOffers)
def get_request(
    request_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    Bitta zayavka takliflari bilan.

    Mijoz hamma taklifni ko'radi, egasi — faqat o'zinikini. Ochiq zayavkani
    har qanday ega ko'ra oladi (u shunga taklif yuborishi kerak), yopilganini
    esa faqat ishtirokchilar.
    """
    request = _get_request(db, request_id)

    is_client = request.client_id == current_user.id
    is_admin = current_user.role == "admin"
    has_offer = (
        db.query(RequestOffer)
        .filter(
            RequestOffer.request_id == request_id,
            RequestOffer.owner_id == current_user.id,
        )
        .first()
        is not None
    )
    is_open_for_owners = request.status == "open" and current_user.role == "owner"

    if not (is_client or is_admin or has_offer or is_open_for_owners):
        raise HTTPException(403, "Bu zayavkaga ruxsat yo'q")

    days = pricing_service.rental_days(request.start_date, request.end_date)
    offers = request_service.list_offers(db, request, current_user)

    data = RequestWithOffers.model_validate(_to_read(db, request, current_user))
    data.offers = [_offer_to_read(db, o, days) for o in offers]
    return data


@router.post("/{request_id}/cancel", response_model=RequestRead)
def cancel_request(
    request_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    request = _get_request(db, request_id)
    request = request_service.cancel_request(db, request, current_user)
    return _to_read(db, request)


# --------------------------------------------------------------- takliflar

@router.post("/{request_id}/offers", response_model=OfferRead)
def create_offer(
    request_id: int,
    data: OfferCreate,
    db: Session = Depends(get_db),
    current_user=Depends(role_checker(["owner", "admin"])),
):
    offer = request_service.create_offer(db, request_id, current_user, data)
    request = _get_request(db, request_id)
    days = pricing_service.rental_days(request.start_date, request.end_date)
    return _offer_to_read(db, offer, days)


@router.delete("/{request_id}/offers/{offer_id}", response_model=OfferRead)
def withdraw_offer(
    request_id: int,
    offer_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    offer = (
        db.query(RequestOffer)
        .filter(RequestOffer.id == offer_id, RequestOffer.request_id == request_id)
        .first()
    )
    if offer is None:
        raise HTTPException(404, "Taklif topilmadi")

    offer = request_service.withdraw_offer(db, offer, current_user)
    request = _get_request(db, request_id)
    days = pricing_service.rental_days(request.start_date, request.end_date)
    return _offer_to_read(db, offer, days)


@router.post("/{request_id}/offers/{offer_id}/accept", response_model=AcceptOfferResult)
def accept_offer(
    request_id: int,
    offer_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    Taklifni tanlash — shu yerda buyurtma yaratiladi va pul muzlatiladi.
    Mablag' yetmasa create_order 400 qaytaradi va zayavka ochiq qoladi.
    """
    request, order = request_service.accept_offer(db, request_id, offer_id, current_user)
    return AcceptOfferResult(request=_to_read(db, request), order_id=order.id)
