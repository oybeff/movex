"""
Доставка стройматериалов водителем «как такси» (23.11.2026, ТЗ Шерзодбека).

Водитель в MoveX GO Driver выбирает свою машину из списка админки
(Damas … HOWO), отмечает, что возит, и минимум по каждой категории
(«Labo — penoblok от 50 dona»). Его точка — GPS телефона, приходит с
каждым опросом, пока он онлайн.

Заказ уходит водителям, когда ПРОДАВЕЦ его принял (товар готов):
- машина водителя = машина заказа (её подобрал сервер по весу или выбрал
  клиент);
- категория товара есть у водителя, и количество не меньше его минимума;
- водитель не дальше `delivery_search_radius_km` от склада продавца.
Кто первый принял — тот и везёт (FOR UPDATE, опоздавшему 409).

Деньги:
- товар — эскроу, как было: заморожен у клиента, продавцу после
  «Yetkazildi» минус комиссия (теперь — только с товара);
- доставка — водителю. Цена — расчёт по ценам админки (delivery_fee
  заказа); своя цена водителя действует, только если она НИЖЕ: клиент не
  платит больше, чем видел на экране;
- оплата доставки с Go wallet — заморожена вместе с товаром, при
  «Yetkazildi» уходит водителю минус комиссия; наличными — водитель
  берёт в руки, а комиссия замораживается на ЕГО балансе при принятии
  (как в тарифном заказе за наличные: не хватает — 402) и списывается
  при завершении.
"""
from datetime import datetime, timezone
from decimal import ROUND_CEILING, Decimal
from typing import List, Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core import delivery_vehicles
from app.core.account_state import assert_not_frozen
from app.models.app_settings import AppSettings
from app.models.balance import Balance, BalanceTransaction
from app.models.catalog import (
    DeliveryDriverCategory,
    DeliveryDriverProfile,
    DeliveryVehicleRow,
    MaterialCategory,
)
from app.models.material import MaterialOrder, MaterialProduct
from app.models.user import User
from app.services import notification_service, pricing_service
from app.services.balance_service import get_or_create_balance

#: Тип товара (material_types.py) → категория водителя (ТЗ). Тип без
#: категории (арматура, доски…) уходит всем водителям с нужной машиной.
TYPE_TO_CATEGORY = {
    "brick": "fired_brick",
    "gas_block": "gas_block",
    "cement": "cement",
    "sand": "sand",
    "gravel": "gravel",
    "stone": "stone",
}

DEFAULT_RADIUS_KM = Decimal("30")


def _dec(v, default="0") -> Decimal:
    if v is None or v == "":
        return Decimal(default)
    return Decimal(str(v))


def _now():
    return datetime.now(timezone.utc)


def _round(v: Decimal) -> Decimal:
    return v.quantize(Decimal("1"), rounding=ROUND_CEILING)


def radius_km(db: Session) -> Decimal:
    row = db.query(AppSettings).filter(AppSettings.key == "delivery_search_radius_km").first()
    try:
        value = Decimal(str(row.value)) if row and row.value not in (None, "") else DEFAULT_RADIUS_KM
    except Exception:
        value = DEFAULT_RADIUS_KM
    return value if value > 0 else DEFAULT_RADIUS_KM


# ---------------------------------------------------------------- профиль

def categories(db: Session) -> List[MaterialCategory]:
    return (
        db.query(MaterialCategory)
        .filter(MaterialCategory.is_enabled.is_(True))
        .order_by(MaterialCategory.sort_order)
        .all()
    )


def profile_dict(db: Session, user: User) -> dict:
    p = db.query(DeliveryDriverProfile).filter(DeliveryDriverProfile.user_id == user.id).first()
    cats = (
        db.query(DeliveryDriverCategory)
        .filter(DeliveryDriverCategory.user_id == user.id)
        .all()
    )
    vehicle = None
    if p is not None:
        v = db.query(DeliveryVehicleRow).filter(DeliveryVehicleRow.code == p.vehicle_code).first()
        if v is not None:
            vehicle = {
                "code": v.code, "name": v.name, "capacity_kg": v.capacity_kg,
                "has_body_choice": bool(v.has_body_choice),
                "base_fee": v.base_fee, "price_per_km": v.price_per_km,
            }
    return {
        "registered": p is not None,
        "vehicle_code": p.vehicle_code if p else None,
        "vehicle": vehicle,
        "plate": p.plate if p else None,
        "body_type": p.body_type if p else None,
        "price_per_km": p.price_per_km if p else None,
        "base_fee": p.base_fee if p else None,
        "is_online": bool(p.is_online) if p else False,
        "categories": [
            {"code": c.category_code, "min_quantity": c.min_quantity} for c in cats
        ],
    }


def save_profile(db: Session, user: User, data) -> dict:
    """Машина, номер, своя цена и категории с минимумом — целиком."""
    assert_not_frozen(user)
    vehicle = (
        db.query(DeliveryVehicleRow)
        .filter(DeliveryVehicleRow.code == data.vehicle_code, DeliveryVehicleRow.is_enabled.is_(True))
        .first()
    )
    if vehicle is None:
        raise HTTPException(400, "Bunday mashina ro'yxatda yo'q")
    known = {c.code for c in categories(db)}
    seen = set()
    for c in data.categories:
        if c.code not in known:
            raise HTTPException(400, f"Noma'lum toifa: {c.code}")
        if c.code in seen:
            raise HTTPException(400, f"Toifa ikki marta: {c.code}")
        seen.add(c.code)

    p = db.query(DeliveryDriverProfile).filter(DeliveryDriverProfile.user_id == user.id).first()
    if p is None:
        p = DeliveryDriverProfile(user_id=user.id, vehicle_code=vehicle.code)
        db.add(p)
    p.vehicle_code = vehicle.code
    p.plate = (data.plate or "").strip().upper() or None
    p.price_per_km = data.price_per_km
    p.base_fee = data.base_fee
    p.body_type = data.body_type if vehicle.has_body_choice else None

    db.query(DeliveryDriverCategory).filter(DeliveryDriverCategory.user_id == user.id).delete()
    for c in data.categories:
        db.add(DeliveryDriverCategory(user_id=user.id, category_code=c.code, min_quantity=c.min_quantity))
    db.commit()
    return profile_dict(db, user)


def heartbeat(db: Session, user: User, online: bool,
              latitude: Optional[float], longitude: Optional[float]) -> None:
    """Опрос водителя: онлайн и где он. Без профиля — ничего не делаем."""
    p = db.query(DeliveryDriverProfile).filter(DeliveryDriverProfile.user_id == user.id).first()
    if p is None:
        return
    p.is_online = bool(online)
    if latitude is not None and longitude is not None:
        p.latitude = latitude
        p.longitude = longitude
        p.location_at = _now()
    db.commit()


# ---------------------------------------------------------------- подбор

def _driver_fee(order: MaterialOrder, p: DeliveryDriverProfile, vehicle: Optional[DeliveryVehicleRow]) -> Decimal:
    """
    Сколько получит водитель. Своя цена водителя — только если ниже
    расчёта заказа: клиент не платит больше, чем видел.
    """
    admin_fee = _dec(order.delivery_fee)
    if p.price_per_km is None and p.base_fee is None:
        return admin_fee
    km = _dec(order.delivery_distance_km)
    base = _dec(p.base_fee) if p.base_fee is not None else _dec(vehicle.base_fee if vehicle else 0)
    per_km = (
        _dec(p.price_per_km) if p.price_per_km is not None
        else _dec(vehicle.price_per_km if vehicle and vehicle.price_per_km is not None else 0)
    )
    own = _round((base + km * per_km) * Decimal(order.trips or 1))
    return min(own, admin_fee)


def _matches(db: Session, order: MaterialOrder, product: MaterialProduct,
             p: DeliveryDriverProfile, mins: dict, radius: Decimal) -> Optional[Decimal]:
    """None — не подходит; иначе расстояние водителя до склада (или 0)."""
    if order.vehicle_code != p.vehicle_code:
        return None
    if p.user_id in (order.buyer_id, order.seller_id):
        return None
    category = TYPE_TO_CATEGORY.get(product.material_type)
    if category is not None:
        if category not in mins:
            return None
        if _dec(order.quantity) < _dec(mins[category]):
            return None
    if None in (p.latitude, p.longitude, product.latitude, product.longitude):
        return Decimal("0")
    dist = pricing_service.distance_km(
        float(p.latitude), float(p.longitude), float(product.latitude), float(product.longitude)
    )
    return dist if dist <= radius else None


def _card(db: Session, order: MaterialOrder, product: MaterialProduct,
          p: DeliveryDriverProfile, to_pickup_km: Decimal) -> dict:
    vehicle = db.query(DeliveryVehicleRow).filter(DeliveryVehicleRow.code == p.vehicle_code).first()
    fee = _driver_fee(order, p, vehicle)
    commission = pricing_service.calculate_commission(db, fee, fee)
    return {
        "id": order.id,
        "material_type": product.material_type,
        "title": product.title,
        "quantity": order.quantity,
        "unit": order.unit,
        "weight_kg": order.weight_kg,
        "trips": order.trips,
        "vehicle_code": order.vehicle_code,
        "pickup_address": product.address,
        "pickup_latitude": product.latitude,
        "pickup_longitude": product.longitude,
        "delivery_address": order.delivery_address,
        "delivery_latitude": order.delivery_latitude,
        "delivery_longitude": order.delivery_longitude,
        "distance_km": order.delivery_distance_km,
        "to_pickup_km": to_pickup_km.quantize(Decimal("0.1")),
        "delivery_payment": order.delivery_payment,
        "driver_fee": fee,
        "commission": commission,
        "you_receive": fee - commission,
        "created_at": order.created_at,
    }


def _profile(db: Session, user: User) -> DeliveryDriverProfile:
    p = db.query(DeliveryDriverProfile).filter(DeliveryDriverProfile.user_id == user.id).first()
    if p is None:
        raise HTTPException(400, "Avval yuk mashinangizni ro'yxatdan o'tkazing")
    return p


def incoming(db: Session, user: User) -> List[dict]:
    p = db.query(DeliveryDriverProfile).filter(DeliveryDriverProfile.user_id == user.id).first()
    if p is None or not p.is_online:
        return []
    mins = {
        c.category_code: c.min_quantity
        for c in db.query(DeliveryDriverCategory).filter(DeliveryDriverCategory.user_id == user.id)
    }
    radius = radius_km(db)
    rows = (
        db.query(MaterialOrder, MaterialProduct)
        .join(MaterialProduct, MaterialProduct.id == MaterialOrder.product_id)
        .filter(
            MaterialOrder.dispatch == "driver",
            MaterialOrder.status == MaterialOrder.STATUS_CONFIRMED,
            MaterialOrder.delivery_status == "searching",
            MaterialOrder.vehicle_code == p.vehicle_code,
        )
        .order_by(MaterialOrder.created_at)
        .limit(50)
        .all()
    )
    out = []
    for order, product in rows:
        dist = _matches(db, order, product, p, mins, radius)
        if dist is not None:
            out.append(_card(db, order, product, p, dist))
    return out


def _lock(db: Session, order_id: int) -> MaterialOrder:
    order = (
        db.query(MaterialOrder)
        .filter(MaterialOrder.id == order_id)
        .with_for_update()
        .first()
    )
    if order is None:
        raise HTTPException(404, "Buyurtma topilmadi")
    return order


def _balance(db: Session, user_id: int) -> Balance:
    get_or_create_balance(db, user_id)
    return db.query(Balance).filter(Balance.user_id == user_id).with_for_update().one()


def accept(db: Session, user: User, order_id: int) -> MaterialOrder:
    assert_not_frozen(user)
    p = _profile(db, user)
    order = _lock(db, order_id)
    if order.dispatch != "driver" or order.status != MaterialOrder.STATUS_CONFIRMED:
        raise HTTPException(400, "Bu buyurtmani olib bo'lmaydi")
    if order.delivery_status != "searching":
        raise HTTPException(409, "Buyurtmani boshqa haydovchi oldi")
    product = db.query(MaterialProduct).filter(MaterialProduct.id == order.product_id).first()
    mins = {
        c.category_code: c.min_quantity
        for c in db.query(DeliveryDriverCategory).filter(DeliveryDriverCategory.user_id == user.id)
    }
    # Радиус при принятии не проверяем: карточку водитель уже видел, а GPS
    # мог сдвинуться на пару сотен метров. Остальное — проверяем.
    if _matches(db, order, product, p, mins, Decimal("100000")) is None:
        raise HTTPException(403, "Bu buyurtma sizning mashinangizga mos emas")

    vehicle = db.query(DeliveryVehicleRow).filter(DeliveryVehicleRow.code == p.vehicle_code).first()
    fee = _driver_fee(order, p, vehicle)
    commission = pricing_service.calculate_commission(db, fee, fee)

    if order.delivery_payment == "cash" and commission > 0:
        # Наличные водитель берёт в руки — комиссию платформы держим на его
        # балансе сразу, иначе её не с кого будет взять.
        bal = _balance(db, user.id)
        available = _dec(bal.balance) - _dec(bal.frozen_balance)
        if available < commission:
            db.rollback()
            raise HTTPException(
                402,
                f"Balansingizda komissiya uchun {int(commission):,} so'm yetmaydi — "
                f"balansni to'ldiring".replace(",", " "),
            )
        bal.frozen_balance = _dec(bal.frozen_balance) + commission
        order.driver_frozen = commission

    order.driver_id = user.id
    order.driver_fee = fee
    order.driver_commission = commission
    order.delivery_status = "accepted"
    order.accepted_at = _now()
    db.commit()
    db.refresh(order)

    notification_service.create_localized(
        db, order.buyer_id, "material_driver_found",
        "material_driver_found.title", "material_driver_found.body",
        None, None, None, order_number=order.id,
    )
    return order


def _own(db: Session, user: User, order_id: int) -> MaterialOrder:
    order = _lock(db, order_id)
    if order.driver_id != user.id:
        raise HTTPException(403, "Bu sizning buyurtmangiz emas")
    if order.status != MaterialOrder.STATUS_CONFIRMED:
        raise HTTPException(400, "Buyurtma yopilgan")
    return order


def picked_up(db: Session, user: User, order_id: int) -> MaterialOrder:
    order = _own(db, user, order_id)
    if order.delivery_status != "accepted":
        raise HTTPException(400, "Holat: " + str(order.delivery_status))
    order.delivery_status = "picked_up"
    order.picked_up_at = _now()
    db.commit()
    db.refresh(order)
    notification_service.create_localized(
        db, order.buyer_id, "material_picked_up",
        "material_picked_up.title", "material_picked_up.body",
        None, None, None, order_number=order.id,
    )
    return order


def arrived(db: Session, user: User, order_id: int) -> MaterialOrder:
    order = _own(db, user, order_id)
    if order.delivery_status != "picked_up":
        raise HTTPException(400, "Avval tovarni olganingizni belgilang")
    order.delivery_status = "arrived"
    order.arrived_at = _now()
    db.commit()
    db.refresh(order)
    notification_service.create_localized(
        db, order.buyer_id, "material_driver_arrived",
        "material_driver_arrived.title", "material_driver_arrived.body",
        None, None, None, order_number=order.id,
    )
    return order


def release_driver(db: Session, order: MaterialOrder) -> None:
    """Снять замороженную комиссию водителя (отмена). Без commit."""
    frozen = _dec(order.driver_frozen)
    if frozen > 0 and order.driver_id:
        bal = db.query(Balance).filter(Balance.user_id == order.driver_id).with_for_update().first()
        if bal is not None:
            cur = _dec(bal.frozen_balance)
            bal.frozen_balance = cur - frozen if cur >= frozen else Decimal("0")
    order.driver_frozen = Decimal("0")


def driver_cancel(db: Session, user: User, order_id: int) -> MaterialOrder:
    """
    Водитель отказался до того, как забрал товар: заказ снова ищет
    водителя. После «Tovarni oldim» — нельзя: товар уже у него в машине.
    """
    order = _own(db, user, order_id)
    if order.delivery_status != "accepted":
        raise HTTPException(400, "Tovar olingandan keyin bekor qilib bo'lmaydi")
    release_driver(db, order)
    order.driver_id = None
    order.driver_fee = None
    order.driver_commission = Decimal("0")
    order.accepted_at = None
    order.delivery_status = "searching"
    db.commit()
    db.refresh(order)
    return order


def settle(db: Session, order: MaterialOrder, buyer_balance: Balance) -> Decimal:
    """
    Деньги за доставку при «Yetkazildi». Вызывается из
    material_service.deliver_order внутри его транзакции, без commit.
    Возвращает сумму, которую дополнительно списали с клиента (доставка
    с Go wallet) — для его транзакции.
    """
    fee = _dec(order.driver_fee)
    commission = _dec(order.driver_commission)
    if order.driver_id is None:
        return Decimal("0")
    driver_bal = _balance(db, order.driver_id)
    if order.delivery_payment == "balance":
        if fee > 0:
            buyer_balance.balance = _dec(buyer_balance.balance) - fee
            driver_bal.balance = _dec(driver_bal.balance) + (fee - commission)
            db.add(BalanceTransaction(
                user_id=order.driver_id, amount=fee - commission, type="income", status="completed",
                description=f"Yetkazib berish #{order.id}",
            ))
        return fee
    # Наличные: водитель взял деньги в руки, платформа списывает комиссию
    # с его баланса — ту, что заморозили при принятии.
    if commission > 0:
        frozen = _dec(order.driver_frozen)
        cur = _dec(driver_bal.frozen_balance)
        driver_bal.frozen_balance = cur - frozen if cur >= frozen else Decimal("0")
        driver_bal.balance = _dec(driver_bal.balance) - commission
        db.add(BalanceTransaction(
            user_id=order.driver_id, amount=commission, type="payment", status="completed",
            description=f"Yetkazib berish #{order.id} — komissiya (naqd)",
        ))
    order.driver_frozen = Decimal("0")
    return Decimal("0")


def my_deliveries(db: Session, user: User) -> List[MaterialOrder]:
    return (
        db.query(MaterialOrder)
        .filter(MaterialOrder.driver_id == user.id)
        .order_by(MaterialOrder.created_at.desc())
        .limit(100)
        .all()
    )
