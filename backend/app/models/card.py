"""Привязанные карты и холды под заказы (макеты K1–K6, Pr3, E7)."""
from sqlalchemy import (Boolean, CheckConstraint, Column, DateTime, ForeignKey, Integer, Numeric,
                        String, Text)
from sqlalchemy.sql import func

from app.db.base import Base


class UserCard(Base):
    """Токен карты от Multicard. Номер карты целиком у нас не хранится."""
    __tablename__ = "user_cards"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    token = Column(String(255), nullable=False, unique=True)
    pan = Column(String(20), nullable=False)
    ps = Column(String(20), nullable=True)
    holder_name = Column(String(100), nullable=True)
    is_default = Column(Boolean, nullable=False, default=False, server_default="false")
    status = Column(String(10), nullable=False, default="active", server_default="active")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (CheckConstraint("status IN ('active','deleted')", name="check_card_status"),)


class CardBindSession(Base):
    __tablename__ = "card_bind_sessions"

    session_id = Column(String(64), primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    card_id = Column(Integer, ForeignKey("user_cards.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class CardPayment(Base):
    """
    Холд под заказ: draft (ждёт OTP) → active (сумма заблокирована на
    карте) → charged (списано после работы) | cancelled (отмена) | failed.
    unknown — шлюз не ответил, статус надо спросить (GET /payment/{uuid}).
    """
    __tablename__ = "card_payments"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    card_id = Column(Integer, ForeignKey("user_cards.id", ondelete="SET NULL"), nullable=True)
    request_id = Column(Integer, ForeignKey("equipment_requests.id", ondelete="SET NULL"), nullable=True, index=True)
    order_id = Column(Integer, ForeignKey("orders.id", ondelete="SET NULL"), nullable=True, index=True)
    uuid = Column(String(64), nullable=True, unique=True)
    amount = Column(Numeric(12, 2), nullable=False)
    status = Column(String(12), nullable=False, default="draft", server_default="draft")
    error = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint(
            "status IN ('draft','active','charged','cancelled','failed','unknown')",
            name="check_card_payment_status",
        ),
        CheckConstraint("amount > 0", name="check_card_payment_amount"),
    )
