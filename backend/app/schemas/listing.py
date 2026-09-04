"""
E'lon sxemalari.

Telefon raqami ataylab ixtiyoriy va javobda har doim ham qaytmaydi: uni
faqat e'lon egasi va uni olgan ega ko'radi. Aks holda taxta raqamlarni
yig'ish uchun ochiq manba bo'lardi.
"""
from datetime import date, datetime
from decimal import Decimal
from typing import List, Optional

from pydantic import BaseModel, Field


class ListingCreate(BaseModel):
    title: str = Field(min_length=2, max_length=120)
    description: Optional[str] = Field(default=None, max_length=4000)

    #: Ixtiyoriy. Ko'rsatilsa — ro'yxatda ikonka va filtr ishlaydi.
    equipment_type: Optional[str] = Field(default=None, max_length=50)

    budget: Optional[Decimal] = Field(default=None, gt=0, le=Decimal("10000000000"))

    address: Optional[str] = Field(default=None, max_length=500)
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)

    needed_from: Optional[date] = None
    needed_to: Optional[date] = None

    #: Ko'rsatilmasa — profildagi raqam ishlatiladi
    contact_phone: Optional[str] = Field(default=None, max_length=20)

    photos: Optional[List[str]] = None


class ListingPhotoRead(BaseModel):
    id: int
    url: str

    class Config:
        from_attributes = True


class ListingRead(BaseModel):
    id: int
    client_id: int
    title: str
    description: Optional[str] = None
    equipment_type: Optional[str] = None
    budget: Optional[Decimal] = None

    address: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None

    needed_from: Optional[date] = None
    needed_to: Optional[date] = None

    status: str
    taken_by: Optional[int] = None
    taken_at: Optional[datetime] = None
    confirmed_at: Optional[datetime] = None
    views_count: int = 0
    expires_at: Optional[datetime] = None
    created_at: datetime

    photos: List[ListingPhotoRead] = []

    # Quyidagilar qo'lda to'ldiriladi
    client_name: Optional[str] = None
    taker_name: Optional[str] = None

    #: Faqat ishtirokchilarga qaytadi, boshqalarga None
    contact_phone: Optional[str] = None

    #: Ko'ruvchiga nisbatan: shu e'lonni u olganmi
    taken_by_me: bool = False

    #: Ko'ruvchi masofasi, km (qidiruv nuqtasi sozlangan bo'lsa)
    distance_km: Optional[float] = None

    # --- sanoqlar. Bazada ustun sifatida saqlanmaydi, so'rovda sanaladi ---
    likes_count: int = 0
    saves_count: int = 0
    offers_count: int = 0

    # --- ko'ruvchiga nisbatan ---
    liked_by_me: bool = False
    saved_by_me: bool = False
    #: Shu e'longa allaqachon narx taklif qilganmi
    offered_by_me: bool = False

    class Config:
        from_attributes = True


class ListingOfferCreate(BaseModel):
    """Ijrochi o'z narxini aytadi."""

    price: Decimal = Field(gt=0, le=Decimal("10000000000"))
    comment: Optional[str] = Field(default=None, max_length=1000)


class ListingOfferRead(BaseModel):
    id: int
    listing_id: int
    user_id: int
    price: Decimal
    comment: Optional[str] = None
    status: str
    created_at: datetime

    #: Qo'lda to'ldiriladi — kim taklif qilgani ro'yxatda ko'rinishi uchun
    user_name: Optional[str] = None

    #: Faqat MUALLIF va qabul qilingan ijrochi ko'radi. Aks holda taxta
    #: raqam yig'ish uchun ochiq manbaga aylanardi.
    user_phone: Optional[str] = None

    class Config:
        from_attributes = True
