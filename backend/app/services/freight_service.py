"""
«Yuk tashish» — перевозка груза клиента из А в Б «как такси» (24.11.2026).

Клиент пишет, сколько тонн, ставит точки А и Б, сервер предлагает самую
малую машину, в которую влезает груз (клиент может выбрать другую — он
знает, пройдёт ли HOWO в его двор). У Labo, Porter, Gazel, Isuzu… клиент
выбирает кузов: tentli (крытый) или tentsiz.

Цена — ТОЛЬКО сервер, по режиму машины из админки (catalog.php):
  km   — подача + расстояние А→Б × цена км;
  hour — часы × цена часа, не меньше минимума часов.
Цена фиксируется в заказе при создании — смена в админке историю не
переписывает.

Везут те же водители, что и стройматериалы («Yuk mashinam»): та же машина,
тот же кузов (если клиент его выбрал), не дальше радиуса от точки А. Кто
первый принял — везёт.

Деньги как у доставки стройматериалов: Go wallet — цена заморожена у
клиента и при завершении уходит водителю минус комиссия; наличные —
водителю в руки, комиссия замораживается на балансе водителя при
принятии (нет денег — 402) и списывается при завершении.
Завершает КЛИЕНТ (как «Yetkazildi»): иначе водитель забирал бы деньги, не
доехав.
"""
from datetime import datetime, timedelta, timezone
from decimal import ROUND_CEILING, Decimal
from typing import List, Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.account_state import assert_not_frozen
from app.models.balance import Balance, BalanceTransaction
from app.models.catalog import DeliveryDriverProfile, DeliveryVehicleRow, FreightOrder
from app.models.user import User
from app.services import delivery_service, notification_service, pricing_service
from app.core.messages import insufficient_funds
from app.services.balance_service import get_or_create_balance

ACTIVE = ("searching", "accepted", "loaded", "arrived")


def _dec(v, default="0") -> Decimal:
    if v is None or v == "":
        return Decimal(default)
    return Decimal(str(v))


def _now():
    return datetime.now(timezone.utc)


def _up(v: Decimal) -> Decimal:
    return v.quantize(Decimal("1"), rounding=ROUND_CEILING)


def _vehicles(db: Session) -> List[DeliveryVehicleRow]:
    return (
        db.query(DeliveryVehicleRow)
        .filter(DeliveryVehicleRow.is_enabled.is_(True))
        .order_by(DeliveryVehicleRow.capacity_kg, DeliveryVehicleRow.sort_order)
        .all()
    )


def price_for(v: DeliveryVehicleRow, km: Decimal, hours: Optional[int]) -> tuple:
    """(цена или None, часы). None — админ не поставил цену этой машине."""
    if v.price_mode == "hour":
        if v.price_per_hour is None:
            return None, None
        h = max(int(hours or v.min_hours or 1), int(v.min_hours or 1))
        return _up(Decimal(h) * _dec(v.price_per_hour)), h
    if v.price_per_km is None:
        return None, None
    return _up(_dec(v.base_fee) + km * _dec(v.price_per_km)), None


def _km(a_lat, a_lon, b_lat, b_lon) -> Decimal:
    return pricing_service.distance_km(a_lat, a_lon, b_lat, b_lon).quantize(Decimal("0.01"))


BODY_TYPES = ("tent", "open", "van", "isothermal", "fridge", "tank", "manipulator")


def _setting(db: Session, key: str, default: str) -> Decimal:
    from app.models.app_settings import AppSettings

    row = db.query(AppSettings).filter(AppSettings.key == key).first()
    try:
        return Decimal(str(row.value)) if row and row.value not in (None, "") else Decimal(default)
    except Exception:
        return Decimal(default)


def loader_prices(db: Session) -> tuple:
    """Грузчик (Шерзодбек 24.11): (цена часа, цена дня) из админки (catalog.php)."""
    return _setting(db, "freight_loader_fee", "0"), _setting(db, "freight_loader_day_fee", "0")


def loader_total(db: Session, needs: bool, mode: Optional[str], hours: Optional[int]) -> tuple:
    """(сумма, режим, часы). Без грузчика — (0, None, None)."""
    if not needs:
        return Decimal("0"), None, None
    hour_fee, day_fee = loader_prices(db)
    if mode == "day":
        return day_fee, "day", None
    h = max(1, min(int(hours or 1), 24))
    return hour_fee * h, "hour", h


def loader_fee(db: Session) -> Decimal:
    """Цена часа грузчика — оставлено для старых вызовов."""
    return loader_prices(db)[0]


def fit_problem(v: DeliveryVehicleRow, weight_kg: Optional[Decimal], l=None, w=None, h=None) -> Optional[str]:
    """
    Y7 «Bu mashinaga sig'maydi»: груз тяжелее или длиннее кузова. Длину и
    ширину можно развернуть, высоту — нет. None — помещается.
    """
    if weight_kg is not None and weight_kg > v.capacity_kg:
        return f"{v.name} {v.capacity_kg / 1000:g} t ko'taradi. Yukingiz {float(weight_kg):g} kg"
    if None in (l, w) or v.body_length_m is None or v.body_width_m is None:
        return None
    a, b = sorted([_dec(l), _dec(w)], reverse=True)
    bl, bw = sorted([_dec(v.body_length_m), _dec(v.body_width_m)], reverse=True)
    if a > bl or b > bw:
        return (f"{v.name} kuzovi {float(v.body_length_m):g}×{float(v.body_width_m):g} m. "
                f"Yukingiz {float(a):g}×{float(b):g} m — xavfsiz tashib bo'lmaydi")
    if h is not None and v.body_height_m is not None and _dec(h) > _dec(v.body_height_m):
        return f"{v.name} kuzovi balandligi {float(v.body_height_m):g} m. Yukingiz {float(_dec(h)):g} m"
    return None


def _free_drivers(db: Session, v: DeliveryVehicleRow, body: Optional[str],
                  lat: float, lon: float, radius: Decimal) -> tuple:
    """Y2 «14 ta bo'sh · 1.8 km»: сколько водителей онлайн и ближайший."""
    q = db.query(DeliveryDriverProfile).filter(
        DeliveryDriverProfile.vehicle_code == v.code, DeliveryDriverProfile.is_online.is_(True))
    if body:
        q = q.filter(DeliveryDriverProfile.body_type == body)
    count, nearest = 0, None
    for p in q.all():
        if p.latitude is None or p.longitude is None:
            continue
        d = pricing_service.distance_km(float(p.latitude), float(p.longitude), lat, lon)
        if d <= radius:
            count += 1
            nearest = d if nearest is None else min(nearest, d)
    return count, (nearest.quantize(Decimal("0.1")) if nearest is not None else None)


def quote(db: Session, from_lat: float, from_lon: float, to_lat: float, to_lon: float,
          tonnes: Optional[Decimal], hours: Optional[int], body: Optional[str] = None,
          weight_kg: Optional[Decimal] = None, length=None, width=None, height=None,
          needs_loader: bool = False, loader_mode: Optional[str] = None,
          loader_hours: Optional[int] = None) -> dict:
    """Все машины с ценой на этот маршрут, свободные водители и «влезет ли»."""
    km = _km(from_lat, from_lon, to_lat, to_lon)
    if weight_kg is None and tonnes is not None:
        weight_kg = tonnes * 1000
    loader, _, _ = loader_total(db, needs_loader, loader_mode, loader_hours)
    hour_fee, day_fee = loader_prices(db)
    radius = delivery_service.radius_km(db)
    items = []
    for v in _vehicles(db):
        price, h = price_for(v, km, hours)
        min_price, _ = price_for(v, Decimal("0"), None)
        free, nearest = _free_drivers(db, v, body if body in v.body_list else None, from_lat, from_lon, radius)
        problem = fit_problem(v, weight_kg, length, width, height)
        items.append({
            "code": v.code,
            "name": v.name,
            "brand": v.brand or v.name,
            "size_class": v.size_class,
            "capacity_kg": v.capacity_kg,
            "volume_m3": v.volume_m3,
            "body_length_m": v.body_length_m,
            "body_width_m": v.body_width_m,
            "body_height_m": v.body_height_m,
            "body_types": v.body_list,
            "has_body_choice": len(v.body_list) > 1,
            "price_mode": v.price_mode,
            "price_per_km": v.price_per_km,
            "base_fee": v.base_fee,
            "hours": h,
            "min_hours": v.min_hours,
            "min_price": min_price,
            "price": (price + loader) if price is not None else None,
            "free_drivers": free,
            "nearest_km": nearest,
            "fits": problem is None,
            "fit_problem": problem,
        })
    suggested = None
    for it in items:
        if it["price"] is not None and it["fits"] and (weight_kg is None or it["capacity_kg"] >= weight_kg):
            if weight_kg is not None or length is not None:
                suggested = it["code"]
                break
    return {"distance_km": km, "loader_fee": loader, "loader_hour_fee": hour_fee,
            "loader_day_fee": day_fee, "vehicles": items, "suggested": suggested}


def create(db: Session, client: User, data) -> FreightOrder:
    assert_not_frozen(client)
    v = (
        db.query(DeliveryVehicleRow)
        .filter(DeliveryVehicleRow.code == data.vehicle_code, DeliveryVehicleRow.is_enabled.is_(True))
        .first()
    )
    if v is None:
        raise HTTPException(400, "Bunday mashina ro'yxatda yo'q")
    body = data.body_type
    bodies = v.body_list
    if len(bodies) > 1:
        if body not in bodies:
            raise HTTPException(400, "Kuzov turini tanlang")
    else:
        body = bodies[0] if bodies else None
    weight = _dec(data.cargo_tonnes) * 1000 if data.cargo_tonnes is not None else None
    problem = fit_problem(v, weight, data.cargo_length_m, data.cargo_width_m, data.cargo_height_m)
    if problem:
        raise HTTPException(400, problem + " — kattaroq mashina tanlang")
    km = _km(data.from_latitude, data.from_longitude, data.to_latitude, data.to_longitude)
    price, hours = price_for(v, km, data.hours)
    if price is None or price <= 0:
        raise HTTPException(400, "Bu mashina uchun narx hali qo'yilmagan")
    loader, loader_mode, loader_hours = loader_total(
        db, bool(data.needs_loader), data.loader_mode, data.loader_hours)
    price = price + loader
    scheduled = data.scheduled_at
    if scheduled is not None:
        if scheduled.tzinfo is None:
            scheduled = scheduled.replace(tzinfo=timezone.utc)
        if scheduled < _now() - timedelta(minutes=5):
            raise HTTPException(400, "Vaqt o'tib ketgan — boshqa vaqt tanlang")

    payment = data.payment_method or "balance"
    frozen = Decimal("0")
    if payment == "balance":
        get_or_create_balance(db, client.id)
        bal = db.query(Balance).filter(Balance.user_id == client.id).with_for_update().one()
        available = _dec(bal.balance) - _dec(bal.frozen_balance)
        if available < price:
            raise HTTPException(400, insufficient_funds(db, client.id, available, price))
        bal.frozen_balance = _dec(bal.frozen_balance) + price
        frozen = price

    order = FreightOrder(
        client_id=client.id, vehicle_code=v.code, body_type=body,
        cargo_tonnes=data.cargo_tonnes, cargo_note=(data.cargo_note or None),
        cargo_type=data.cargo_type, cargo_length_m=data.cargo_length_m, cargo_width_m=data.cargo_width_m,
        cargo_height_m=data.cargo_height_m, cargo_volume_m3=data.cargo_volume_m3,
        needs_loader=bool(data.needs_loader), loader_fee=loader, loader_mode=loader_mode,
        loader_hours=loader_hours, scheduled_at=scheduled,
        from_address=data.from_address, from_latitude=data.from_latitude, from_longitude=data.from_longitude,
        to_address=data.to_address, to_latitude=data.to_latitude, to_longitude=data.to_longitude,
        distance_km=km, price_mode=v.price_mode, hours=hours, price=price,
        payment_method=payment, frozen_amount=frozen, status="searching",
    )
    db.add(order)
    db.commit()
    db.refresh(order)
    return order


# ---------------------------------------------------------------- водитель

def _matches(order: FreightOrder, p: DeliveryDriverProfile, radius: Decimal) -> Optional[Decimal]:
    if order.vehicle_code != p.vehicle_code or order.client_id == p.user_id:
        return None
    if order.body_type and p.body_type != order.body_type:
        return None
    if p.latitude is None or p.longitude is None:
        return Decimal("0")
    dist = pricing_service.distance_km(float(p.latitude), float(p.longitude),
                                       float(order.from_latitude), float(order.from_longitude))
    return dist if dist <= radius else None


def _card(db: Session, order: FreightOrder, to_pickup: Decimal) -> dict:
    fee = _dec(order.price)
    commission = pricing_service.calculate_commission(db, fee, fee)
    return {
        "id": order.id, "kind": "freight", "vehicle_code": order.vehicle_code, "body_type": order.body_type,
        "cargo_tonnes": order.cargo_tonnes, "cargo_note": order.cargo_note,
        "cargo_type": order.cargo_type, "cargo_length_m": order.cargo_length_m,
        "cargo_width_m": order.cargo_width_m, "cargo_height_m": order.cargo_height_m,
        "needs_loader": order.needs_loader, "loader_mode": order.loader_mode,
        "loader_hours": order.loader_hours, "scheduled_at": order.scheduled_at,
        "from_address": order.from_address, "to_address": order.to_address,
        "distance_km": order.distance_km, "to_pickup_km": to_pickup.quantize(Decimal("0.1")),
        "price_mode": order.price_mode, "hours": order.hours,
        "payment_method": order.payment_method,
        "driver_fee": fee, "commission": commission, "you_receive": fee - commission,
        "created_at": order.created_at,
    }


def incoming(db: Session, driver: User) -> List[dict]:
    p = db.query(DeliveryDriverProfile).filter(DeliveryDriverProfile.user_id == driver.id).first()
    if p is None or not p.is_online:
        return []
    radius = delivery_service.radius_km(db)
    rows = (
        db.query(FreightOrder)
        .filter(FreightOrder.status == "searching", FreightOrder.vehicle_code == p.vehicle_code)
        .order_by(FreightOrder.created_at)
        .limit(50)
        .all()
    )
    out = []
    for o in rows:
        d = _matches(o, p, radius)
        if d is not None:
            out.append(_card(db, o, d))
    return out


def _lock(db: Session, order_id: int) -> FreightOrder:
    o = db.query(FreightOrder).filter(FreightOrder.id == order_id).with_for_update().first()
    if o is None:
        raise HTTPException(404, "Buyurtma topilmadi")
    return o


def _balance(db: Session, user_id: int) -> Balance:
    get_or_create_balance(db, user_id)
    return db.query(Balance).filter(Balance.user_id == user_id).with_for_update().one()


def accept(db: Session, driver: User, order_id: int) -> FreightOrder:
    assert_not_frozen(driver)
    p = db.query(DeliveryDriverProfile).filter(DeliveryDriverProfile.user_id == driver.id).first()
    if p is None:
        raise HTTPException(400, "Avval yuk mashinangizni ro'yxatdan o'tkazing")
    o = _lock(db, order_id)
    if o.status != "searching":
        raise HTTPException(409, "Buyurtmani boshqa haydovchi oldi")
    if _matches(o, p, Decimal("100000")) is None:
        raise HTTPException(403, "Bu buyurtma sizning mashinangizga mos emas")
    fee = _dec(o.price)
    commission = pricing_service.calculate_commission(db, fee, fee)
    if o.payment_method == "cash" and commission > 0:
        bal = _balance(db, driver.id)
        if _dec(bal.balance) - _dec(bal.frozen_balance) < commission:
            db.rollback()
            raise HTTPException(
                402, f"Balansingizda komissiya uchun {int(commission):,} so'm yetmaydi — balansni to'ldiring"
                .replace(",", " "))
        bal.frozen_balance = _dec(bal.frozen_balance) + commission
        o.driver_frozen = commission
    o.driver_id = driver.id
    o.driver_fee = fee
    o.driver_commission = commission
    o.status = "accepted"
    o.accepted_at = _now()
    db.commit()
    db.refresh(o)
    notification_service.create_localized(
        db, o.client_id, "freight_driver_found", "freight_driver_found.title", "freight_driver_found.body",
        None, None, None, order_number=o.id)
    return o


def _own(db: Session, driver: User, order_id: int) -> FreightOrder:
    o = _lock(db, order_id)
    if o.driver_id != driver.id:
        raise HTTPException(403, "Bu sizning buyurtmangiz emas")
    return o


def loaded(db: Session, driver: User, order_id: int) -> FreightOrder:
    o = _own(db, driver, order_id)
    if o.status != "accepted":
        raise HTTPException(400, "Holat: " + o.status)
    o.status = "loaded"
    o.loaded_at = _now()
    db.commit()
    db.refresh(o)
    notification_service.create_localized(
        db, o.client_id, "freight_loaded", "freight_loaded.title", "freight_loaded.body",
        None, None, None, order_number=o.id)
    return o


def arrived(db: Session, driver: User, order_id: int) -> FreightOrder:
    o = _own(db, driver, order_id)
    if o.status != "loaded":
        raise HTTPException(400, "Avval yuk ortilganini belgilang")
    o.status = "arrived"
    o.arrived_at = _now()
    db.commit()
    db.refresh(o)
    notification_service.create_localized(
        db, o.client_id, "freight_arrived", "freight_arrived.title", "freight_arrived.body",
        None, None, None, order_number=o.id)
    return o


def _release_driver(db: Session, o: FreightOrder) -> None:
    frozen = _dec(o.driver_frozen)
    if frozen > 0 and o.driver_id:
        bal = db.query(Balance).filter(Balance.user_id == o.driver_id).with_for_update().first()
        if bal is not None:
            cur = _dec(bal.frozen_balance)
            bal.frozen_balance = cur - frozen if cur >= frozen else Decimal("0")
    o.driver_frozen = Decimal("0")


def driver_cancel(db: Session, driver: User, order_id: int) -> FreightOrder:
    """До погрузки — заказ снова ищет водителя."""
    o = _own(db, driver, order_id)
    if o.status != "accepted":
        raise HTTPException(400, "Yuk ortilgandan keyin bekor qilib bo'lmaydi")
    _release_driver(db, o)
    o.driver_id = None
    o.driver_fee = None
    o.driver_commission = Decimal("0")
    o.accepted_at = None
    o.status = "searching"
    db.commit()
    db.refresh(o)
    return o


def _client_order(db: Session, client: User, order_id: int) -> FreightOrder:
    o = _lock(db, order_id)
    if o.client_id != client.id and client.role != "admin":
        raise HTTPException(403, "Bu sizning buyurtmangiz emas")
    return o


def client_cancel(db: Session, client: User, order_id: int) -> FreightOrder:
    """Клиент отменяет, пока груз не погружен. Деньги — только разморозка."""
    o = _client_order(db, client, order_id)
    if o.status not in ("searching", "accepted"):
        raise HTTPException(400, "Yuk ortilgandan keyin bekor qilib bo'lmaydi")
    frozen = _dec(o.frozen_amount)
    if frozen > 0:
        bal = db.query(Balance).filter(Balance.user_id == o.client_id).with_for_update().first()
        if bal is not None:
            cur = _dec(bal.frozen_balance)
            bal.frozen_balance = cur - frozen if cur >= frozen else Decimal("0")
    o.frozen_amount = Decimal("0")
    driver_id = o.driver_id
    _release_driver(db, o)
    o.status = "cancelled"
    o.cancelled_by = "client"
    db.commit()
    db.refresh(o)
    if driver_id:
        notification_service.create_localized(
            db, driver_id, "freight_cancelled", "freight_cancelled.title", "freight_cancelled.body",
            None, None, None, order_number=o.id)
    return o


def finish(db: Session, client: User, order_id: int) -> FreightOrder:
    """Клиент подтвердил: груз доставлен. Деньги двигаются здесь."""
    o = _client_order(db, client, order_id)
    if o.status not in ("loaded", "arrived"):
        raise HTTPException(400, "Yuk hali ortilmagan")
    fee = _dec(o.driver_fee)
    commission = _dec(o.driver_commission)
    driver_bal = _balance(db, o.driver_id)
    if o.payment_method == "balance":
        bal = _balance(db, o.client_id)
        frozen = _dec(o.frozen_amount)
        cur = _dec(bal.frozen_balance)
        bal.frozen_balance = cur - frozen if cur >= frozen else Decimal("0")
        bal.balance = _dec(bal.balance) - fee
        driver_bal.balance = _dec(driver_bal.balance) + (fee - commission)
        db.add(BalanceTransaction(user_id=o.client_id, amount=fee, type="payment", status="completed",
                                  description=f"Yuk tashish #{o.id}"))
        db.add(BalanceTransaction(user_id=o.driver_id, amount=fee - commission, type="income",
                                  status="completed", description=f"Yuk tashish #{o.id}"))
    elif commission > 0:
        frozen = _dec(o.driver_frozen)
        cur = _dec(driver_bal.frozen_balance)
        driver_bal.frozen_balance = cur - frozen if cur >= frozen else Decimal("0")
        driver_bal.balance = _dec(driver_bal.balance) - commission
        db.add(BalanceTransaction(user_id=o.driver_id, amount=commission, type="payment",
                                  status="completed", description=f"Yuk tashish #{o.id} — komissiya (naqd)"))
    o.frozen_amount = Decimal("0")
    o.driver_frozen = Decimal("0")
    o.status = "done"
    o.finished_at = _now()
    db.commit()
    db.refresh(o)
    return o


def read(db: Session, o: FreightOrder, viewer: User) -> dict:
    """Контакты второй стороны — только когда водитель принял заказ."""
    v = db.query(DeliveryVehicleRow).filter(DeliveryVehicleRow.code == o.vehicle_code).first()
    out = {c.name: getattr(o, c.name) for c in FreightOrder.__table__.columns}
    out["vehicle_name"] = v.name if v else o.vehicle_code
    out["capacity_kg"] = v.capacity_kg if v else None
    if o.driver_id:
        d = db.query(User).filter(User.id == o.driver_id).first()
        p = db.query(DeliveryDriverProfile).filter(DeliveryDriverProfile.user_id == o.driver_id).first()
        c = db.query(User).filter(User.id == o.client_id).first()
        out["driver_name"] = d.full_name if d else None
        out["driver_phone"] = d.phone if d else None
        out["driver_plate"] = p.plate if p else None
        out["client_name"] = c.full_name if c else None
        out["client_phone"] = c.phone if c else None
    return out


def client_orders(db: Session, client: User) -> List[FreightOrder]:
    return (db.query(FreightOrder).filter(FreightOrder.client_id == client.id)
            .order_by(FreightOrder.created_at.desc()).limit(100).all())


def driver_orders(db: Session, driver: User) -> List[FreightOrder]:
    return (db.query(FreightOrder).filter(FreightOrder.driver_id == driver.id)
            .order_by(FreightOrder.created_at.desc()).limit(100).all())
