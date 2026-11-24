"""
Admin panel: buyurtmalar ustidan amallar (Figma «Admin panel» → 02).

O3 · Bekor qilish — hamma turdagi buyurtma: texnika (orders), tezkor
zayavka (equipment_requests, hali hech kim olmagan), yuk tashish
(freight_orders), material (material_orders). Pul FAQAT qaytadi
(muzlatish yechiladi) — jarima yo'q: Sherzodbek 21.11 «shtraf yo'q»
degan, kompensatsiya esa alohida sozlama (compensation_service).

O4 · Ijrochini almashtirish — mos ijrochilar ro'yxati (nega mos emasligi
yozilgan) va tayinlash. Yuk/material: haydovchi; texnika: boshqa egasining
shu turdagi texnikasi. Naqd buyurtmada yangi ijrochining komissiyasi uning
balansida muzlatiladi (ilovadagi qabul qilish bilan bir xil qoida),
eskisiniki yechiladi.

Pul mantig'i — servislardagi bilan bir xil yordamchilar orqali: panel o'zi
hech narsani hisoblamaydi. Har bir amal admin_actions'ga yoziladi.
"""
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import List, Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.admin_action import AdminAction
from app.models.balance import Balance
from app.models.catalog import DeliveryDriverCategory, DeliveryDriverProfile, DeliveryVehicleRow, FreightOrder
from app.models.equipment import Equipment
from app.models.equipment_request import EquipmentRequest
from app.models.material import MaterialOrder, MaterialProduct
from app.models.order import Order
from app.models.user import User
from app.schemas.order import OrderUpdate
from app.services import (
    delivery_service,
    freight_service,
    material_service,
    notification_service,
    order_service,
    pricing_service,
    request_service,
)

KINDS = ("equipment", "request", "freight", "material")

#: O3 sabablari — panel shu kodlarni yuboradi, bazada kod saqlanadi
CANCEL_REASONS = {
    "client_request": "Mijoz so'rovi bilan",
    "performer_late": "Ijrochi kechikdi / kelmadi",
    "technical": "Texnik nosozlik (ilova / to'lov)",
    "fraud": "Firibgarlik shubhasi",
    "other": "Boshqa sabab",
}

ACTIVE_FREIGHT = ("accepted", "loaded", "arrived")
ACTIVE_DELIVERY = ("accepted", "picked_up", "arrived")


def _dec(v) -> Decimal:
    return Decimal(str(v)) if v is not None else Decimal("0")


def _now():
    return datetime.now(timezone.utc)


def _admin(db: Session, admin_id: int) -> User:
    u = db.query(User).filter(User.id == admin_id).first()
    if u is None or u.role != "admin":
        raise HTTPException(403, "Admin topilmadi")
    return u


def _log(db: Session, admin_id: int, action: str, entity: str, entity_id: int, payload: dict) -> None:
    db.add(AdminAction(admin_id=admin_id, action=action, entity=entity, entity_id=entity_id, payload=payload))
    db.commit()


def _notify(db: Session, user_id: Optional[int], type_: str, key: str, order_id: int) -> None:
    if not user_id:
        return
    try:
        notification_service.create_localized(
            db, user_id, type_, f"{key}.title", f"{key}.body", None, None, None, order_number=order_id)
    except Exception:  # noqa: BLE001 — bildirishnoma xatosi amalni buzmasin
        db.rollback()


def _unfreeze(db: Session, user_id: Optional[int], amount: Decimal) -> None:
    if amount <= 0 or not user_id:
        return
    bal = db.query(Balance).filter(Balance.user_id == user_id).with_for_update().first()
    if bal is not None:
        cur = _dec(bal.frozen_balance)
        bal.frozen_balance = cur - amount if cur >= amount else Decimal("0")


def _freeze_commission(db: Session, user_id: int, commission: Decimal) -> Decimal:
    """Naqd buyurtma: ijrochining komissiyasini muzlatish. Yetmasa — 402."""
    if commission <= 0:
        return Decimal("0")
    bal = freight_service._balance(db, user_id)
    if _dec(bal.balance) - _dec(bal.frozen_balance) < commission:
        db.rollback()
        raise HTTPException(402, f"Ijrochi balansida komissiya uchun {int(commission):,} so'm yo'q"
                            .replace(",", " "))
    bal.frozen_balance = _dec(bal.frozen_balance) + commission
    return commission


# =================================================================== O3 · bekor qilish

def cancel(db: Session, kind: str, order_id: int, admin_id: int, reason: str,
           note: Optional[str] = None, notify: bool = True) -> dict:
    if kind not in KINDS:
        raise HTTPException(400, "Noma'lum buyurtma turi")
    if reason not in CANCEL_REASONS:
        raise HTTPException(400, "Sabab majburiy")
    admin = _admin(db, admin_id)
    released = Decimal("0")

    if kind == "equipment":
        o = db.query(Order).filter(Order.id == order_id).first()
        if o is None:
            raise HTTPException(404, "Buyurtma topilmadi")
        if o.status not in ("pending", "confirmed"):
            raise HTTPException(409, f"Buyurtma yopilgan: {o.status}")
        released = _dec(o.frozen_amount)
        # Mijoz nomidan — pul mantig'i (escrow, naqd garov, karta holdi)
        # update_order'da, uni takrorlamaymiz. Kim bekor qilgani pastda.
        order_service.update_order(db, o.id, OrderUpdate(status="cancelled"), o.user_id)
        db.refresh(o)
        o.cancelled_by = "admin"
        o.cancel_reason = reason
        db.commit()
        status = o.status

    elif kind == "request":
        r = db.query(EquipmentRequest).filter(EquipmentRequest.id == order_id).first()
        if r is None:
            raise HTTPException(404, "Zayavka topilmadi")
        released = _dec(r.frozen_amount)
        request_service.cancel_request(db, r, admin)
        if notify:
            _notify(db, r.client_id, "request_cancelled", "admin_cancelled", r.id)
        status = r.status

    elif kind == "freight":
        o = freight_service._lock(db, order_id)
        if o.status in ("done", "cancelled"):
            raise HTTPException(409, f"Buyurtma yopilgan: {o.status}")
        released = _dec(o.frozen_amount)
        _unfreeze(db, o.client_id, released)
        o.frozen_amount = Decimal("0")
        driver_id = o.driver_id
        freight_service._release_driver(db, o)
        o.status = "cancelled"
        o.cancelled_by = "admin"
        o.cancel_reason = reason
        db.commit()
        if notify:
            _notify(db, o.client_id, "freight_cancelled", "admin_cancelled", o.id)
            _notify(db, driver_id, "freight_cancelled", "admin_cancelled", o.id)
        status = o.status

    else:  # material
        o = db.query(MaterialOrder).filter(MaterialOrder.id == order_id).first()
        if o is None:
            raise HTTPException(404, "Buyurtma topilmadi")
        released = _dec(o.frozen_amount)
        material_service.cancel_order(db, order_id, admin)
        db.refresh(o)
        o.cancelled_by = "admin"
        o.cancel_reason = reason
        db.commit()
        if notify:
            _notify(db, o.buyer_id, "material_cancelled", "admin_cancelled", o.id)
        status = o.status

    _log(db, admin_id, "order_cancel", kind, order_id,
         {"reason": reason, "note": note, "released": str(released), "notify": notify})
    return {"kind": kind, "id": order_id, "status": status, "released": released}


# =================================================================== O4 · ijrochilar

def _vehicle(db: Session, code: str):
    return db.query(DeliveryVehicleRow).filter(DeliveryVehicleRow.code == code).first()


def _busy_driver_ids(db: Session) -> set:
    a = {r[0] for r in db.query(FreightOrder.driver_id)
         .filter(FreightOrder.status.in_(ACTIVE_FREIGHT), FreightOrder.driver_id.isnot(None))}
    b = {r[0] for r in db.query(MaterialOrder.driver_id)
         .filter(MaterialOrder.delivery_status.in_(ACTIVE_DELIVERY), MaterialOrder.driver_id.isnot(None))}
    return a | b


def _available(db: Session, user_id: int) -> Decimal:
    bal = db.query(Balance).filter(Balance.user_id == user_id).first()
    return (_dec(bal.balance) - _dec(bal.frozen_balance)) if bal else Decimal("0")


def _account_problem(u: Optional[User]) -> Optional[str]:
    if u is None:
        return "Foydalanuvchi topilmadi"
    if u.is_blocked:
        return "Akkaunt bloklangan"
    if u.is_frozen:
        return "Akkaunt muzlatilgan"
    return None


def _driver_rows(db: Session, vehicle_code: str, exclude: set, lat, lon) -> list:
    rows = (db.query(DeliveryDriverProfile, User)
            .join(User, User.id == DeliveryDriverProfile.user_id)
            .filter(DeliveryDriverProfile.vehicle_code == vehicle_code).all())
    out = []
    for p, u in rows:
        if u.id in exclude:
            continue
        dist = None
        if None not in (p.latitude, p.longitude, lat, lon):
            dist = pricing_service.distance_km(float(p.latitude), float(p.longitude), float(lat), float(lon))
        fresh = p.location_at is not None and p.location_at > _now() - timedelta(minutes=2)
        out.append((p, u, dist, bool(p.is_online and fresh)))
    return out


def candidates(db: Session, kind: str, order_id: int) -> dict:
    busy = _busy_driver_ids(db)
    out: List[dict] = []

    if kind == "freight":
        o = db.query(FreightOrder).filter(FreightOrder.id == order_id).first()
        if o is None:
            raise HTTPException(404, "Buyurtma topilmadi")
        commission = pricing_service.calculate_commission(db, _dec(o.price), _dec(o.price))
        for p, u, dist, online in _driver_rows(db, o.vehicle_code, {o.client_id}, o.from_latitude, o.from_longitude):
            reason = _account_problem(u)
            if reason is None and o.body_type and p.body_type != o.body_type:
                reason = "Kuzov turi mos emas"
            if reason is None and u.id in busy and u.id != o.driver_id:
                reason = "Boshqa buyurtmada band"
            if reason is None and o.payment_method == "cash" and commission > 0 and _available(db, u.id) < commission:
                reason = f"Balansida komissiya ({int(commission):,} so'm) yo'q".replace(",", " ")
            out.append(_cand(u, p.plate, p.vehicle_code, dist, online, reason, u.id == o.driver_id))
        current = o.driver_id
        can = o.status in ("searching", "accepted")
        note = None if can else "Yuk ortilgandan keyin haydovchini almashtirib bo'lmaydi"

    elif kind == "material":
        o = db.query(MaterialOrder).filter(MaterialOrder.id == order_id).first()
        if o is None:
            raise HTTPException(404, "Buyurtma topilmadi")
        product = db.query(MaterialProduct).filter(MaterialProduct.id == o.product_id).first()
        category = delivery_service.TYPE_TO_CATEGORY.get(product.material_type) if product else None
        for p, u, dist, online in _driver_rows(db, o.vehicle_code, {o.buyer_id, o.seller_id},
                                               product.latitude if product else None,
                                               product.longitude if product else None):
            reason = _account_problem(u)
            if reason is None and category is not None:
                mins = {c.category_code: c.min_quantity for c in db.query(DeliveryDriverCategory)
                        .filter(DeliveryDriverCategory.user_id == u.id)}
                if category not in mins:
                    reason = "Bu tovarni tashimaydi"
                elif _dec(o.quantity) < _dec(mins[category]):
                    reason = "Miqdor haydovchi minimumidan kam"
            if reason is None and u.id in busy and u.id != o.driver_id:
                reason = "Boshqa buyurtmada band"
            if reason is None and o.delivery_payment == "cash":
                fee = delivery_service._driver_fee(o, p, _vehicle(db, p.vehicle_code))
                com = pricing_service.calculate_commission(db, fee, fee)
                if com > 0 and _available(db, u.id) < com:
                    reason = f"Balansida komissiya ({int(com):,} so'm) yo'q".replace(",", " ")
            out.append(_cand(u, p.plate, p.vehicle_code, dist, online, reason, u.id == o.driver_id))
        current = o.driver_id
        can = (o.dispatch == "driver" and o.status == MaterialOrder.STATUS_CONFIRMED
               and o.delivery_status in ("searching", "accepted"))
        note = None if can else ("Haydovchi tovarni olgan — almashtirib bo'lmaydi"
                                 if o.delivery_status in ("picked_up", "arrived")
                                 else "Buyurtma haydovchi qidirish bosqichida emas")

    elif kind == "equipment":
        o = db.query(Order).filter(Order.id == order_id).first()
        if o is None:
            raise HTTPException(404, "Buyurtma topilmadi")
        cur_eq = db.query(Equipment).filter(Equipment.id == o.equipment_id).first()
        busy_owners = {r[0] for r in db.query(Equipment.owner_id).join(Order, Order.equipment_id == Equipment.id)
                       .filter(Order.status == "confirmed", Order.finished_at.is_(None), Order.id != o.id)}
        rows = (db.query(Equipment, User).join(User, User.id == Equipment.owner_id)
                .filter(Equipment.type == (cur_eq.type if cur_eq else None),
                        Equipment.deleted_at.is_(None), Equipment.id != o.equipment_id,
                        User.id != o.user_id).all())
        for e, u in rows:
            dist = None
            if None not in (e.latitude, e.longitude, o.delivery_latitude, o.delivery_longitude):
                dist = pricing_service.distance_km(float(e.latitude), float(e.longitude),
                                                   float(o.delivery_latitude), float(o.delivery_longitude))
            reason = _account_problem(u)
            if reason is None and not e.available:
                reason = "Texnika band deb belgilangan"
            if reason is None and u.id in busy_owners:
                reason = "Boshqa buyurtmada band"
            if reason is None and o.payment_method == "cash" and _dec(o.commission) > 0 \
                    and _available(db, u.id) < _dec(o.commission):
                reason = f"Balansida komissiya ({int(o.commission):,} so'm) yo'q".replace(",", " ")
            c = _cand(u, e.plate_number, e.type, dist, None, reason, False)
            c["equipment_id"] = e.id
            c["model"] = e.model
            out.append(c)
        current = cur_eq.owner_id if cur_eq else None
        can = o.status in ("pending", "confirmed") and o.started_at is None
        note = None if can else ("Ish boshlangan — texnikani almashtirib bo'lmaydi"
                                 if o.started_at else f"Buyurtma faol emas: {o.status}")
    else:
        raise HTTPException(400, "Bu turdagi buyurtmada ijrochi yo'q")

    out.sort(key=lambda c: (c["reason"] is not None, c["current"],
                            c["distance_km"] if c["distance_km"] is not None else 10 ** 6))
    return {"can_reassign": can, "note": note, "current_user_id": current, "candidates": out}


def _cand(u: User, plate, vehicle, dist, online, reason, current) -> dict:
    return {
        "user_id": u.id, "name": u.full_name, "phone": u.phone, "plate": plate, "vehicle": vehicle,
        "distance_km": float(dist.quantize(Decimal("0.1"))) if dist is not None else None,
        "online": online, "reason": reason, "current": current,
    }


# =================================================================== O4 · tayinlash

def reassign(db: Session, kind: str, order_id: int, admin_id: int,
             target_user_id: Optional[int] = None, equipment_id: Optional[int] = None,
             note: Optional[str] = None) -> dict:
    """
    target_user_id=None (yuk/material) — haydovchini olib, buyurtmani qayta
    qidiruvga qaytarish. Texnikada equipment_id majburiy.
    """
    _admin(db, admin_id)
    info = candidates(db, kind, order_id)
    if not info["can_reassign"]:
        raise HTTPException(409, info["note"] or "Almashtirib bo'lmaydi")
    if kind == "equipment":
        if not equipment_id:
            raise HTTPException(400, "Texnikani tanlang")
        cand = next((c for c in info["candidates"] if c.get("equipment_id") == equipment_id), None)
    elif target_user_id is not None:
        cand = next((c for c in info["candidates"] if c["user_id"] == target_user_id), None)
    else:
        cand = None
    if (kind == "equipment" or target_user_id is not None) and (cand is None or cand["reason"] or cand["current"]):
        raise HTTPException(409, (cand or {}).get("reason") or "Bu ijrochi mos emas")

    old_user = None
    if kind == "freight":
        o = freight_service._lock(db, order_id)
        old_user = o.driver_id
        freight_service._release_driver(db, o)
        o.driver_id = None
        o.driver_fee = None
        o.driver_commission = Decimal("0")
        o.accepted_at = None
        o.status = "searching"
        if target_user_id is not None:
            fee = _dec(o.price)
            commission = pricing_service.calculate_commission(db, fee, fee)
            if o.payment_method == "cash":
                o.driver_frozen = _freeze_commission(db, target_user_id, commission)
            o.driver_id = target_user_id
            o.driver_fee = fee
            o.driver_commission = commission
            o.status = "accepted"
            o.accepted_at = _now()
        db.commit()
        _notify(db, old_user, "freight_cancelled", "admin_unassigned", o.id)
        if target_user_id is not None:
            _notify(db, target_user_id, "order_assigned", "order_assigned", o.id)
            _notify(db, o.client_id, "freight_driver_found", "freight_driver_found", o.id)
        status = o.status

    elif kind == "material":
        o = delivery_service._lock(db, order_id)
        old_user = o.driver_id
        delivery_service.release_driver(db, o)
        o.driver_id = None
        o.driver_fee = None
        o.driver_commission = Decimal("0")
        o.accepted_at = None
        o.delivery_status = "searching"
        if target_user_id is not None:
            p = db.query(DeliveryDriverProfile).filter(DeliveryDriverProfile.user_id == target_user_id).first()
            fee = delivery_service._driver_fee(o, p, _vehicle(db, p.vehicle_code))
            commission = pricing_service.calculate_commission(db, fee, fee)
            if o.delivery_payment == "cash":
                o.driver_frozen = _freeze_commission(db, target_user_id, commission)
            o.driver_id = target_user_id
            o.driver_fee = fee
            o.driver_commission = commission
            o.delivery_status = "accepted"
            o.accepted_at = _now()
        db.commit()
        _notify(db, old_user, "material_cancelled", "admin_unassigned", o.id)
        if target_user_id is not None:
            _notify(db, target_user_id, "order_assigned", "order_assigned", o.id)
            _notify(db, o.buyer_id, "material_driver_found", "material_driver_found", o.id)
        status = o.delivery_status

    else:  # equipment
        o = db.query(Order).filter(Order.id == order_id).with_for_update().first()
        old_eq = db.query(Equipment).filter(Equipment.id == o.equipment_id).first()
        old_user = old_eq.owner_id if old_eq else None
        new_owner = cand["user_id"]
        if o.payment_method == "cash":
            _unfreeze(db, old_user, _dec(o.owner_frozen))
            o.owner_frozen = _freeze_commission(db, new_owner, _dec(o.commission))
        o.equipment_id = equipment_id
        o.departed_at = None
        o.arrived_at = None
        o.delay_minutes = None
        o.delay_reason = None
        db.commit()
        _notify(db, old_user, "order_cancelled", "admin_unassigned", o.id)
        _notify(db, new_owner, "order_assigned", "order_assigned", o.id)
        status = o.status

    _log(db, admin_id, "order_reassign" if target_user_id or equipment_id else "order_requeue", kind, order_id,
         {"from_user": old_user, "to_user": target_user_id or (cand or {}).get("user_id"),
          "equipment_id": equipment_id, "note": note})
    return {"kind": kind, "id": order_id, "status": status}
