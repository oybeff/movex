"""
Ход тарифного заказа после того, как владелец его взял (второй макет).

    confirmed ─ «Ketdik» (departed_at) ─ «Boshlash» (started_at)
              ─ «Yakunlash» (finished_at) ─ клиент подтверждает → completed

Деньги здесь двигает только «продлить время» (extend). Завершение и отмена
по-прежнему идут через order_service.update_order — там вся логика эскроу
и наличных, второй копии быть не должно.
"""
from app.core.messages import insufficient_funds
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Optional

from fastapi import HTTPException
from sqlalchemy import func, text
from sqlalchemy.orm import Session

from app.models.balance import Balance
from app.models.equipment import Equipment
from app.models.order import Order
from app.models.order_problem import PROBLEM_REASONS, OrderProblem
from app.models.review import Review
from app.models.user import User
from app.core.media import is_own_media
from app.services import pricing_service

#: Средняя скорость техники в городе для «Taxminan N daqiqada yetib keladi».
#: Это оценка, а не обещание: живого местоположения у техники нет.
AVG_SPEED_KMH = Decimal("25")

#: За один раз можно продлить не больше чем на столько часов.
MAX_EXTEND_HOURS = 12

#: Через столько после «Yakunlash» заказ подтверждается сам (B4).
AUTO_CONFIRM_AFTER = timedelta(minutes=10)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _lock_order(db: Session, order_id: int) -> Order:
    order = db.query(Order).filter(Order.id == order_id).with_for_update().first()
    if order is None:
        raise HTTPException(404, "Buyurtma topilmadi")
    return order


def _equipment(db: Session, order: Order) -> Equipment:
    eq = db.query(Equipment).filter(Equipment.id == order.equipment_id).first()
    if eq is None:
        raise HTTPException(404, "Texnika topilmadi")
    return eq


def _owner_only(db: Session, order: Order, user: User) -> Equipment:
    eq = _equipment(db, order)
    if eq.owner_id != user.id:
        raise HTTPException(403, "Faqat texnika egasi")
    if order.status != "confirmed":
        raise HTTPException(409, "Buyurtma faol emas")
    return eq


def _notify(db: Session, order: Order, to_user_id: int, type_: str, **params) -> None:
    """
    Xabarnoma ikkinchi tomonga (M5). Xato bo'lsa buyurtmani to'xtatmaydi:
    notification_service o'zi jurnalga yozadi va davom etadi.
    """
    from app.core.equipment_types import type_name
    from app.services import notification_service

    eq = db.query(Equipment).filter(Equipment.id == order.equipment_id).first()
    owner = db.query(User).filter(User.id == eq.owner_id).first() if eq else None
    lang = notification_service.user_language(db, to_user_id)
    what = " ".join(p for p in (type_name(eq.type, lang) if eq else None, eq.model if eq else None) if p)
    notification_service.create_localized(
        db, to_user_id, type_, f"{type_}.title", f"{type_}.body",
        order.id, eq.type if eq else None, eq.model if eq else None,
        language=lang, what=what, owner=(owner.full_name if owner else ""), **params,
    )


def depart(db: Session, order_id: int, user: User) -> Order:
    """«Ketdik»: владелец выехал. Повторное нажатие ничего не ломает."""
    order = _lock_order(db, order_id)
    _owner_only(db, order, user)
    first = order.departed_at is None
    if first:
        order.departed_at = _now()
    db.commit()
    db.refresh(order)
    if first:
        _notify(db, order, order.user_id, "order_departed")
    return order


def arrive(db: Session, order_id: int, user: User) -> Order:
    """«Yetib keldim» (макет водителя D1 → D2): техника на месте, ждём клиента."""
    order = _lock_order(db, order_id)
    _owner_only(db, order, user)
    now = _now()
    if order.departed_at is None:
        order.departed_at = now
    first = order.arrived_at is None
    if first:
        order.arrived_at = now
    db.commit()
    db.refresh(order)
    if first:
        _notify(db, order, order.user_id, "order_arrived")
    return order


def start(db: Session, order_id: int, user: User) -> Order:
    """«Boshlash»: работа началась — с этого момента идёт таймер клиента."""
    order = _lock_order(db, order_id)
    _owner_only(db, order, user)
    now = _now()
    first = order.started_at is None
    if order.departed_at is None:
        order.departed_at = now
    if order.arrived_at is None:
        order.arrived_at = now
    if first:
        order.started_at = now
    db.commit()
    db.refresh(order)
    if first:
        _notify(db, order, order.user_id, "order_started")
    return order


def finish(db: Session, order_id: int, user: User) -> Order:
    """
    «Yakunlash»: владелец закончил. Деньги ещё НЕ двигаются — заказ
    завершает клиент подтверждением (макет: «texnika egasi yakunlaydi —
    siz tasdiqlaysiz»).
    """
    order = _lock_order(db, order_id)
    _owner_only(db, order, user)
    if order.started_at is None:
        raise HTTPException(409, "Ish hali boshlanmagan")
    first = order.finished_at is None
    if first:
        order.finished_at = _now()
    db.commit()
    db.refresh(order)
    if first:
        _notify(db, order, order.user_id, "order_finished")
    return order


def request_extend(db: Session, order_id: int, user: User, hours: int) -> Order:
    """
    Клиент: «So'rov yuborish» (B3). Деньги НЕ двигаются — только запрос;
    продление случится, когда владелец согласится (approve_extend).
    Повторный запрос заменяет прежний.
    """
    if hours < 1 or hours > MAX_EXTEND_HOURS:
        raise HTTPException(400, f"1 dan {MAX_EXTEND_HOURS} soatgacha uzaytirish mumkin")
    order = _lock_order(db, order_id)
    if order.user_id != user.id:
        raise HTTPException(403, "Faqat buyurtmachi uzaytiradi")
    if order.status != "confirmed" or order.finished_at is not None:
        raise HTTPException(409, "Buyurtmani uzaytirib bo'lmaydi")
    if not order.tariff or not order.hours:
        raise HTTPException(400, "Faqat tarifli buyurtma uzaytiriladi")
    if order.payment_method == "card":
        # Доплата картой — второй холд; пока не сделано
        raise HTTPException(400, "Karta bilan to'langan buyurtmani hozircha uzaytirib bo'lmaydi")
    order.extend_requested_hours = hours
    db.commit()
    db.refresh(order)
    owner_id = _equipment(db, order).owner_id
    _notify(db, order, owner_id, "order_extend_requested", hours=hours)
    return order


def approve_extend(db: Session, order_id: int, user: User) -> Order:
    """Владелец согласился — вот теперь часы и деньги добавляются."""
    order = _lock_order(db, order_id)
    _owner_only(db, order, user)
    hours = order.extend_requested_hours
    if not hours:
        raise HTTPException(409, "Uzaytirish so'rovi yo'q")
    client = db.query(User).filter(User.id == order.user_id).first()
    order.extend_requested_hours = None
    order = _apply_extend(db, order, client, hours)
    _notify(db, order, order.user_id, "order_extend_approved", hours=hours)
    return order


def decline_extend(db: Session, order_id: int, user: User) -> Order:
    order = _lock_order(db, order_id)
    _owner_only(db, order, user)
    had_request = order.extend_requested_hours is not None
    order.extend_requested_hours = None
    db.commit()
    db.refresh(order)
    if had_request:
        _notify(db, order, order.user_id, "order_extend_declined")
    return order


def report_delay(db: Session, order_id: int, user: User, minutes: int,
                 reason: Optional[str]) -> Order:
    """Владелец: «опаздываю на N минут» (B2 у клиента). До начала работы."""
    order = _lock_order(db, order_id)
    _owner_only(db, order, user)
    if order.started_at is not None:
        raise HTTPException(409, "Ish allaqachon boshlangan")
    order.delay_minutes = minutes
    order.delay_reason = (reason or "").strip()[:300] or None
    db.commit()
    db.refresh(order)
    _notify(db, order, order.user_id, "order_delayed", minutes=minutes)
    return order


def report_problem(db: Session, order_id: int, user: User, reason: str,
                   comment: Optional[str], photos: list) -> OrderProblem:
    """
    Клиент: «Muammo haqida xabar» (B5). Фото — только свои загрузки из
    /static/problems/, не больше трёх. Жалоба останавливает
    автоподтверждение: деньги не уйдут, пока заказ не разберут.
    """
    if reason not in PROBLEM_REASONS:
        raise HTTPException(400, "Sabab noto'g'ri")
    photos = list(photos or [])
    if len(photos) > 3:
        raise HTTPException(400, "3 tagacha rasm")
    for url in photos:
        if not (is_own_media(url) and url.startswith("/static/problems/")):
            raise HTTPException(400, "Rasm manzili noto'g'ri")
    order = _lock_order(db, order_id)
    if order.user_id != user.id:
        raise HTTPException(403, "Faqat buyurtmachi")
    if order.status != "confirmed":
        raise HTTPException(409, "Buyurtma faol emas")
    problem = OrderProblem(
        order_id=order.id, user_id=user.id, reason=reason,
        comment=(comment or "").strip()[:1000] or None, photos=photos or None,
    )
    db.add(problem)
    if order.problem_reported_at is None:
        order.problem_reported_at = _now()
    db.commit()
    db.refresh(problem)
    return problem


def auto_confirm(db: Session, order: Order) -> Order:
    """
    «10 daqiqa ichida javob bermasangiz, ish avtomatik tasdiqlanadi» (B4).
    Проверяется лениво — при чтении заказа. Жалоба (problem_reported_at)
    автоподтверждение отключает.
    """
    if (
        order.status == "confirmed"
        and order.finished_at is not None
        and order.problem_reported_at is None
        and _now() - order.finished_at >= AUTO_CONFIRM_AFTER
    ):
        from app.schemas.order import OrderUpdate
        from app.services import order_service

        try:
            order = order_service.update_order(
                db, order.id, OrderUpdate(status="completed"), order.user_id
            )
        except HTTPException:
            db.rollback()
    return order


def no_show(db: Session, order_id: int, user: User) -> Order:
    """
    E7 «Mijoz kelmadi»: техника на месте, клиент не вышел. Владелец
    отменяет заказ; если ждал не меньше NO_SHOW_WAIT_MINUTES — клиент
    платит компенсацию (compensation_service, по умолчанию выключена).
    Раньше — обычная отмена владельцем, без денег.
    """
    from app.schemas.order import OrderUpdate
    from app.services import compensation_service, order_service

    order = _lock_order(db, order_id)
    eq = _owner_only(db, order, user)
    if order.arrived_at is None:
        raise HTTPException(409, "Avval «Yetib keldim» bosing")
    if order.started_at is not None:
        raise HTTPException(409, "Ish boshlangan")
    waited = _now() - order.arrived_at
    if waited >= timedelta(minutes=compensation_service.NO_SHOW_WAIT_MINUTES):
        compensation_service.compensate(db, order, eq.owner_id)
    order.cancel_reason = "client_no_show"
    # update_order ставит cancelled_by='owner', возвращает остаток заморозки
    # и коммитит всё одной транзакцией вместе с компенсацией.
    return order_service.update_order(db, order.id, OrderUpdate(status="cancelled"), user.id)


def rate_client(db: Session, order_id: int, user: User, rating: int, tags: list) -> dict:
    """D6 «Mijozni baholang»: одна оценка на заказ, повтор переписывает."""
    from app.models.client_rating import ClientRating

    order = db.query(Order).filter(Order.id == order_id).first()
    if order is None:
        raise HTTPException(404, "Buyurtma topilmadi")
    eq = _equipment(db, order)
    if eq.owner_id != user.id:
        raise HTTPException(403, "Faqat texnika egasi")
    if order.finished_at is None and order.status != "completed":
        raise HTTPException(409, "Ish hali yakunlanmagan")
    if not 1 <= int(rating) <= 5:
        raise HTTPException(400, "Baho 1 dan 5 gacha")
    clean = list(dict.fromkeys(x for x in (tags or []) if x in CLIENT_RATING_TAGS))
    row = db.query(ClientRating).filter(ClientRating.order_id == order.id).first()
    if row is None:
        row = ClientRating(order_id=order.id, owner_id=user.id, client_id=order.user_id)
        db.add(row)
    row.rating = int(rating)
    row.tags = ",".join(clean) or None
    db.commit()
    return {"order_id": order.id, "rating": row.rating, "tags": clean}


def client_rating_summary(db: Session, client_id: int) -> dict:
    """Средняя оценка клиента водителями — для карточки входящего заказа."""
    from sqlalchemy import func as sa_func

    from app.models.client_rating import ClientRating

    avg, cnt = (
        db.query(sa_func.avg(ClientRating.rating), sa_func.count(ClientRating.id))
        .filter(ClientRating.client_id == client_id)
        .one()
    )
    return {"rating": round(float(avg), 1) if avg is not None else None, "count": int(cnt or 0)}


#: Плашки макета D6. Код — в базе, текст — в переводах приложения.
CLIENT_RATING_TAGS = ("on_time_pay", "polite", "exact_address", "kept_waiting")


def extend(db: Session, order_id: int, user: User, hours: int) -> Order:
    """Старый прямой путь (без согласия владельца) — через запрос."""
    return request_extend(db, order_id, user, hours)


def _apply_extend(db: Session, order: Order, user: User, hours: int) -> Order:
    """
    Продление по согласию владельца: часы по цене часа заказа.

    Цена часа = total_amount / hours заказа — ровно та, по которой он
    заказывал (тариф + навесное). Новый тариф админа сюда не попадает.

    С баланса: доплата замораживается сразу, не хватает — 400.
    Наличными: клиент доплатит владельцу в руки; если комиссия выросла
    (процентный режим), разница замораживается у владельца.
    """
    total = Decimal(str(order.total_amount))
    per_hour = total / Decimal(order.hours)
    extra = (per_hour * hours).quantize(Decimal("0.01"))
    new_total = total + extra
    new_commission = pricing_service.calculate_commission(db, new_total, new_total)
    old_commission = Decimal(str(order.commission))

    if order.payment_method == "cash":
        delta = new_commission - old_commission
        if delta > 0:
            eq = _equipment(db, order)
            ob = (
                db.query(Balance).filter(Balance.user_id == eq.owner_id).with_for_update().first()
            )
            available = (
                Decimal(str(ob.balance)) - Decimal(str(ob.frozen_balance)) if ob else Decimal("0")
            )
            if available < delta:
                db.rollback()
                raise HTTPException(
                    409, "Texnika egasining hisobida komissiya uchun mablag' yetmaydi"
                )
            ob.frozen_balance = Decimal(str(ob.frozen_balance)) + delta
            order.owner_frozen = Decimal(str(order.owner_frozen or 0)) + delta
    else:
        cb = db.query(Balance).filter(Balance.user_id == user.id).with_for_update().first()
        available = (
            Decimal(str(cb.balance)) - Decimal(str(cb.frozen_balance)) if cb else Decimal("0")
        )
        if available < extra:
            db.rollback()
            raise HTTPException(
                400,
                insufficient_funds(db, user.id, available, extra),
            )
        cb.frozen_balance = Decimal(str(cb.frozen_balance)) + extra
        order.frozen_amount = Decimal(str(order.frozen_amount)) + extra

    order.total_amount = new_total
    order.commission = new_commission
    order.hours = order.hours + hours
    db.commit()
    db.refresh(order)
    return order


def executor(db: Session, order: Order) -> dict:
    """
    Карточка исполнителя для клиента (экран 8): имя, рейтинг, число
    заказов, машина, госномер, примерное время подачи.

    Рейтинг — среднее отзывов на ВСЮ технику владельца, заказы — его
    завершённые заказы. Время подачи — расстояние от точки машины до
    адреса при средней скорости; живого местоположения нет.
    """
    eq = _equipment(db, order)
    owner = db.query(User).filter(User.id == eq.owner_id).first()
    eq_ids = [r[0] for r in db.query(Equipment.id).filter(Equipment.owner_id == eq.owner_id).all()]
    rating_row = (
        db.query(func.avg(Review.rating), func.count(Review.id))
        .filter(Review.equipment_id.in_(eq_ids))
        .first()
    )
    done = (
        db.query(func.count(Order.id))
        .filter(Order.equipment_id.in_(eq_ids), Order.status == "completed")
        .scalar()
    )
    # Куда едет техника. Макет (кадр 8): «Manzil» — точка «Qayerdan», где
    # техника нужна в начале; у тарифного заказа она в заявке (origin_*).
    # Нет её (старые заказы) — адрес заказа, как раньше.
    from app.models.equipment_request import EquipmentRequest

    req = db.query(EquipmentRequest).filter(EquipmentRequest.order_id == order.id).first()
    dest_lat, dest_lon = order.delivery_latitude, order.delivery_longitude
    if req is not None and req.origin_latitude and req.origin_longitude:
        dest_lat, dest_lon = req.origin_latitude, req.origin_longitude
    eta: Optional[int] = None
    try:
        km = pricing_service.distance_km(
            float(eq.latitude), float(eq.longitude),
            float(dest_lat), float(dest_lon),
        )
        eta = max(5, int((Decimal(km) / AVG_SPEED_KMH * 60).to_integral_value()))
    except (TypeError, ValueError):
        pass
    name = (owner.full_name if owner else "") or ""
    initials = "".join(p[0] for p in name.split()[:2]).upper() or None
    return dict(
        owner_id=eq.owner_id,
        owner_name=name or None,
        owner_initials=initials,
        owner_phone=owner.phone if owner else None,
        rating=round(float(rating_row[0]), 1) if rating_row and rating_row[0] is not None else None,
        reviews=int(rating_row[1]) if rating_row else 0,
        orders_done=int(done or 0),
        equipment_type=eq.type,
        equipment_model=eq.model,
        plate_number=eq.plate_number,
        eta_minutes=eta,
        # Точка, выбранная владельцем при добавлении техники (живого
        # слежения нет): клиент рисует по ней машину и линию до адреса.
        equipment_latitude=_float_or_none(eq.latitude),
        equipment_longitude=_float_or_none(eq.longitude),
        destination_latitude=_float_or_none(dest_lat),
        destination_longitude=_float_or_none(dest_lon),
    )


def _float_or_none(v) -> Optional[float]:
    try:
        return float(v) if v is not None else None
    except (TypeError, ValueError):
        return None


# ------------------------------------------------- M1–M3 · Buyurtmalarim

def _iso(v):
    return v.isoformat() if v is not None else None


def _num(v):
    return float(v) if v is not None else None


def _stage(order: Order) -> str:
    """
    Этап для карточки: searching (заявка без исполнителя), scheduled
    («Rejada» — взят, но не выехал), on_the_way («Yo'lda»), working,
    awaiting_confirm (B4), completed, cancelled.
    """
    if order.status == "completed":
        return "completed"
    if order.status in ("cancelled", "rejected"):
        return "cancelled"
    if order.finished_at is not None:
        return "awaiting_confirm"
    if order.started_at is not None:
        return "working"
    if order.departed_at is not None:
        return "on_the_way"
    return "scheduled"


def client_cards(db: Session, user: User, lang: str = "uz") -> list:
    """
    Список «Buyurtmalarim» одним запросом: заказы клиента и его тарифные
    заявки, которые ещё ищут исполнителя. В карточке всё, что рисует
    макет M1–M3, — чтобы приложению не ходить за каждой строкой отдельно.
    """
    from app.models.equipment_request import EquipmentRequest
    from app.models.tariff import EquipmentAttachment

    from app.services.request_service import expire_stale

    expire_stale(db)

    orders = (
        db.query(Order).filter(Order.user_id == user.id)
        .order_by(Order.created_at.desc()).limit(200).all()
    )
    for o in orders:
        auto_confirm(db, o)
    reqs = {
        r.order_id: r
        for r in db.query(EquipmentRequest)
        .filter(EquipmentRequest.client_id == user.id, EquipmentRequest.order_id.isnot(None))
        .all()
    }
    att_ids = {r.attachment_id for r in reqs.values() if r.attachment_id}
    # Ищущие заявки — в «Faol»; отменённые и истёкшие без заказа — в «Tarix»
    # как «Bekor qilindi» (макет M2), за последние 90 дней.
    open_reqs = (
        db.query(EquipmentRequest)
        .filter(
            EquipmentRequest.client_id == user.id,
            EquipmentRequest.tariff.isnot(None),
            EquipmentRequest.order_id.is_(None),
            EquipmentRequest.status.in_(("open", "awaiting_payment", "cancelled", "expired")),
            EquipmentRequest.created_at > func.now() - text("interval '90 days'"),
        )
        .order_by(EquipmentRequest.created_at.desc())
        .limit(100)
        .all()
    )
    att_ids |= {r.attachment_id for r in open_reqs if r.attachment_id}
    from app.models.card import UserCard

    card_ids = {r.card_id for r in list(reqs.values()) + open_reqs if r.card_id}
    card_labels = {
        c.id: f"{(c.ps or 'karta').capitalize()} •• {c.pan[-4:]}"
        for c in db.query(UserCard).filter(UserCard.id.in_(card_ids)).all()
    } if card_ids else {}
    atts = {
        a.id: (a.name_ru if lang == "ru" else a.name_uz)
        for a in db.query(EquipmentAttachment).filter(EquipmentAttachment.id.in_(att_ids)).all()
    } if att_ids else {}

    cards = []
    for r in open_reqs:
        cards.append(dict(
            kind="request", id=r.id, order_id=None, request_id=r.id,
            stage="searching" if r.status in ("open", "awaiting_payment") else "cancelled",
            status=r.status, equipment_type=r.equipment_type, equipment_model=None,
            plate_number=None, owner_name=None, owner_initials=None, owner_phone=None,
            owner_rating=None, my_rating=None,
            start_date=_iso(r.start_date), start_time=_iso(r.start_time), hours=r.hours,
            tariff=r.tariff, from_address=r.origin_address, to_address=r.delivery_address,
            from_lat=r.origin_latitude, from_lon=r.origin_longitude,
            to_lat=r.delivery_latitude, to_lon=r.delivery_longitude,
            total=_num(r.budget), delivery_fee=None, payment_method=r.payment_method,
            card_label=card_labels.get(r.card_id),
            attachment_id=r.attachment_id, attachment_name=atts.get(r.attachment_id),
            attachment_price=_num(r.attachment_price),
            started_at=None, finished_at=None, created_at=_iso(r.created_at),
        ))
    for o in orders:
        r = reqs.get(o.id)
        ex = executor(db, o)
        mine = (
            db.query(Review.rating)
            .filter(Review.user_id == user.id, Review.equipment_id == o.equipment_id)
            .order_by(Review.id.desc()).first()
        )
        cards.append(dict(
            kind="order", id=o.id, order_id=o.id, request_id=r.id if r else None,
            stage=_stage(o), status=o.status,
            equipment_type=ex["equipment_type"], equipment_model=ex["equipment_model"],
            plate_number=ex["plate_number"], owner_name=ex["owner_name"],
            owner_initials=ex["owner_initials"],
            # Телефон только пока заказ живой — как в карточке исполнителя
            owner_phone=ex["owner_phone"] if o.status in ("pending", "confirmed", "completed") else None,
            owner_rating=ex["rating"], my_rating=mine[0] if mine else None,
            start_date=_iso(o.start_date), start_time=_iso(o.start_time), hours=o.hours,
            tariff=o.tariff,
            from_address=r.origin_address if r else None, to_address=o.delivery_address,
            from_lat=r.origin_latitude if r else None, from_lon=r.origin_longitude if r else None,
            to_lat=o.delivery_latitude, to_lon=o.delivery_longitude,
            total=_num(o.total_amount), delivery_fee=_num(o.delivery_fee),
            payment_method=o.payment_method,
            card_label=card_labels.get(r.card_id) if r else None,
            attachment_id=r.attachment_id if r else None,
            attachment_name=atts.get(r.attachment_id) if r else None,
            attachment_price=_num(r.attachment_price) if r else None,
            started_at=_iso(o.started_at), finished_at=_iso(o.finished_at),
            created_at=_iso(o.created_at),
        ))
    return cards


# ------------------------------------------------- E7 · Kartadan to'lov o'tmadi

def _client_card_order(db: Session, order_id: int, user: User) -> Order:
    order = _lock_order(db, order_id)
    if order.user_id != user.id:
        raise HTTPException(403, "Faqat buyurtmachi")
    if order.status != "confirmed" or order.payment_method != "card":
        raise HTTPException(409, "Bu buyurtma karta bilan to'lov kutmayapti")
    if order.finished_at is None:
        raise HTTPException(409, "Ish hali yakunlanmagan")
    return order


def pay_with_card(db: Session, order_id: int, user: User, card_id: int) -> Order:
    """«Boshqa karta tanlash» / «Qayta urinish»: списать сразу с карты."""
    from app.services import card_service, order_service

    order = _client_card_order(db, order_id, user)
    card = card_service.own_card(db, user, card_id)
    cp = card_service.pay_now(db, user, card, Decimal(str(order.total_amount)), order.id)
    if cp.status != "charged":
        db.commit()
        raise HTTPException(402, "card_payment_failed")
    order_service.settle_card_paid(db, order, _equipment(db, order))
    db.commit()
    db.refresh(order)
    return order


def switch_to_cash(db: Session, order_id: int, user: User) -> Order:
    """
    «Naqd to'lash»: клиент отдаёт владельцу наличные. Комиссия тогда
    удерживается с баланса владельца, как в обычном наличном заказе —
    не хватает денег у владельца → 409, пусть клиент платит картой.
    """
    from app.models.card import CardPayment
    from app.services import card_service, order_service
    from app.schemas.order import OrderUpdate

    order = _client_card_order(db, order_id, user)
    eq = _equipment(db, order)
    commission = Decimal(str(order.commission or 0))
    ob = db.query(Balance).filter(Balance.user_id == eq.owner_id).with_for_update().first()
    available = Decimal(str(ob.balance)) - Decimal(str(ob.frozen_balance)) if ob else Decimal("0")
    if commission > 0 and available < commission:
        raise HTTPException(409, "Texnika egasining hisobida komissiya uchun mablag' yetmaydi")
    for cp in db.query(CardPayment).filter(CardPayment.order_id == order.id).all():
        card_service.cancel_hold(cp)
    if commission > 0:
        ob.frozen_balance = Decimal(str(ob.frozen_balance)) + commission
    order.owner_frozen = commission
    order.payment_method = "cash"
    db.commit()
    return order_service.update_order(db, order.id, OrderUpdate(status="completed"), user.id)
