from sqlalchemy import Column, Integer, Numeric, String, Date, DateTime, ForeignKey, Text
from sqlalchemy.sql import func
from sqlalchemy import CheckConstraint
from app.db.base import Base

class Order(Base):
    __tablename__ = "orders"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    equipment_id = Column(Integer, ForeignKey("equipment.id", ondelete="CASCADE"), nullable=False, index=True)
    start_date = Column(Date, nullable=False)
    end_date = Column(Date, nullable=False)
    status = Column(String(20), nullable=False, default='pending')  # pending, confirmed, rejected, cancelled, completed
    total_amount = Column(Numeric(10,2), nullable=False)  # Jami summa (narx + komissiya)
    commission = Column(Numeric(10,2), nullable=False)  # Komissiya
    frozen_amount = Column(Numeric(10,2), nullable=False)  # Muzlatilgan summa (total_amount)

    # Yetkazib berish joyi (delivery location)
    delivery_latitude = Column(String(50), nullable=False)  # Yetkazib berish joyi latitude
    delivery_longitude = Column(String(50), nullable=False)  # Yetkazib berish joyi longitude
    delivery_address = Column(Text, nullable=True)  # Yetkazib berish manzili (ixtiyoriy)
    delivery_distance = Column(Numeric(10,2), nullable=True)  # Yetkazish masofasi (km)
    delivery_fee = Column(Numeric(10,2), nullable=True)  # Yetkazish narxi

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint("status IN ('pending','confirmed','rejected','cancelled','completed')", name="check_order_status"),
        CheckConstraint("total_amount > 0", name="check_order_total_amount"),
        CheckConstraint("commission >= 0", name="check_order_commission"),
        CheckConstraint("frozen_amount >= 0", name="check_order_frozen_amount"),
        CheckConstraint("delivery_distance IS NULL OR delivery_distance >= 0", name="check_order_delivery_distance"),
        CheckConstraint("delivery_fee IS NULL OR delivery_fee >= 0", name="check_order_delivery_fee"),
    )
