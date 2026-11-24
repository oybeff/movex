"""
Регионы цен: в какой зоне точка и какая там цена тарифа.

Зона находится по точке, КУДА нужна техника. Цена в зоне подменяет
базовую (`tariffs`) только для заданных пар «тип × тариф»; надбавка зоны
применяется к итогу и округляется вверх до 1 000, как «+10% narx».
"""
from decimal import Decimal
from typing import List, Optional, Tuple

from sqlalchemy.orm import Session

from app.models.price_zone import PriceZone, ZoneTariff


def point_in_polygon(lat: float, lon: float, polygon) -> bool:
    """Луч вправо (ray casting). polygon — [[lat, lon], ...]."""
    if not polygon or len(polygon) < 3:
        return False
    inside = False
    n = len(polygon)
    j = n - 1
    for i in range(n):
        yi, xi = float(polygon[i][0]), float(polygon[i][1])
        yj, xj = float(polygon[j][0]), float(polygon[j][1])
        if (yi > lat) != (yj > lat):
            x_cross = (xj - xi) * (lat - yi) / (yj - yi) + xi
            if lon < x_cross:
                inside = not inside
        j = i
    return inside


def enabled_zones(db: Session) -> List[PriceZone]:
    return (
        db.query(PriceZone)
        .filter(PriceZone.is_enabled.is_(True))
        .order_by(PriceZone.sort_order, PriceZone.id)
        .all()
    )


def find_zone(db: Session, lat: Optional[float], lon: Optional[float]) -> Optional[PriceZone]:
    if lat is None or lon is None:
        return None
    for z in enabled_zones(db):
        if point_in_polygon(float(lat), float(lon), z.polygon):
            return z
    return None


def zone_price(db: Session, zone: Optional[PriceZone], equipment_type: str, tier: str) -> Optional[Decimal]:
    """Цена тарифа в зоне или None — тогда базовая."""
    if zone is None:
        return None
    row = (
        db.query(ZoneTariff)
        .filter(ZoneTariff.zone_id == zone.id, ZoneTariff.equipment_type == equipment_type,
                ZoneTariff.tier == tier)
        .first()
    )
    return Decimal(str(row.price)) if row else None


def apply_surcharge(total: Decimal, zone: Optional[PriceZone]) -> Decimal:
    pct = Decimal(str(zone.surcharge_percent)) if zone is not None and zone.surcharge_percent else Decimal("0")
    if pct == 0:
        return total
    raw = total * (100 + pct) / 100
    return ((raw + 999) // 1000) * 1000


def public_zones(db: Session) -> List[dict]:
    """Для приложения (E3): где обслуживаем, кроме базового прямоугольника."""
    return [{"name": z.name, "polygon": z.polygon} for z in enabled_zones(db)]


def served(db: Session, lat: Optional[float], lon: Optional[float]) -> Tuple[bool, Optional[PriceZone]]:
    """(обслуживаем ли точку, её зона). Зона расширяет базовую область."""
    from app.core import service_area

    zone = find_zone(db, lat, lon)
    return (zone is not None or service_area.contains(lat, lon)), zone
