from sqlalchemy import Column, Integer, Numeric, String, DateTime, ForeignKey
from sqlalchemy.sql import func
from sqlalchemy import CheckConstraint
from app.db.base import Base

class Payment(Base):
    __tablename__ = "payments"

    id = Column(Integer, primary_key=True, index=True)
    order_id = Column(Integer, ForeignKey("orders.id", ondelete="CASCADE"), nullable=False)
    amount = Column(Numeric(10,2), nullable=False)
    commission = Column(Numeric(10,2), nullable=False)
    payment_method = Column(String(50))
    status = Column(String(20), nullable=False)
    paid_at = Column(DateTime(timezone=True))

    __table_args__ = (
        CheckConstraint("amount > 0", name="check_payment_amount"),
        CheckConstraint("payment_method IN ('Payme','Click','Card') OR payment_method IS NULL", name="check_payment_method"),
        CheckConstraint("status IN ('pending','completed','failed')", name="check_payment_status"),
    )
