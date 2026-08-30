"""
Zayavka va takliflarning sxemalari.

Pul maydonlari haqida. budget va price_per_day — bu MO'LJAL, hisob emas.
Buyurtmaning haqiqiy summasi serverda pricing_service tomonidan
hisoblanadi, shuning uchun bu yerda total_amount yoki commission degan
maydon yo'q va bo'lmasligi ham kerak: mijoz yuborgan summaga ishonish
aynan tuzatilgan xato.
"""
from datetime import date, datetime
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, Field


class RequestCreate(BaseModel):
    equipment_type: str = Field(min_length=1, max_length=50)
    start_date: date
    end_date: date

    delivery_latitude: float = Field(ge=-90, le=90)
    delivery_longitude: float = Field(ge=-180, le=180)
    delivery_address: Optional[str] = Field(default=None, max_length=500)

    #: Mijozning mo'ljali. Ko'rsatilmasa — "narxni o'zingiz ayting".
    budget: Optional[Decimal] = Field(default=None, gt=0, le=Decimal("10000000000"))
    comment: Optional[str] = Field(default=None, max_length=1000)


class OfferCreate(BaseModel):
    equipment_id: int
    price_per_day: Decimal = Field(gt=0, le=Decimal("1000000000"))
    comment: Optional[str] = Field(default=None, max_length=1000)


class OfferRead(BaseModel):
    id: int
    request_id: int
    owner_id: int
    equipment_id: int
    price_per_day: Decimal
    comment: Optional[str] = None
    status: str
    created_at: datetime

    # Ilova har bir taklif yonida texnikani ko'rsatadi, alohida so'rovsiz
    equipment_type: Optional[str] = None
    equipment_model: Optional[str] = None
    owner_name: Optional[str] = None

    #: Kunlik narx * kunlar. Komissiya va yetkazib berish bunga KIRMAYDI —
    #: to'liq summa buyurtma yaratilganda hisoblanadi.
    estimated_subtotal: Optional[Decimal] = None

    class Config:
        from_attributes = True


class RequestRead(BaseModel):
    id: int
    client_id: int
    equipment_type: str
    start_date: date
    end_date: date

    delivery_latitude: str
    delivery_longitude: str
    delivery_address: Optional[str] = None

    budget: Optional[Decimal] = None
    comment: Optional[str] = None
    status: str

    selected_offer_id: Optional[int] = None
    order_id: Optional[int] = None
    expires_at: Optional[datetime] = None
    created_at: datetime

    #: Ro'yxatda "3 ta taklif" deb ko'rsatish uchun
    offers_count: int = 0
    #: Egaga: zayavka nuqtasigacha masofa, km
    distance_km: Optional[float] = None

    class Config:
        from_attributes = True


class RequestWithOffers(RequestRead):
    offers: List[OfferRead] = []


class AcceptOfferResult(BaseModel):
    request: RequestRead
    order_id: int


class SearchAreaUpdate(BaseModel):
    """Qidiruv va xabarnoma radiusi."""

    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    radius_km: int = Field(ge=1, le=1000)


class SearchAreaRead(BaseModel):
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    radius_km: int
