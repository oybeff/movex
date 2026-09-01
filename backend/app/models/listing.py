"""
E'lonlar taxtasi.

Zayavkadan farqi. Zayavkada mijoz ma'lumotnomadagi TURNI tanlaydi, egalar
narx taklif qiladi, mijoz esa ular orasidan birini tanlaydi — bu savdo.

E'londa boshqacha: mijoz o'z so'zlari bilan nima kerakligini yozadi (bozorda
yo'q texnika, yuk ortish, biror xizmat), egasi "olaman" deydi, mijoz esa
tasdiqlaydi. Savdo yo'q, ma'lumotnoma ham shart emas.

PUL HARAKATI YO'Q. E'lon — bu tanishtirish: kelishilgandan keyin ikkala
tomon bir-birining telefonini va chatini oladi. Pulni eskrou orqali
o'tkazish kerak bo'lsa, bu alohida ish: buyurtma jadvali aniq texnikaga
bog'langan, e'londa esa texnika umuman bo'lmasligi mumkin.
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
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.db.base import Base

#: E'lon ochiq turadigan muddat
LISTING_TTL_DAYS = 14

#: Bitta mijozda bir vaqtda ochiq tura oladigan e'lonlar soni
MAX_OPEN_LISTINGS_PER_CLIENT = 20

#: Bitta e'longa nechta rasm
MAX_LISTING_PHOTOS = 6


class Listing(Base):
    """Mijozning e'loni."""

    __tablename__ = "listings"

    id = Column(Integer, primary_key=True, index=True)
    client_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    title = Column(String(120), nullable=False)
    description = Column(Text, nullable=True)

    # Tur ixtiyoriy: e'lon ma'lumotnomaga bog'lanmagan. Ko'rsatilsa —
    # ro'yxatda ikonka chiqadi va egalar turi bo'yicha filtrlay oladi.
    equipment_type = Column(String(50), nullable=True, index=True)

    budget = Column(Numeric(12, 2), nullable=True)

    address = Column(Text, nullable=True)
    latitude = Column(Numeric(10, 7), nullable=True)
    longitude = Column(Numeric(10, 7), nullable=True)

    needed_from = Column(Date, nullable=True)
    needed_to = Column(Date, nullable=True)

    contact_phone = Column(String(20), nullable=True)

    # open      — javob kutilmoqda
    # taken     — egasi oldi, mijozning tasdig'i kutilmoqda
    # confirmed — mijoz tasdiqladi, ish boshlandi
    # done      — yakunlandi
    # cancelled — mijoz bekor qildi
    # expired   — muddati o'tdi
    status = Column(String(20), nullable=False, default="open", index=True)

    taken_by = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    taken_at = Column(DateTime(timezone=True), nullable=True)
    confirmed_at = Column(DateTime(timezone=True), nullable=True)
    finished_at = Column(DateTime(timezone=True), nullable=True)

    #: Nechta marta ochildi. Mijozga "e'lonim ko'rinyaptimi" degan savolga
    #: javob beradi.
    views_count = Column(Integer, nullable=False, default=0)

    expires_at = Column(DateTime(timezone=True), nullable=True, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    photos = relationship(
        "ListingPhoto",
        back_populates="listing",
        cascade="all, delete-orphan",
        order_by="ListingPhoto.id",
    )

    __table_args__ = (
        CheckConstraint(
            "status IN ('open','taken','confirmed','done','cancelled','expired')",
            name="check_listing_status",
        ),
        CheckConstraint("budget IS NULL OR budget > 0", name="check_listing_budget"),
        CheckConstraint(
            "needed_to IS NULL OR needed_from IS NULL OR needed_to >= needed_from",
            name="check_listing_dates",
        ),
        CheckConstraint("views_count >= 0", name="check_listing_views"),
    )


class ListingPhoto(Base):
    """E'longa biriktirilgan rasm."""

    __tablename__ = "listing_photos"

    id = Column(Integer, primary_key=True, index=True)
    listing_id = Column(
        Integer, ForeignKey("listings.id", ondelete="CASCADE"), nullable=False, index=True
    )
    url = Column(String(500), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    listing = relationship("Listing", back_populates="photos")
