"""
Materiallar sxemalari.

Narx bilan bog'liq maydonlar (summa, ulush, yetkazib berish) faqat
JAVOBDA bor. So'rovda ular umuman qabul qilinmaydi: xaridor nima va
qancha kerakligini aytadi, summani server sanaydi. Ilgari shu qoida
buzilgan joyda ekskavator bir oyga 1 000 so'mga ketgan.
"""
from datetime import datetime
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, Field


class MaterialProductCreate(BaseModel):
    material_type: str = Field(max_length=50)
    title: str = Field(min_length=2, max_length=150)
    description: Optional[str] = Field(default=None, max_length=4000)

    #: Ko'rsatilmasa — ma'lumotnomadagi standart birlik
    unit: Optional[str] = Field(default=None, max_length=10)
    #: Ko'rsatilmasa — ma'lumotnomadagi taxminiy og'irlik
    unit_weight_kg: Optional[Decimal] = Field(default=None, gt=0, le=Decimal("100000"))

    price_per_unit: Decimal = Field(gt=0, le=Decimal("10000000000"))
    min_quantity: Optional[Decimal] = Field(default=1, gt=0)
    available_quantity: Optional[Decimal] = Field(default=None, ge=0)
    delivery_price_per_km: Optional[Decimal] = Field(default=None, ge=0)

    address: Optional[str] = Field(default=None, max_length=500)
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)

    photos: Optional[List[str]] = None


class MaterialProductUpdate(BaseModel):
    title: Optional[str] = Field(default=None, min_length=2, max_length=150)
    description: Optional[str] = Field(default=None, max_length=4000)
    unit_weight_kg: Optional[Decimal] = Field(default=None, gt=0)
    price_per_unit: Optional[Decimal] = Field(default=None, gt=0)
    min_quantity: Optional[Decimal] = Field(default=None, gt=0)
    available_quantity: Optional[Decimal] = Field(default=None, ge=0)
    delivery_price_per_km: Optional[Decimal] = Field(default=None, ge=0)
    address: Optional[str] = Field(default=None, max_length=500)
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)


class MaterialPhotoRead(BaseModel):
    id: int
    url: str

    class Config:
        from_attributes = True


class MaterialProductRead(BaseModel):
    id: int
    owner_id: int
    material_type: str
    title: str
    description: Optional[str] = None

    unit: str
    unit_weight_kg: Decimal
    price_per_unit: Decimal
    min_quantity: Decimal
    available_quantity: Optional[Decimal] = None
    delivery_price_per_km: Optional[Decimal] = None

    address: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None

    status: str
    moderation_comment: Optional[str] = None
    created_at: datetime

    photos: List[MaterialPhotoRead] = []

    #: Qo'lda to'ldiriladi
    owner_name: Optional[str] = None
    distance_km: Optional[float] = None

    class Config:
        from_attributes = True


class MaterialQuoteRequest(BaseModel):
    """
    Ekrandagi jonli hisob. Buyurtma yaratilmaydi.

    Summa bu yerda ham SERVERDA sanaladi: ilova o'zi hisoblab, keyin
    natijani yuborsa, ikki xil formula paydo bo'lardi.
    """

    product_id: int
    quantity: Decimal = Field(gt=0)
    delivery_latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    delivery_longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    #: Foydalanuvchi mashinani o'zgartirgan bo'lsa
    vehicle_code: Optional[str] = Field(default=None, max_length=20)


class MaterialQuoteRead(BaseModel):
    quantity: Decimal
    unit: str
    price_per_unit: Decimal
    goods_amount: Decimal

    weight_kg: Decimal
    vehicle_code: str
    vehicle_capacity_kg: int
    trips: int

    delivery_distance_km: Optional[Decimal] = None
    delivery_fee: Decimal

    #: Xaridor to'laydigan summa: tovar + yetkazib berish.
    #: Ulush bu summaga KIRMAYDI — uni sotuvchi to'laydi.
    total: Decimal


class MaterialOrderCreate(BaseModel):
    product_id: int
    quantity: Decimal = Field(gt=0)

    delivery_address: Optional[str] = Field(default=None, max_length=500)
    delivery_latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    delivery_longitude: Optional[float] = Field(default=None, ge=-180, le=180)

    vehicle_code: Optional[str] = Field(default=None, max_length=20)
    comment: Optional[str] = Field(default=None, max_length=1000)


class MaterialOrderRead(BaseModel):
    id: int
    buyer_id: int
    seller_id: int
    product_id: int

    quantity: Decimal
    unit: str
    price_per_unit: Decimal
    goods_amount: Decimal

    weight_kg: Decimal
    vehicle_code: str
    trips: int

    delivery_distance_km: Optional[Decimal] = None
    delivery_fee: Decimal
    commission: Decimal
    total_amount: Decimal

    delivery_address: Optional[str] = None
    comment: Optional[str] = None
    status: str
    created_at: datetime

    #: Qo'lda to'ldiriladi
    product_title: Optional[str] = None
    material_type: Optional[str] = None
    buyer_name: Optional[str] = None
    seller_name: Optional[str] = None

    class Config:
        from_attributes = True


class MaterialTypeRead(BaseModel):
    """Ma'lumotnoma satri — ilova ro'yxatni shundan quradi."""

    code: str
    default_unit: str
    default_unit_weight_kg: Decimal


class DeliveryVehicleRead(BaseModel):
    code: str
    capacity_kg: int


class MaterialModerate(BaseModel):
    approve: bool
    comment: Optional[str] = Field(default=None, max_length=500)
