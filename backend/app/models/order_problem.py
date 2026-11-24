"""
Nizo (shikoyat) — mijoz ilovasi B5 «Muammo haqida xabar» va 24.11.2026
dan boshlab hamma turdagi buyurtma: texnika, yuk tashish, material
(Figma «Admin panel» 07). Ochishi mumkin: mijoz yoki ijrochi.

order_id — kind'ga qarab orders / freight_orders / material_orders id
(FK yo'q: buyurtma uch xil jadvalda).
"""
from sqlalchemy import JSON, Boolean, CheckConstraint, Column, DateTime, ForeignKey, Integer, Numeric, String, Text
from sqlalchemy.sql import func

from app.db.base import Base

PROBLEM_REASONS = ("not_arrived", "wrong_equipment", "poor_quality", "price_differs", "other",
                   "damaged", "wrong_quantity", "client_no_pay", "client_absent")
#: Mijoz tanlashi mumkin bo'lgan sabablar / ijrochi tanlashi mumkin bo'lganlar
CLIENT_REASONS = ("not_arrived", "wrong_equipment", "poor_quality", "price_differs", "damaged",
                  "wrong_quantity", "other")
PERFORMER_REASONS = ("client_no_pay", "client_absent", "other")
PROBLEM_KINDS = ("equipment", "freight", "material")


class OrderProblem(Base):
    __tablename__ = "order_problems"

    id = Column(Integer, primary_key=True)
    kind = Column(String(12), nullable=False, default="equipment", server_default="equipment")
    order_id = Column(Integer, nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    #: client — buyurtmachi ochdi, performer — ijrochi (ega / haydovchi / sotuvchi)
    opened_role = Column(String(10), nullable=False, default="client", server_default="client")
    reason = Column(String(20), nullable=False)
    comment = Column(Text, nullable=True)
    #: Ссылки на свои загрузки (/static/problems/...), не больше трёх.
    photos = Column(JSON, nullable=True)
    #: open — ждёт админа, resolved — разобрана.
    status = Column(String(10), nullable=False, default="open", server_default="open")
    assigned_admin_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    #: SLA: birinchi javob (1 soat) va yechim (48 soat)
    first_response_at = Column(DateTime(timezone=True), nullable=True)
    resolved_at = Column(DateTime(timezone=True), nullable=True)
    resolved_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    #: client | partial | performer | close
    resolution = Column(String(12), nullable=True)
    refund_amount = Column(Numeric(14, 2), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        CheckConstraint("status IN ('open','resolved')", name="check_problem_status"),
    )


class DisputeMessage(Base):
    """Nizodagi xabar. visibility: all | client | performer | internal."""
    __tablename__ = "dispute_messages"

    id = Column(Integer, primary_key=True)
    problem_id = Column(Integer, ForeignKey("order_problems.id", ondelete="CASCADE"), nullable=False)
    author_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    author_role = Column(String(10), nullable=False)
    visibility = Column(String(10), nullable=False, default="all", server_default="all")
    text = Column(Text, nullable=True)
    photos = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class SupportThread(Base):
    """Ilovadagi «Yordam» chati: bitta foydalanuvchi — bitta ochiq suhbat."""
    __tablename__ = "support_threads"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    app = Column(String(10), nullable=False, default="client", server_default="client")
    status = Column(String(10), nullable=False, default="open", server_default="open")
    assigned_admin_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    last_message_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    user_read_at = Column(DateTime(timezone=True), nullable=True)
    admin_read_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class SupportMessage(Base):
    __tablename__ = "support_messages"

    id = Column(Integer, primary_key=True)
    thread_id = Column(Integer, ForeignKey("support_threads.id", ondelete="CASCADE"), nullable=False)
    author_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    is_admin = Column(Boolean, nullable=False, default=False, server_default="false")
    text = Column(Text, nullable=True)
    photo = Column(String(300), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
