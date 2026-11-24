"""
Регионы цен (Шерзодбек, 24.11.2026): «Андижан — другая цена, Ташкент —
другая, например кран 300 000 в час в Андижане и 350 000 в Ташкенте».

Админ рисует зону многоугольником на карте (`admin/zones.php`) и задаёт в
ней СВОИ цены на пары «тип × тариф» (`zone_tariffs`) и, если надо,
надбавку в процентах (`surcharge_percent`, «povishenie»). Цену заказа
определяет точка, КУДА нужна техника (`delivery_*`).

Чего в зоне нет — берётся из базовых `tariffs`: незаданная цена в зоне
означает «как везде», а не «тип недоступен». Зоны пересекаются — побеждает
меньший `sort_order`.
"""
from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    UniqueConstraint,
)
from sqlalchemy.sql import func

from app.db.base import Base


class PriceZone(Base):
    __tablename__ = "price_zones"

    id = Column(Integer, primary_key=True)
    name = Column(String(100), nullable=False)
    #: [[lat, lon], ...] — вершины многоугольника, не меньше трёх.
    polygon = Column(JSON, nullable=False)
    #: Надбавка ко всей сумме тарифного заказа в зоне, % (−50…200).
    surcharge_percent = Column(Numeric(5, 2), nullable=False, default=0, server_default="0")
    is_enabled = Column(Boolean, nullable=False, default=True, server_default="true")
    sort_order = Column(Integer, nullable=False, default=0, server_default="0")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint("surcharge_percent BETWEEN -50 AND 200", name="check_zone_surcharge"),
    )


class ZoneTariff(Base):
    """Цена тарифа в зоне. NULL в цене — как в базовом тарифе."""

    __tablename__ = "zone_tariffs"

    id = Column(Integer, primary_key=True)
    zone_id = Column(Integer, ForeignKey("price_zones.id", ondelete="CASCADE"), nullable=False, index=True)
    equipment_type = Column(String(50), nullable=False)
    tier = Column(String(10), nullable=False)
    #: Цена часа (Ekonom) — или цена пакета (Tezkor 6 ч, Kun davomida 12 ч),
    #: смотря каков базовый тариф. Одно поле, чтобы админ не путал два.
    price = Column(Numeric(12, 2), nullable=False)

    __table_args__ = (
        UniqueConstraint("zone_id", "equipment_type", "tier", name="uq_zone_tariff"),
        CheckConstraint("tier IN ('econom','fast','day')", name="check_zone_tariff_tier"),
        CheckConstraint("price > 0", name="check_zone_tariff_price"),
    )
