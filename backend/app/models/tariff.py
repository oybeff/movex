"""
Тарифы быстрого заказа «как такси» (второй макет, ноябрь 2026).

Клиент выбирает тип техники, тариф и число часов — цену видит сразу и
не торгуется. Поэтому цену за час задаёт АДМИН (страница tariffs.php),
а не клиент и не владелец: решение владельца продукта от 12.11.2026.

Три тарифа на каждый тип техники:

    econom — «Ekonom», обычная подача;
    fast   — «Tezkor», быстрая подача, дороже;
    day    — «Kun davomida», подача в течение дня, дешевле.

Сумма заказа = (цена тарифа за час + цена навесного за час) × часы.
Считает её ТОЛЬКО сервер (tariff_service.quote), и та же функция
вызывается при создании заказа: иначе на экране одна сумма, а заморозится
другая.
"""
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    Integer,
    Numeric,
    String,
    UniqueConstraint,
)
from sqlalchemy.sql import func

from app.db.base import Base

#: Коды тарифов в порядке показа в приложении.
TARIFF_TIERS = ("econom", "fast", "day")


class Tariff(Base):
    """Цена часа для пары «тип техники × тариф»."""

    __tablename__ = "tariffs"

    id = Column(Integer, primary_key=True)
    #: Код типа из справочника ('excavator'), как в equipment.type.
    equipment_type = Column(String(50), nullable=False, index=True)
    tier = Column(String(10), nullable=False)
    price_per_hour = Column(Numeric(12, 2), nullable=False)
    #: Минимальный заказ, часов. Макет: «Ish vaqti — kamida 4 soat».
    min_hours = Column(Integer, nullable=False, default=1, server_default="1")
    #: Выключенный тариф в приложении не показывается и не заказывается.
    is_active = Column(Boolean, nullable=False, default=True, server_default="true")
    #: «45 daqiqada keladi» в карточке тарифа. Задаёт админ; пусто — без минут.
    eta_minutes = Column(Integer, nullable=True)
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    __table_args__ = (
        UniqueConstraint("equipment_type", "tier", name="uq_tariff_type_tier"),
        CheckConstraint("tier IN ('econom','fast','day')", name="check_tariff_tier"),
        CheckConstraint("price_per_hour > 0", name="check_tariff_price"),
        CheckConstraint("min_hours BETWEEN 1 AND 24", name="check_tariff_min_hours"),
        CheckConstraint("eta_minutes IS NULL OR eta_minutes BETWEEN 1 AND 1440", name="check_tariff_eta"),
    )


class EquipmentAttachment(Base):
    """
    Навесное оборудование («Qo'shimcha jihoz»): ковши, гидромолот, бур.
    Своё для каждого типа техники, цена — надбавка за час (0 — «включено
    в цену», как «Oddiy kovsh» в макете).
    """

    __tablename__ = "equipment_attachments"

    id = Column(Integer, primary_key=True)
    equipment_type = Column(String(50), nullable=False, index=True)
    #: Названия задаёт админ, перевод хранится здесь же: справочника
    #: навесного в коде нет.
    name_uz = Column(String(100), nullable=False)
    name_ru = Column(String(100), nullable=False)
    price_per_hour = Column(Numeric(12, 2), nullable=False, default=0, server_default="0")
    is_active = Column(Boolean, nullable=False, default=True, server_default="true")
    sort_order = Column(Integer, nullable=False, default=0, server_default="0")

    __table_args__ = (
        CheckConstraint("price_per_hour >= 0", name="check_attachment_price"),
    )
