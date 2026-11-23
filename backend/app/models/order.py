from sqlalchemy import Column, Integer, Numeric, String, Date, DateTime, ForeignKey, Text, Time
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
    # Boshlanish vaqti. Hozircha faqat tez buyurtmadan keladi.
    start_time = Column(Time, nullable=True)
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

    # Тарифный заказ (второй макет). balance — эскроу как раньше; cash —
    # клиент платит владельцу наличными, frozen_amount = 0, а на балансе
    # ВЛАДЕЛЬЦА при принятии замораживается комиссия (owner_frozen) и
    # списывается при завершении. Без этой заморозки владелец успел бы
    # вывести деньги, и комиссию было бы не с чего взять.
    payment_method = Column(String(10), nullable=False, default='balance', server_default='balance')
    owner_frozen = Column(Numeric(10,2), nullable=False, default=0, server_default='0')
    tariff = Column(String(10), nullable=True)
    hours = Column(Integer, nullable=True)
    # Ход тарифного заказа: владелец «Ketdik» → «Boshlash» → «Yakunlash»,
    # затем клиент подтверждает (status='completed').
    departed_at = Column(DateTime(timezone=True), nullable=True)
    # «Yetib keldim» водителя (макет D1 → D2), между выездом и началом работы
    arrived_at = Column(DateTime(timezone=True), nullable=True)
    started_at = Column(DateTime(timezone=True), nullable=True)
    finished_at = Column(DateTime(timezone=True), nullable=True)
    # Макет B1–B5: продление по согласию владельца, опоздание, кто отменил,
    # жалоба (жалоба останавливает автоподтверждение через 10 минут).
    extend_requested_hours = Column(Integer, nullable=True)
    delay_minutes = Column(Integer, nullable=True)
    delay_reason = Column(Text, nullable=True)
    cancelled_by = Column(String(10), nullable=True)
    # E6: plans | long_wait | wrong_address | other — mijoz tanlagan sabab
    cancel_reason = Column(String(30), nullable=True)
    problem_reported_at = Column(DateTime(timezone=True), nullable=True)
    # Макет водителя E1/E7: сколько клиент заплатил владельцу за отмену после
    # выезда или за неявку. Пишется в момент отмены — смена ставки в админке
    # историю не переписывает. 0 — компенсации не было.
    compensation = Column(Numeric(12, 2), nullable=False, default=0, server_default="0")

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint("status IN ('pending','confirmed','rejected','cancelled','completed')", name="check_order_status"),
        CheckConstraint("total_amount > 0", name="check_order_total_amount"),
        CheckConstraint("commission >= 0", name="check_order_commission"),
        CheckConstraint("frozen_amount >= 0", name="check_order_frozen_amount"),
        CheckConstraint("delivery_distance IS NULL OR delivery_distance >= 0", name="check_order_delivery_distance"),
        CheckConstraint("delivery_fee IS NULL OR delivery_fee >= 0", name="check_order_delivery_fee"),
        CheckConstraint("payment_method IN ('balance','cash','card')", name="check_order_payment_method"),
        CheckConstraint("owner_frozen >= 0", name="check_order_owner_frozen"),
        CheckConstraint("compensation >= 0", name="check_order_compensation"),
        # У наличного заказа нет эскроу клиента — только заморозка владельца.
        CheckConstraint("payment_method = 'balance' OR frozen_amount = 0", name="check_order_cash_no_escrow"),
    )
