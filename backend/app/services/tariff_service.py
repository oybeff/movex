"""
Расчёт тарифного заказа «как такси».

Одна функция [quote] на экран и на создание заказа: приложение показывает
цену из GET /requests/tariffs, а create_request считает её ЗАНОВО тем же
кодом и не верит сумме из тела запроса. Иначе на экране одна цифра, а
заморозится другая — ровно то, что уже чинилось в каталоге.
"""
from dataclasses import dataclass
from decimal import Decimal
from typing import List, Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.tariff import TARIFF_TIERS, EquipmentAttachment, Tariff

#: Больше суток один тарифный заказ не длится: для этого есть каталог
#: с посуточной ценой.
MAX_HOURS = 24


@dataclass
class TariffQuote:
    tier: str
    price_per_hour: Decimal
    attachment_per_hour: Decimal
    min_hours: int
    hours: int
    total: Decimal
    eta_minutes: Optional[int] = None


def active_tariffs(db: Session, equipment_type: str) -> List[Tariff]:
    rows = (
        db.query(Tariff)
        .filter(Tariff.equipment_type == equipment_type, Tariff.is_active.is_(True))
        .all()
    )
    order = {t: i for i, t in enumerate(TARIFF_TIERS)}
    return sorted(rows, key=lambda r: order.get(r.tier, 99))


def types_with_tariffs(db: Session) -> List[str]:
    """Типы, для которых админ задал хотя бы один активный тариф."""
    rows = (
        db.query(Tariff.equipment_type)
        .filter(Tariff.is_active.is_(True))
        .distinct()
        .all()
    )
    return sorted(r[0] for r in rows)


def active_attachments(db: Session, equipment_type: str) -> List[EquipmentAttachment]:
    return (
        db.query(EquipmentAttachment)
        .filter(
            EquipmentAttachment.equipment_type == equipment_type,
            EquipmentAttachment.is_active.is_(True),
        )
        .order_by(EquipmentAttachment.sort_order, EquipmentAttachment.id)
        .all()
    )


def get_attachment(
    db: Session, equipment_type: str, attachment_id: Optional[int]
) -> Optional[EquipmentAttachment]:
    """Навесное для типа. Чужое, выключенное или несуществующее — 400."""
    if attachment_id is None:
        return None
    att = db.query(EquipmentAttachment).filter(EquipmentAttachment.id == attachment_id).first()
    if att is None or not att.is_active or att.equipment_type != equipment_type:
        raise HTTPException(400, "Bu jihoz shu texnika uchun mavjud emas")
    return att


def quote_all(
    db: Session,
    equipment_type: str,
    hours: Optional[int],
    attachment_id: Optional[int],
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
) -> List[TariffQuote]:
    """Все активные тарифы типа с итоговой суммой. hours=None — минимум тарифа.
    
    Динамический расчёт времени прибытия (eta_minutes): если переданы координаты
    клиента, ищется ближайшая доступная техника данного типа и рассчитывается
    время доезда по формуле (дистанция / 25 км/ч) + буфер подготовки.
    """
    att = get_attachment(db, equipment_type, attachment_id)
    att_price = Decimal(str(att.price_per_hour)) if att else Decimal("0")

    # Ищем минимальное расстояние до доступной техники данного типа
    nearest_km: Optional[float] = None
    if latitude is not None and longitude is not None:
        try:
            from app.models.equipment import Equipment
            from app.models.user import User
            from app.services import pricing_service

            machines = (
                db.query(Equipment)
                .filter(
                    Equipment.type == equipment_type,
                    Equipment.deleted_at.is_(None),
                    Equipment.status == "available",
                )
                .all()
            )
            for eq in machines:
                e_lat = float(eq.latitude) if eq.latitude is not None else None
                e_lon = float(eq.longitude) if eq.longitude is not None else None
                if e_lat is None or e_lon is None:
                    owner = db.query(User).filter(User.id == eq.owner_id).first()
                    if owner and owner.search_latitude is not None and owner.search_longitude is not None:
                        e_lat = float(owner.search_latitude)
                        e_lon = float(owner.search_longitude)
                if e_lat is not None and e_lon is not None:
                    dist = float(pricing_service.distance_km(e_lat, e_lon, latitude, longitude))
                    if nearest_km is None or dist < nearest_km:
                        nearest_km = dist
        except Exception:
            nearest_km = None

    result = []
    for t in active_tariffs(db, equipment_type):
        h = max(hours or t.min_hours, t.min_hours)
        h = min(h, MAX_HOURS)
        price = Decimal(str(t.price_per_hour))

        eta = t.eta_minutes
        if t.tier == "day":
            eta = None  # Для «Kun davomida» всегда подпись «Bugun ichida»
        elif nearest_km is not None:
            # Средняя скорость спецтехники по городу 25 км/ч (1 км ≈ 2.4 мин)
            travel_mins = int(round(nearest_km / 25.0 * 60))
            if t.tier == "fast":
                # Срочный вызов: подача сразу + 5 мин на выезд, минимум 10 мин
                eta = max(10, min(120, travel_mins + 5))
            else:
                # Эконом: плановая подача с буфером 15 мин, минимум 20 мин
                eta = max(20, min(180, travel_mins + 15))

        result.append(TariffQuote(
            tier=t.tier,
            price_per_hour=price,
            attachment_per_hour=att_price,
            min_hours=t.min_hours,
            hours=h,
            total=(price + att_price) * h,
            eta_minutes=eta,
        ))
    return result


def quote(
    db: Session, equipment_type: str, tier: str, hours: int, attachment_id: Optional[int]
) -> TariffQuote:
    """
    Сумма ОДНОГО тарифа для создания заказа. Здесь, в отличие от экрана,
    часы не подтягиваются к минимуму молча: меньше минимума — 400, чтобы
    клиент не заплатил за 4 часа, думая, что заказал 2.
    """
    if tier not in TARIFF_TIERS:
        raise HTTPException(400, "Tarif noto'g'ri")
    tariff = next((t for t in active_tariffs(db, equipment_type) if t.tier == tier), None)
    if tariff is None:
        raise HTTPException(400, "Bu texnika uchun tarif mavjud emas")
    if hours is None or hours < tariff.min_hours:
        raise HTTPException(400, f"Ish vaqti kamida {tariff.min_hours} soat")
    if hours > MAX_HOURS:
        raise HTTPException(400, f"Ish vaqti {MAX_HOURS} soatdan oshmasin")
    att = get_attachment(db, equipment_type, attachment_id)
    att_price = Decimal(str(att.price_per_hour)) if att else Decimal("0")
    price = Decimal(str(tariff.price_per_hour))
    return TariffQuote(
        tier=tier,
        price_per_hour=price,
        attachment_per_hour=att_price,
        min_hours=tariff.min_hours,
        hours=hours,
        total=(price + att_price) * hours,
        eta_minutes=tariff.eta_minutes,
    )
