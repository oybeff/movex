from sqlalchemy import BigInteger, Column, Integer, Numeric, String, DateTime, ForeignKey
from sqlalchemy.sql import func
from sqlalchemy import CheckConstraint
from app.db.base import Base

class Balance(Base):
    __tablename__ = "balances"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False, index=True)
    balance = Column(Numeric(12,2), default=0.0, nullable=False)  # Umumiy balans
    frozen_balance = Column(Numeric(12,2), default=0.0, nullable=False)  # Muzlatilgan balans (pending orders uchun)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    __table_args__ = (
        CheckConstraint("balance >= 0", name="check_balance_non_negative"),
        CheckConstraint("frozen_balance >= 0", name="check_frozen_balance_non_negative"),
        CheckConstraint("frozen_balance <= balance", name="check_frozen_balance_not_exceed_balance"),
    )


class BalanceTransaction(Base):
    __tablename__ = "balance_transactions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    amount = Column(Numeric(12,2), nullable=False)
    type = Column(String(20), nullable=False)  # 'topup', 'payment', 'income', 'refund'
    status = Column(String(20), nullable=False)  # 'pending', 'completed', 'failed'
    payment_method = Column(String(50))  # 'click', 'payme', etc.
    description = Column(String(500))
    order_id = Column(Integer, ForeignKey("orders.id", ondelete="SET NULL"), nullable=True)  # Buyurtma bilan bog'lash

    # Click to'lov tizimi uchun qo'shimcha ustunlar
    click_trans_id = Column(Integer, nullable=True)  # Click transaction ID
    click_prepare_id = Column(Integer, nullable=True)  # Click prepare ID
    phone_number = Column(String(20), nullable=True)  # Telefon raqam (Click uchun)

    # Payme (Paycom) Merchant API uchun.
    # Payme protokoli tranzaksiyaning o'z holatini talab qiladi:
    #   1 — yaratilgan, 2 — o'tkazilgan, -1 — bekor qilingan,
    #   -2 — o'tkazilgandan keyin bekor qilingan
    # Vaqtlar Payme talabi bo'yicha millisekundlarda saqlanadi.
    payme_transaction_id = Column(String(50), nullable=True, index=True)
    payme_state = Column(Integer, nullable=True)
    payme_create_time = Column(BigInteger, nullable=True)
    payme_perform_time = Column(BigInteger, nullable=True)
    payme_cancel_time = Column(BigInteger, nullable=True)
    payme_reason = Column(Integer, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        CheckConstraint("amount > 0", name="check_transaction_amount"),
        CheckConstraint("type IN ('topup','payment','income','refund')", name="check_transaction_type"),
        CheckConstraint("status IN ('pending','completed','failed','canceled')", name="check_transaction_status"),
        CheckConstraint("payment_method IN ('click','payme','uzum','card','cash') OR payment_method IS NULL", name="check_transaction_payment_method"),
    )

