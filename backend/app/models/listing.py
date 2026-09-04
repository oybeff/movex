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
    UniqueConstraint,
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

    offers = relationship(
        "ListingOffer",
        back_populates="listing",
        cascade="all, delete-orphan",
        order_by="ListingOffer.id",
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


class ListingOffer(Base):
    """
    E'longa javoban aytilgan O'Z narxi.

    "Olaman" tugmasi joyida qoladi: u muallifning byudjetiga rozilik
    bildiradi. Taklif esa boshqa narsa — ijrochi o'z summasini aytadi, va
    muallif kelgan takliflardan birini tanlaydi. Ikkalasi bir vaqtda
    ishlaydi, chunki e'lonlarning yarmida byudjet umuman ko'rsatilmaydi.

    Bir odam bitta e'longa BITTA taklif bera oladi (unique). Fikrini
    o'zgartirsa — o'sha taklifning narxi yangilanadi, yangi qator
    yaratilmaydi: aks holda bitta odam ro'yxatni to'ldirib tashlardi.

    PUL YO'Q, zayavkadagidek savdo ham yo'q. Narx — kelishuv uchun raqam;
    eskrou buyurtmaga bog'langan, e'londa esa texnika bo'lmasligi mumkin.
    """

    __tablename__ = "listing_offers"

    id = Column(Integer, primary_key=True, index=True)
    listing_id = Column(
        Integer, ForeignKey("listings.id", ondelete="CASCADE"), nullable=False, index=True
    )
    #: Kim taklif qildi. Rol muhim emas: e'lon ikki tomonlama.
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    price = Column(Numeric(12, 2), nullable=False)
    comment = Column(Text, nullable=True)

    # pending  — muallif hali qaramagan
    # accepted — muallif shu taklifni tanladi
    # declined — muallif boshqasini tanladi yoki e'lon yopildi
    # withdrawn — ijrochi o'zi qaytarib oldi
    status = Column(String(20), nullable=False, default="pending", index=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    listing = relationship("Listing", back_populates="offers")

    __table_args__ = (
        UniqueConstraint("listing_id", "user_id", name="uq_listing_offer_once"),
        CheckConstraint("price > 0", name="check_listing_offer_price"),
        CheckConstraint(
            "status IN ('pending','accepted','declined','withdrawn')",
            name="check_listing_offer_status",
        ),
    )


class ListingReaction(Base):
    """
    Yoqtirish va saqlash.

    Ikkalasi bitta jadvalda: farqi faqat `kind` da, mantiqi bir xil —
    bosildi/olib tashlandi, bir odamdan bitta. Alohida ikki jadval bir xil
    kodni ikki marta yozishga majbur qilardi.

    Sanoq denormalizatsiya QILINMAYDI: e'lonlar soni kichik, va
    listings.likes_count kabi ustun ertami-kechmi haqiqatdan ajralib
    qoladi. Kerak bo'lganda bitta GROUP BY so'rov bilan sanaladi.
    """

    __tablename__ = "listing_reactions"

    LIKE = "like"
    SAVE = "save"

    id = Column(Integer, primary_key=True, index=True)
    listing_id = Column(
        Integer, ForeignKey("listings.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    kind = Column(String(10), nullable=False, index=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)

    __table_args__ = (
        UniqueConstraint(
            "listing_id", "user_id", "kind", name="uq_listing_reaction_once"
        ),
        CheckConstraint("kind IN ('like','save')", name="check_listing_reaction_kind"),
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
