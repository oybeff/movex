"""
Zayavkalar bo'yicha mantiq.

Katalogdan farqi shundaki, bu yerda mijoz aniq mashinani emas, TURNI
so'raydi, va zayavkani radiusdagi hamma mos egalar ko'radi.

Pul haqida bitta qoida bor va u buziladigan emas: ZAYAVKA VA TAKLIF PULNI
QIMIRLATMAYDI. Byudjet — mijozning mo'ljali, taklifdagi narx — egasining
so'ragani. Haqiqiy summa faqat taklif tanlangan paytda, odatdagi
create_order ichida, pricing_service hisobi bo'yicha aniqlanadi. Shu tufayli
eskrou, komissiya va muzlatish qoidalari o'zgarishsiz qoladi.
"""
import logging
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import List, Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.equipment_types import is_valid_type, type_name
from app.core.messages import normalize_language
from app.models.equipment import Equipment
from app.models.equipment_request import (
    REQUEST_TTL_HOURS,
    EquipmentRequest,
    RequestOffer,
)
from app.models.user import User
from app.schemas.order import OrderCreate
from app.services import notification_service, order_service, pricing_service

logger = logging.getLogger(__name__)

#: Bitta mijozda bir vaqtda ochiq tura oladigan zayavkalar soni.
#: Cheklovsiz bo'lsa, bitta hisob yuzlab zayavka yaratib, hamma egalarga
#: xabar yog'dirishi mumkin edi.
MAX_OPEN_REQUESTS_PER_CLIENT = 10


# --------------------------------------------------------------- yordamchi

def _now() -> datetime:
    return datetime.now(timezone.utc)


def _as_float(value) -> Optional[float]:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _within_radius(user: User, lat: Optional[float], lon: Optional[float]) -> bool:
    """
    Nuqta foydalanuvchining radiusiga tushadimi.

    Foydalanuvchi nuqtasini sozlamagan bo'lsa — True. Sozlamagan odam
    hech narsa ko'rmay qolmasligi kerak; radius bu filtr, taqiq emas.
    """
    u_lat = _as_float(user.search_latitude)
    u_lon = _as_float(user.search_longitude)
    if None in (u_lat, u_lon, lat, lon):
        return True

    radius = user.search_radius_km or 100
    return pricing_service.distance_km(u_lat, u_lon, lat, lon) <= Decimal(radius)


def expire_stale(db: Session) -> int:
    """Muddati o'tgan zayavkalarni yopadi. Ro'yxat so'ralganda chaqiriladi."""
    stale = (
        db.query(EquipmentRequest)
        .filter(
            EquipmentRequest.status == "open",
            EquipmentRequest.expires_at.isnot(None),
            EquipmentRequest.expires_at < _now(),
        )
        .all()
    )
    for request in stale:
        request.status = "expired"
    if stale:
        db.commit()
    return len(stale)


# ------------------------------------------------------------- zayavkalar

def create_request(db: Session, client: User, data) -> EquipmentRequest:
    """Mijoz zayavka beradi va radiusdagi egalarga xabar ketadi."""
    # Zayavkada tur QAT'IY tekshiriladi va normalize_type ishlatilmaydi.
    #
    # normalize_type notanish matnni jimgina 'other' ga aylantiradi. Katalog
    # uchun bu to'g'ri — u yerda eski erkin matnli yozuvlar bor. Zayavkada
    # esa turdan kimga xabar borishi kelib chiqadi: xato yozilgan tur
    # "Boshqa texnika" bo'lib qolsa, kerakli egalar zayavkani umuman
    # ko'rmaydi va mijoz nega javob yo'qligini tushunmaydi.
    #
    # Ilova turni ma'lumotnomadagi ro'yxatdan tanlaydi, shuning uchun
    # qat'iylik hech narsani buzmaydi.
    equipment_type = (data.equipment_type or "").strip()
    if not is_valid_type(equipment_type):
        raise HTTPException(
            400,
            f"Texnika turi noto'g'ri: {data.equipment_type!r}. "
            "Ro'yxatni /equipment/types dan oling.",
        )

    days = pricing_service.rental_days(data.start_date, data.end_date)
    if days <= 0:
        raise HTTPException(400, "Tugash sanasi boshlanish sanasidan oldin bo'lmasin")
    if days > pricing_service.MAX_RENTAL_DAYS:
        raise HTTPException(
            400, f"Ijara muddati {pricing_service.MAX_RENTAL_DAYS} kundan oshmasligi kerak"
        )

    open_count = (
        db.query(EquipmentRequest)
        .filter(
            EquipmentRequest.client_id == client.id,
            EquipmentRequest.status == "open",
        )
        .count()
    )
    if open_count >= MAX_OPEN_REQUESTS_PER_CLIENT:
        raise HTTPException(
            400,
            f"Ochiq zayavkalar soni {MAX_OPEN_REQUESTS_PER_CLIENT} tadan oshmasligi kerak. "
            "Avvalgilarini yoping.",
        )

    request = EquipmentRequest(
        client_id=client.id,
        equipment_type=equipment_type,
        start_date=data.start_date,
        end_date=data.end_date,
        delivery_latitude=str(data.delivery_latitude),
        delivery_longitude=str(data.delivery_longitude),
        delivery_address=data.delivery_address,
        budget=data.budget,
        comment=data.comment,
        status="open",
        expires_at=_now() + timedelta(hours=REQUEST_TTL_HOURS),
    )
    db.add(request)
    db.commit()
    db.refresh(request)

    _notify_owners_nearby(db, request)
    return request


def _notify_owners_nearby(db: Session, request: EquipmentRequest) -> None:
    """
    Mos texnikasi bor va radiusi yetadigan egalarga xabar.

    Xabar yuborilmasa ham zayavka qoladi — shuning uchun hamma xato
    yutiladi.
    """
    try:
        lat = _as_float(request.delivery_latitude)
        lon = _as_float(request.delivery_longitude)

        owner_ids = {
            row[0]
            for row in db.query(Equipment.owner_id)
            .filter(
                Equipment.type == request.equipment_type,
                Equipment.deleted_at.is_(None),
            )
            .distinct()
        }
        if not owner_ids:
            return

        owners = db.query(User).filter(User.id.in_(owner_ids)).all()
        created = []
        for owner in owners:
            if not _within_radius(owner, lat, lon):
                continue
            lang = normalize_language(owner.language)
            created.append(notification_service.create_localized(
                db, owner.id, "request_created",
                "request_created.title",
                "request_created.body_with_address"
                if request.delivery_address else "request_created.body",
                None, request.equipment_type, None,
                commit=False, language=lang,
                what=type_name(request.equipment_type, lang),
                start=request.start_date,
                end=request.end_date,
                address=request.delivery_address or "",
            ))
        db.commit()
        # Push commit'dan KEYIN: aks holda hali saqlanmagan xabarnoma
        # haqida bildirishnoma ketardi.
        notification_service.send_pending(db, created)
    except Exception:
        logger.exception("Zayavka xabarnomalari yuborilmadi: request=%s", request.id)
        db.rollback()


def list_client_requests(db: Session, client_id: int, skip=0, limit=50):
    expire_stale(db)
    return (
        db.query(EquipmentRequest)
        .filter(EquipmentRequest.client_id == client_id)
        .order_by(EquipmentRequest.created_at.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )


def list_open_for_owner(db: Session, owner: User, skip=0, limit=50):
    """
    Egaga ko'rsatiladigan ochiq zayavkalar: uning texnikasi turiga mos va
    radiusiga tushadiganlari.
    """
    expire_stale(db)

    own_types = {
        row[0]
        for row in db.query(Equipment.type)
        .filter(Equipment.owner_id == owner.id, Equipment.deleted_at.is_(None))
        .distinct()
    }
    if not own_types:
        return []

    candidates = (
        db.query(EquipmentRequest)
        .filter(
            EquipmentRequest.status == "open",
            EquipmentRequest.equipment_type.in_(own_types),
        )
        .order_by(EquipmentRequest.created_at.desc())
        .limit(limit * 4 + skip)  # radius filtridan keyin yetarli qolishi uchun
        .all()
    )

    visible = [
        r
        for r in candidates
        if _within_radius(
            owner, _as_float(r.delivery_latitude), _as_float(r.delivery_longitude)
        )
    ]
    return visible[skip : skip + limit]


def cancel_request(db: Session, request: EquipmentRequest, user: User) -> EquipmentRequest:
    if request.client_id != user.id and user.role != "admin":
        raise HTTPException(403, "Bu zayavka sizniki emas")
    if request.status != "open":
        raise HTTPException(400, "Faqat ochiq zayavkani bekor qilish mumkin")

    request.status = "cancelled"
    # Kutayotgan takliflarni ham yopamiz, aks holda ular osilib qoladi
    offers = (
        db.query(RequestOffer)
        .filter(RequestOffer.request_id == request.id, RequestOffer.status == "pending")
        .all()
    )
    for offer in offers:
        offer.status = "rejected"
    db.commit()
    db.refresh(request)

    created = [
        notification_service.create_localized(
            db, offer.owner_id, "request_cancelled",
            "request_cancelled.title", "request_cancelled.body",
            None, request.equipment_type, None, commit=False,
            request_id=request.id,
        )
        for offer in offers
    ]
    db.commit()
    notification_service.send_pending(db, created)
    return request


# --------------------------------------------------------------- takliflar

def create_offer(db: Session, request_id: int, owner: User, data) -> RequestOffer:
    """Egasi zayavkaga o'z narxi bilan javob beradi."""
    request = db.query(EquipmentRequest).filter(EquipmentRequest.id == request_id).first()
    if request is None:
        raise HTTPException(404, "Zayavka topilmadi")
    if request.status != "open":
        raise HTTPException(400, "Zayavka yopilgan")

    equipment = (
        db.query(Equipment)
        .filter(Equipment.id == data.equipment_id, Equipment.deleted_at.is_(None))
        .first()
    )
    if equipment is None:
        raise HTTPException(404, "Texnika topilmadi")
    if equipment.owner_id != owner.id:
        raise HTTPException(403, "Bu texnika sizniki emas")
    if equipment.type != request.equipment_type:
        raise HTTPException(400, "Texnika turi zayavkaga mos emas")

    exists = (
        db.query(RequestOffer)
        .filter(
            RequestOffer.request_id == request_id,
            RequestOffer.equipment_id == data.equipment_id,
            RequestOffer.status != "withdrawn",
        )
        .first()
    )
    if exists:
        raise HTTPException(400, "Bu texnika uchun taklif allaqachon yuborilgan")

    offer = RequestOffer(
        request_id=request_id,
        owner_id=owner.id,
        equipment_id=data.equipment_id,
        price_per_day=data.price_per_day,
        comment=data.comment,
        status="pending",
    )
    db.add(offer)
    db.commit()
    db.refresh(offer)

    notification_service.create_localized(
        db, request.client_id, "request_offer",
        "request_offer.title", "request_offer.body",
        None, request.equipment_type, equipment.model,
        model=equipment.model,
        price=f"{int(offer.price_per_day):,}".replace(",", " "),
    )
    return offer


def list_offers(db: Session, request: EquipmentRequest, user: User) -> List[RequestOffer]:
    """
    Takliflar ro'yxati.

    Mijoz o'z zayavkasidagi HAMMA taklifni ko'radi — u shundan tanlaydi.
    Egasi esa faqat O'ZINING taklifini: raqobatchilarning narxini ko'rish
    kerak emas.
    """
    query = db.query(RequestOffer).filter(RequestOffer.request_id == request.id)

    if user.role == "admin" or request.client_id == user.id:
        pass
    else:
        query = query.filter(RequestOffer.owner_id == user.id)

    return query.order_by(RequestOffer.created_at.asc()).all()


def withdraw_offer(db: Session, offer: RequestOffer, owner: User) -> RequestOffer:
    if offer.owner_id != owner.id and owner.role != "admin":
        raise HTTPException(403, "Bu taklif sizniki emas")
    if offer.status != "pending":
        raise HTTPException(400, "Faqat kutilayotgan taklifni olib tashlash mumkin")

    offer.status = "withdrawn"
    db.commit()
    db.refresh(offer)
    return offer


def accept_offer(db: Session, request_id: int, offer_id: int, client: User):
    """
    Mijoz taklifni tanlaydi — va shu yerda ODATDAGI BUYURTMA tug'iladi.

    Narx taklifdagi kunlik stavkadan olinadi, lekin umumiy summani baribir
    pricing_service hisoblaydi: komissiya va yetkazib berish har doim bir xil
    qoidada. Pul ham odatdagidek create_order ichida muzlatiladi.
    """
    request = (
        db.query(EquipmentRequest)
        .filter(EquipmentRequest.id == request_id)
        .with_for_update()
        .first()
    )
    if request is None:
        raise HTTPException(404, "Zayavka topilmadi")
    if request.client_id != client.id:
        raise HTTPException(403, "Bu zayavka sizniki emas")
    if request.status != "open":
        raise HTTPException(400, "Zayavka yopilgan")

    offer = (
        db.query(RequestOffer)
        .filter(RequestOffer.id == offer_id, RequestOffer.request_id == request_id)
        .first()
    )
    if offer is None:
        raise HTTPException(404, "Taklif topilmadi")
    if offer.status != "pending":
        raise HTTPException(400, "Taklif allaqachon yopilgan")

    order_in = OrderCreate(
        equipment_id=offer.equipment_id,
        start_date=request.start_date,
        end_date=request.end_date,
        delivery_latitude=request.delivery_latitude,
        delivery_longitude=request.delivery_longitude,
        delivery_address=request.delivery_address,
    )

    # Narx bazadagi taklifdan olinadi, so'rov tanasidan emas.
    order = order_service.create_order(
        db, order_in, client.id, price_per_day_override=Decimal(str(offer.price_per_day))
    )

    offer.status = "accepted"
    request.status = "assigned"
    request.selected_offer_id = offer.id
    request.order_id = order.id

    others = (
        db.query(RequestOffer)
        .filter(
            RequestOffer.request_id == request_id,
            RequestOffer.id != offer.id,
            RequestOffer.status == "pending",
        )
        .all()
    )
    for other in others:
        other.status = "rejected"
    db.commit()

    accepted_equipment = (
        db.query(Equipment).filter(Equipment.id == offer.equipment_id).first()
    )
    created = [notification_service.create_localized(
        db, offer.owner_id, "request_offer_accepted",
        "request_offer_accepted.title", "request_offer_accepted.body",
        order.id, request.equipment_type,
        accepted_equipment.model if accepted_equipment else None,
        commit=False,
    )]
    for other in others:
        created.append(notification_service.create_localized(
            db, other.owner_id, "request_offer_rejected",
            "request_offer_rejected.title", "request_offer_rejected.body",
            None, request.equipment_type, None, commit=False,
            request_id=request.id,
        ))
    db.commit()
    notification_service.send_pending(db, created)

    return request, order
