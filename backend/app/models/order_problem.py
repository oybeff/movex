"""Жалоба клиента по заказу — макет B5 «Muammo haqida xabar»."""
from sqlalchemy import JSON, CheckConstraint, Column, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.sql import func

from app.db.base import Base

PROBLEM_REASONS = ("not_arrived", "wrong_equipment", "poor_quality", "price_differs", "other")


class OrderProblem(Base):
    __tablename__ = "order_problems"

    id = Column(Integer, primary_key=True)
    order_id = Column(Integer, ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    reason = Column(String(20), nullable=False)
    comment = Column(Text, nullable=True)
    #: Ссылки на свои загрузки (/static/order_problems/...), не больше трёх.
    photos = Column(JSON, nullable=True)
    #: open — ждёт админа, resolved — разобрана.
    status = Column(String(10), nullable=False, default="open", server_default="open")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        CheckConstraint(
            "reason IN ('not_arrived','wrong_equipment','poor_quality','price_differs','other')",
            name="check_problem_reason",
        ),
        CheckConstraint("status IN ('open','resolved')", name="check_problem_status"),
    )
