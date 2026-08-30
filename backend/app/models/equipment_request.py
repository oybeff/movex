"""
Zayavkalar: mijoz texnikani "chaqiradi", egalari narx taklif qiladi.

Katalog bilan farqi. Katalogda mijoz ANIQ mashinani tanlaydi va buyurtma
darhol o'sha egaga ketadi. Bu yerda esa teskari: mijoz "menga ekskavator
kerak, manzil shu, sana shu, byudjetim shuncha" deydi, va zayavkani
radiusdagi hamma mos egalar ko'radi.

Ish tartibi:

    mijoz zayavka beradi (byudjet ko'rsatiladi)
        -> radiusdagi egalarga xabar
    egalar o'z narxi bilan taklif yuboradi
        -> mijozga har bir taklif haqida xabar
    mijoz bitta taklifni tanlaydi
        -> ODATDAGI BUYURTMA yaratiladi, puli muzlatiladi

MUHIM: zayavkaning o'zi pul harakatiga sabab BO'LMAYDI. Byudjet — bu
mijozning mo'ljali, hisob-kitob emas. Pul faqat taklif tanlangandan keyin,
buyurtma yaratilganda va faqat pricing_service hisobiga ko'ra qimirlaydi.
Aks holda byudjetni yozib pulni boshqarish yo'li ochilardi.
"""
from sqlalchemy import (
    CheckConstraint,
    Column,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.sql import func

from app.db.base import Base

#: Zayavka ochiq turadigan muddat — shundan keyin u o'z-o'zidan yopiladi.
REQUEST_TTL_HOURS = 48


class EquipmentRequest(Base):
    """Mijozning texnikaga bo'lgan zayavkasi."""

    __tablename__ = "equipment_requests"

    id = Column(Integer, primary_key=True, index=True)
    client_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    # Aniq mashina emas, TUR kodi: 'excavator'. Mashinani egasi taklifda
    # ko'rsatadi.
    equipment_type = Column(String(50), nullable=False, index=True)

    start_date = Column(Date, nullable=False)
    end_date = Column(Date, nullable=False)

    delivery_latitude = Column(String(50), nullable=False)
    delivery_longitude = Column(String(50), nullable=False)
    delivery_address = Column(Text, nullable=True)

    # Mijozning mo'ljali. Majburiy emas: "narxni o'zingiz ayting" ham bo'ladi.
    budget = Column(Numeric(12, 2), nullable=True)
    comment = Column(Text, nullable=True)

    # open      — takliflar kutilmoqda
    # assigned  — taklif tanlandi, buyurtma yaratildi
    # cancelled — mijoz bekor qildi
    # expired   — muddati o'tdi
    status = Column(String(20), nullable=False, default="open", index=True)

    # Tanlangan taklif va undan kelib chiqqan buyurtma
    selected_offer_id = Column(Integer, nullable=True)
    order_id = Column(
        Integer, ForeignKey("orders.id", ondelete="SET NULL"), nullable=True
    )

    expires_at = Column(DateTime(timezone=True), nullable=True, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    __table_args__ = (
        CheckConstraint(
            "status IN ('open','assigned','cancelled','expired')",
            name="check_request_status",
        ),
        CheckConstraint("end_date >= start_date", name="check_request_dates"),
        CheckConstraint("budget IS NULL OR budget > 0", name="check_request_budget"),
    )


class RequestOffer(Base):
    """Egasining zayavkaga javobi: qaysi mashina va qancha narxga."""

    __tablename__ = "request_offers"

    id = Column(Integer, primary_key=True, index=True)
    request_id = Column(
        Integer,
        ForeignKey("equipment_requests.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    owner_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    equipment_id = Column(
        Integer, ForeignKey("equipment.id", ondelete="CASCADE"), nullable=False
    )

    # Egasi taklif qilgan KUNLIK narx. Umumiy summani buyurtma yaratilganda
    # pricing_service hisoblaydi — shu yerda yozilgan summaga ishonilmaydi.
    price_per_day = Column(Numeric(12, 2), nullable=False)
    comment = Column(Text, nullable=True)

    # pending — mijoz hali qaramagan
    # accepted — tanlandi
    # rejected — boshqa taklif tanlandi yoki mijoz rad etdi
    # withdrawn — egasi o'zi olib tashladi
    status = Column(String(20), nullable=False, default="pending", index=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    __table_args__ = (
        # Bitta mashina bitta zayavkaga ikki marta taklif qilinmaydi
        UniqueConstraint("request_id", "equipment_id", name="uq_offer_request_equipment"),
        CheckConstraint(
            "status IN ('pending','accepted','rejected','withdrawn')",
            name="check_offer_status",
        ),
        CheckConstraint("price_per_day > 0", name="check_offer_price"),
    )
