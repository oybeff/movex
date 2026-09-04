"""
Qurilish materiallari: sotuvchining tovari va xaridorning buyurtmasi.

Ijaradan farqi. Texnika ijaraga olinadi va qaytariladi, narxi kunlik. Bu
yerda tovar SOTIB olinadi: narx birlik uchun, muddat yo'q, qaytarish ham
yo'q. Shuning uchun alohida jadvallar — orders ga tiqib bo'lmaydi, u
aniq texnikaga va sanalarga bog'langan.

Pul harakati esa AYNAN ijaradagidek: xaridorning balansidan summa
muzlatiladi, tovar yetkazilgach yechiladi va sotuvchiga o'tadi, ulush
sotuvchidan ushlanadi. Boshqacha qilishning sababi yo'q, va ikki xil
eskrou ikki xil xatoni anglatardi.
"""
from sqlalchemy import (
    CheckConstraint,
    Column,
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

#: Bitta tovarga nechta rasm
MAX_MATERIAL_PHOTOS = 6


class MaterialProduct(Base):
    """
    Sotuvchining tovari: "G'isht M-100, 900 so'm/dona, 50 000 dona bor".

    MODERATSIYADAN o'tadi: sotuvchi qo'shadi, admin tasdiqlaydi. Tasdiqsiz
    tovar katalogda ko'rinmaydi. Sabab oddiy — katalog xaridorning birinchi
    ko'radigan joyi, va u yerdagi axlat butun bo'limni o'ldiradi.
    """

    __tablename__ = "material_products"

    STATUS_PENDING = "pending"
    STATUS_APPROVED = "approved"
    STATUS_REJECTED = "rejected"

    id = Column(Integer, primary_key=True, index=True)
    owner_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )

    #: Ma'lumotnoma kodi — material_types.py
    material_type = Column(String(50), nullable=False, index=True)

    title = Column(String(150), nullable=False)
    description = Column(Text, nullable=True)

    #: piece / bag / tonne / m3
    unit = Column(String(10), nullable=False)

    #: Bitta birlikning og'irligi. MASHINA SHUNGA QARAB tanlanadi:
    #: 5 000 dona g'isht × 3.5 kg = 17.5 tonna, ya'ni KamAZ kerak.
    unit_weight_kg = Column(Numeric(12, 3), nullable=False)

    price_per_unit = Column(Numeric(12, 2), nullable=False)

    #: Eng kam buyurtma. Bitta g'isht sotishning ma'nosi yo'q.
    min_quantity = Column(Numeric(12, 2), nullable=False, default=1)

    #: Omborda qancha bor. NULL — cheklanmagan.
    available_quantity = Column(Numeric(12, 2), nullable=True)

    #: Yetkazib berish narxi, km uchun. Texnikadagi bilan bir xil qoida.
    delivery_price_per_km = Column(Numeric(12, 2), nullable=True)

    #: Ombor manzili — masofa shu nuqtadan sanaladi
    address = Column(Text, nullable=True)
    latitude = Column(Numeric(10, 7), nullable=True)
    longitude = Column(Numeric(10, 7), nullable=True)

    status = Column(String(20), nullable=False, default=STATUS_PENDING, index=True)
    moderation_comment = Column(Text, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    photos = relationship(
        "MaterialPhoto",
        back_populates="product",
        cascade="all, delete-orphan",
        order_by="MaterialPhoto.id",
    )

    __table_args__ = (
        CheckConstraint("price_per_unit > 0", name="check_material_price"),
        CheckConstraint("unit_weight_kg > 0", name="check_material_unit_weight"),
        CheckConstraint("min_quantity > 0", name="check_material_min_quantity"),
        CheckConstraint(
            "available_quantity IS NULL OR available_quantity >= 0",
            name="check_material_available",
        ),
        CheckConstraint(
            "unit IN ('piece','bag','tonne','m3')", name="check_material_unit"
        ),
        CheckConstraint(
            "status IN ('pending','approved','rejected')",
            name="check_material_product_status",
        ),
    )


class MaterialPhoto(Base):
    __tablename__ = "material_photos"

    id = Column(Integer, primary_key=True, index=True)
    product_id = Column(
        Integer,
        ForeignKey("material_products.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    url = Column(String(500), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    product = relationship("MaterialProduct", back_populates="photos")


class MaterialOrder(Base):
    """
    Material buyurtmasi.

    Hamma summa BUYURTMA BERILGAN PAYTDAGI holicha saqlanadi: sotuvchi
    ertaga narxini oshirsa, kechagi buyurtma o'zgarmasligi kerak. Aks
    holda muzlatilgan pul bilan buyurtmadagi summa bir-biriga to'g'ri
    kelmay qolardi.
    """

    __tablename__ = "material_orders"

    STATUS_PENDING = "pending"        # sotuvchi javobini kutmoqda
    STATUS_CONFIRMED = "confirmed"    # sotuvchi qabul qildi
    STATUS_DELIVERED = "delivered"    # yetkazildi, pul o'tdi
    STATUS_CANCELLED = "cancelled"    # xaridor bekor qildi
    STATUS_REJECTED = "rejected"      # sotuvchi rad etdi

    id = Column(Integer, primary_key=True, index=True)
    buyer_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    seller_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id = Column(
        Integer,
        ForeignKey("material_products.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )

    quantity = Column(Numeric(12, 2), nullable=False)

    # --- buyurtma paytidagi nusxalar ---
    unit = Column(String(10), nullable=False)
    price_per_unit = Column(Numeric(12, 2), nullable=False)
    goods_amount = Column(Numeric(12, 2), nullable=False)

    weight_kg = Column(Numeric(12, 2), nullable=False)
    vehicle_code = Column(String(20), nullable=False)
    trips = Column(Integer, nullable=False, default=1)

    delivery_distance_km = Column(Numeric(10, 2), nullable=True)
    delivery_fee = Column(Numeric(12, 2), nullable=False, default=0)

    #: Platforma ulushi — SOTUVCHIDAN ushlanadi, xaridorning summasiga
    #: qo'shilmaydi. Ijaradagi qoida bilan bir xil.
    commission = Column(Numeric(12, 2), nullable=False, default=0)

    #: Xaridor to'laydigan summa: tovar + yetkazib berish
    total_amount = Column(Numeric(12, 2), nullable=False)
    #: Balansda muzlatilgan summa — buyurtma yopilguncha
    frozen_amount = Column(Numeric(12, 2), nullable=False, default=0)

    delivery_address = Column(Text, nullable=True)
    delivery_latitude = Column(Numeric(10, 7), nullable=True)
    delivery_longitude = Column(Numeric(10, 7), nullable=True)

    comment = Column(Text, nullable=True)
    status = Column(String(20), nullable=False, default=STATUS_PENDING, index=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    __table_args__ = (
        CheckConstraint("quantity > 0", name="check_material_order_quantity"),
        CheckConstraint("total_amount > 0", name="check_material_order_total"),
        CheckConstraint("commission >= 0", name="check_material_order_commission"),
        CheckConstraint("trips > 0", name="check_material_order_trips"),
        CheckConstraint(
            "status IN ('pending','confirmed','delivered','cancelled','rejected')",
            name="check_material_order_status",
        ),
    )
