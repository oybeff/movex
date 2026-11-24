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
from sqlalchemy import Boolean, CheckConstraint, Column, DateTime, ForeignKey, Integer, Numeric, String, Text
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
    # «Yuk tashish» (24.11.2026): админ выбирает, как считать перевозку —
    # km: подача + км × цена; hour: часы × цена часа (не меньше min_hours).
    price_mode = Column(String(10), nullable=False, default="km")
    price_per_hour = Column(Numeric(12, 2), nullable=True)
    min_hours = Column(Integer, nullable=False, default=1)
    #: Клиент выбирает кузов (Labo, Porter, Gazel, Isuzu…)
    has_body_choice = Column(Boolean, nullable=False, default=False)
    # Шаги Y1–Y8 макета: марка и класс — для экрана марок (Y1), размеры
    # кузова — для проверки «sig'maydi» (Y7), кузова модели — Y3.
    brand = Column(String(40), nullable=True)
    size_class = Column(String(10), nullable=False, default="medium")
    body_length_m = Column(Numeric(5, 2), nullable=True)
    body_width_m = Column(Numeric(5, 2), nullable=True)
    body_height_m = Column(Numeric(5, 2), nullable=True)
    #: «tent,open,van,…» — какие кузова бывают у этой модели
    body_types = Column(String(120), nullable=False, default="")

    @property
    def body_list(self) -> list:
        return [b for b in (self.body_types or "").split(",") if b]
    is_enabled = Column(Boolean, nullable=False, default=True)
    sort_order = Column(Integer, nullable=False, default=0)
    #: Картинка модели из админки; NULL — общая картинка грузовика.
    icon_url = Column(String(255), nullable=True)

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
    #: tent — tentli (крытый), open — tentsiz; NULL — не указан
    body_type = Column(String(10), nullable=True)
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



class FreightOrder(Base):
    """
    «Yuk tashish»: клиент везёт СВОЙ груз из А в Б на выбранном грузовике.
    Цена — из админки по режиму машины (км или часы), фиксируется при
    создании. Водитель — из тех же, что возят стройматериалы.
    """

    __tablename__ = "freight_orders"

    id = Column(Integer, primary_key=True, index=True)
    client_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    driver_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    vehicle_code = Column(String(30), nullable=False)
    body_type = Column(String(10), nullable=True)
    cargo_tonnes = Column(Numeric(8, 2), nullable=True)
    cargo_note = Column(Text, nullable=True)
    cargo_type = Column(String(20), nullable=True)
    cargo_length_m = Column(Numeric(5, 2), nullable=True)
    cargo_width_m = Column(Numeric(5, 2), nullable=True)
    cargo_height_m = Column(Numeric(5, 2), nullable=True)
    cargo_volume_m3 = Column(Numeric(7, 2), nullable=True)
    needs_loader = Column(Boolean, nullable=False, default=False)
    loader_fee = Column(Numeric(12, 2), nullable=False, default=0)
    loader_mode = Column(String(4), nullable=True)   # hour | day
    loader_hours = Column(Integer, nullable=True)
    #: NULL — «Hozir»; иначе когда подать машину (Y5)
    scheduled_at = Column(DateTime(timezone=True), nullable=True)
    from_address = Column(Text, nullable=True)
    from_latitude = Column(Numeric(10, 7), nullable=False)
    from_longitude = Column(Numeric(10, 7), nullable=False)
    to_address = Column(Text, nullable=True)
    to_latitude = Column(Numeric(10, 7), nullable=False)
    to_longitude = Column(Numeric(10, 7), nullable=False)
    distance_km = Column(Numeric(10, 2), nullable=False)
    price_mode = Column(String(10), nullable=False)
    hours = Column(Integer, nullable=True)
    price = Column(Numeric(12, 2), nullable=False)
    payment_method = Column(String(10), nullable=False, default="balance")
    frozen_amount = Column(Numeric(12, 2), nullable=False, default=0)
    driver_fee = Column(Numeric(12, 2), nullable=True)
    driver_commission = Column(Numeric(12, 2), nullable=False, default=0)
    driver_frozen = Column(Numeric(12, 2), nullable=False, default=0)
    #: searching → accepted → loaded → arrived → done | cancelled
    status = Column(String(20), nullable=False, default="searching", index=True)
    accepted_at = Column(DateTime(timezone=True), nullable=True)
    loaded_at = Column(DateTime(timezone=True), nullable=True)
    arrived_at = Column(DateTime(timezone=True), nullable=True)
    finished_at = Column(DateTime(timezone=True), nullable=True)
    cancelled_by = Column(String(10), nullable=True)
    cancel_reason = Column(String(30), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
