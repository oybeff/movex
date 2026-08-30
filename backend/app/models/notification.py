from sqlalchemy import Boolean, CheckConstraint, Column, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.sql import func

from app.db.base import Base

# Xabarnoma turlari. Ilova shu qiymat bo'yicha ikonka va rangni tanlaydi.
NOTIFICATION_TYPES = (
    "order_created",     # egasiga: yangi buyurtma keldi
    "order_confirmed",   # mijozga: ega tasdiqladi
    "order_rejected",    # mijozga: ega rad etdi
    "order_cancelled",   # ikkinchi tomonga: buyurtma bekor qilindi
    "order_completed",   # ikkalasiga: buyurtma yakunlandi
    "balance_topup",     # hisob to'ldirildi
    "payout_paid",       # pul yechish arizasi to'landi
    "payout_rejected",   # pul yechish arizasi rad etildi
    "system",            # umumiy xabar
)


class Notification(Base):
    """
    Foydalanuvchiga ko'rsatiladigan xabarnoma.

    equipment_type ataylab shu yerda saqlanadi (buyurtmadan har safar
    olinmaydi): buyurtma o'chirilsa ham xabarnoma ro'yxatida to'g'ri
    ikonka qolishi kerak.
    """

    __tablename__ = "notifications"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    type = Column(String(32), nullable=False)
    title = Column(String(200), nullable=False)
    body = Column(Text, nullable=True)

    order_id = Column(Integer, ForeignKey("orders.id", ondelete="SET NULL"), nullable=True)
    equipment_type = Column(String(50), nullable=True)

    is_read = Column(Boolean, nullable=False, default=False, index=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)

    __table_args__ = (
        CheckConstraint(
            "type IN ('order_created','order_confirmed','order_rejected','order_cancelled',"
            "'order_completed','balance_topup','payout_paid','payout_rejected','system')",
            name="check_notification_type",
        ),
    )


class DeviceToken(Base):
    """
    Push uchun qurilma tokeni.

    Hozircha faqat saqlanadi: Firebase loyihasi ulanmaguncha push
    yuborilmaydi. Shunda ham ilova tokenni ro'yxatdan o'tkazishi mumkin —
    server tomoni tayyor.

    Bitta foydalanuvchida bir nechta qurilma bo'lishi mumkin, shuning uchun
    unique bo'lgan narsa — tokenning o'zi.
    """

    __tablename__ = "device_tokens"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    token = Column(String(255), nullable=False, unique=True, index=True)
    platform = Column(String(16), nullable=False)  # android | ios | web

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint("platform IN ('android','ios','web')", name="check_device_platform"),
    )
