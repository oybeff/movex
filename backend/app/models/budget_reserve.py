from sqlalchemy import Column, Integer, Numeric, String, DateTime, ForeignKey
from sqlalchemy.sql import func
from sqlalchemy import CheckConstraint
from app.db.base import Base


class BudgetReserve(Base):
    """
    Budjet jamg'armasi jadvali
    
    Har bir buyurtmadan olingan 10% komissiya bu yerda saqlanadi.
    Bu pul tizim budjetiga tegishli va keyinchalik marketing, 
    texnik xizmat va boshqa xarajatlar uchun ishlatilishi mumkin.
    """
    __tablename__ = "budget_reserves"

    id = Column(Integer, primary_key=True, index=True)
    order_id = Column(Integer, ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True)
    amount = Column(Numeric(12, 2), nullable=False)  # Komissiya summasi (10%)
    description = Column(String(500))
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        CheckConstraint("amount > 0", name="check_budget_reserve_amount"),
    )

