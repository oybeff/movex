"""
Справочники, которые ведёт АДМИН, а не код (23.11.2026, просьба Шерзодбека:
«ko'p nastroykalarni admin panel orqali»).

equipment_catalog — типы техники: название uz/ru, группа для экрана
«Barcha kategoriyalar» (K2), подпись, иконка, вкл/выкл, порядок. Новый тип,
заведённый в админке, появляется в приложении без выпуска новой версии.
Код (`excavator`) по-прежнему то, что лежит в equipment.type и
equipment_requests.equipment_type — его не переименовывают.

delivery_vehicles — машины доставки стройматериалов: название, сколько
везёт (кг), объём кузова, цена подачи и километра. Раньше это был список
из четырёх машин в коде (Labo 0,7 т → сразу Isuzu 5 т).
"""
from sqlalchemy import Boolean, CheckConstraint, Column, DateTime, ForeignKey, Integer, Numeric, String
from sqlalchemy.sql import func

from app.db.base import Base


class EquipmentCatalogType(Base):
    __tablename__ = "equipment_catalog"

    code = Column(String(40), primary_key=True)
    name_uz = Column(String(100), nullable=False)
    name_ru = Column(String(100), nullable=False)
    group_code = Column(String(20), nullable=False, default="other")
    subtitle_uz = Column(String(150), nullable=True)
    subtitle_ru = Column(String(150), nullable=True)
    # /static/catalog/<файл> — загружается из админки. Пусто — иконка из
    # самого приложения (assets), если она там есть.
    icon_url = Column(String(255), nullable=True)
    is_enabled = Column(Boolean, nullable=False, default=True)
    sort_order = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class DeliveryVehicleRow(Base):
    __tablename__ = "delivery_vehicles"

    code = Column(String(30), primary_key=True)
    name = Column(String(60), nullable=False)
    capacity_kg = Column(Integer, nullable=False)
    volume_m3 = Column(Numeric(6, 2), nullable=True)
    # Доставка = (подача + км × цена км) × рейсы. Цена км пустая — берётся
    # цена км из товара продавца, как было до 23.11.2026.
    base_fee = Column(Numeric(12, 2), nullable=False, default=0)
    price_per_km = Column(Numeric(12, 2), nullable=True)
    is_enabled = Column(Boolean, nullable=False, default=True)
    sort_order = Column(Integer, nullable=False, default=0)

    __table_args__ = (
        CheckConstraint("capacity_kg > 0", name="check_delivery_vehicle_capacity"),
        CheckConstraint("base_fee >= 0", name="check_delivery_vehicle_base_fee"),
        CheckConstraint("price_per_km IS NULL OR price_per_km >= 0", name="check_delivery_vehicle_km"),
    )


class MaterialCategory(Base):
    """Категория стройматериала из ТЗ (qum, penablok…). unit: piece|bag|tonne|m3."""

    __tablename__ = "material_categories"

    code = Column(String(30), primary_key=True)
    name_uz = Column(String(100), nullable=False)
    name_ru = Column(String(100), nullable=False)
    unit = Column(String(10), nullable=False)
    is_enabled = Column(Boolean, nullable=False, default=True)
    sort_order = Column(Integer, nullable=False, default=0)


class DeliveryDriverProfile(Base):
    """
    Водитель, который возит стройматериалы. Одна машина на водителя: её
    выбирают из списка админки, грузоподъёмность берётся оттуда же.
    Своя цена за км/подачу — необязательна; клиент всё равно не платит
    больше расчёта по ценам админки.
    """

    __tablename__ = "delivery_driver_profiles"

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    vehicle_code = Column(String(30), ForeignKey("delivery_vehicles.code", ondelete="RESTRICT"), nullable=False)
    plate = Column(String(20), nullable=True)
    price_per_km = Column(Numeric(12, 2), nullable=True)
    base_fee = Column(Numeric(12, 2), nullable=True)
    is_online = Column(Boolean, nullable=False, default=False)
    latitude = Column(Numeric(10, 7), nullable=True)
    longitude = Column(Numeric(10, 7), nullable=True)
    location_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class DeliveryDriverCategory(Base):
    __tablename__ = "delivery_driver_categories"

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    category_code = Column(String(30), ForeignKey("material_categories.code", ondelete="CASCADE"), primary_key=True)
    min_quantity = Column(Numeric(12, 2), nullable=False, default=1)
