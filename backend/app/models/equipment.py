# app/models/equipment.py
from sqlalchemy import Column, Integer, String, Numeric, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.sql import func
from sqlalchemy import CheckConstraint
from sqlalchemy.orm import relationship
from app.db.base import Base

class Equipment(Base):
    __tablename__ = "equipment"

    id = Column(Integer, primary_key=True, index=True)
    owner_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    company_id = Column(Integer, ForeignKey("companies.id", ondelete="SET NULL"))
    # Ma'lumotnomadagi kod: 'excavator', 'truck_crane', ... (app/core/equipment_types.py)
    type = Column(String(50), nullable=False)
    # Kodga o'tishdan oldingi erkin matn. Vaqtinchalik: ma'lumotlar tekshirilgach,
    # alohida migratsiya bilan o'chiriladi.
    type_legacy = Column(String(50), nullable=True)
    model = Column(String(100), nullable=False)
    year = Column(Integer, CheckConstraint("year > 1900 AND year <= EXTRACT(YEAR FROM CURRENT_DATE)"))
    power_hp = Column(Integer)

    # цены
    price_per_hour = Column(Numeric(10,2))
    price_per_shift = Column(Numeric(10,2))
    price_per_day = Column(Numeric(10,2), nullable=False)
    delivery_price_per_km = Column(Numeric(10,2), nullable=True)  # Yetkazish narxi (km uchun)

    # гео
    address = Column(String(200))
    latitude = Column(Numeric(9,6))
    longitude = Column(Numeric(9,6))

    # характеристики
    payload_kg = Column(Integer)    # грузоподъемность
    dimensions = Column(String(100)) # размеры
    description = Column(Text)

    # старое поле (можно забыть, раз фото вынесли)
    photo_url = Column(Text)

    status = Column(String(20), nullable=False, default='available') # available | busy | maintenance

    available = Column(Boolean, default=True)  # можно оставить для совместимости
    deleted_at = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    photos = relationship("EquipmentPhoto", back_populates="equipment", cascade="all, delete-orphan")

    __table_args__ = (
        CheckConstraint("price_per_day > 0", name="check_price_per_day"),
        CheckConstraint("price_per_hour > 0 OR price_per_hour IS NULL", name="check_price_per_hour"),
        CheckConstraint("price_per_shift > 0 OR price_per_shift IS NULL", name="check_price_per_shift"),
        CheckConstraint("delivery_price_per_km >= 0 OR delivery_price_per_km IS NULL", name="check_delivery_price_per_km"),
        CheckConstraint("payload_kg >= 0 OR payload_kg IS NULL", name="check_payload_kg"),
        CheckConstraint("status IN ('available','busy','maintenance')", name="check_equipment_status"),
    )

class EquipmentPhoto(Base):
    __tablename__ = "equipment_photos"

    id = Column(Integer, primary_key=True)
    equipment_id = Column(Integer, ForeignKey("equipment.id", ondelete="CASCADE"), nullable=False)
    url = Column(Text, nullable=False)
    is_primary = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    equipment = relationship("Equipment", back_populates="photos")
