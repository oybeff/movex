from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator


class PayoutRequestCreate(BaseModel):
    """Texnika egasi pul yechish arizasini beradi."""

    amount: float = Field(gt=0, description="Yechib olinadigan summa, so'mda")
    card_number: str = Field(min_length=16, max_length=32, description="Karta raqami")
    card_holder: Optional[str] = Field(None, max_length=100)
    comment: Optional[str] = Field(None, max_length=500)

    @field_validator("card_number")
    @classmethod
    def only_digits(cls, value: str) -> str:
        digits = "".join(ch for ch in value if ch.isdigit())
        if len(digits) != 16:
            raise ValueError("Karta raqami 16 ta raqamdan iborat bo'lishi kerak")
        return digits


class PayoutRequestRead(BaseModel):
    """
    Egasiga va adminga qaytariladigan ko'rinish.
    Karta raqami HECH QACHON to'liq qaytarilmaydi.
    """

    id: int
    user_id: int

    # amount — so'ralgan summa, balansdan shu yechiladi.
    # commission — platforma ulushi, payout_amount — kartaga tushadigan qismi.
    amount: float
    commission: float = 0
    payout_amount: float
    status: str
    card_masked: str
    card_holder: Optional[str] = None
    comment: Optional[str] = None
    admin_comment: Optional[str] = None

    # Shlyuzdagi o'tkazma holati. Bizning `status` dan alohida: 'progress'
    # va 'draft' ikkalasi ham bizda 'pending' ga tushadi, lekin adminda
    # farqi ko'rinishi kerak — biri yo'lda, ikkinchisi hali yo'lga
    # chiqmagan.
    rahmat_status: Optional[str] = None
    rahmat_receipt_url: Optional[str] = None
    #: Oxirgi xato. Ariza 'pending' da qoladi, sabab ko'rinib turishi kerak.
    rahmat_error: Optional[str] = None

    processed_at: Optional[datetime] = None
    created_at: datetime

    class Config:
        from_attributes = True


class PayoutRequestResolve(BaseModel):
    """Admin arizani hal qiladi."""

    admin_comment: Optional[str] = Field(None, max_length=500)
    #: FAQAT ichki (adminka) manzillari uchun: amalni kim bajargani.
    #: Ochiq manzillarda e'tiborsiz qoldiriladi — u yerda admin tokendan
    #: aniqlanadi, aks holda har kim boshqa admin nomidan ish qilardi.
    admin_id: Optional[int] = None


class PayoutSettingsRead(BaseModel):
    """
    Pul yechish shartlari — ilova ularni ariza berishdan OLDIN ko'rsatadi.

    Ilova o'zi hisoblab qo'ya olmaydi: foiz adminkadan o'zgaradi, va
    yig'ilgan ilovada eski qiymat qotib qolardi — ekranda bir summa,
    balansdan boshqasi.
    """

    mode: str                  # fixed yoki percent
    fixed: float               # qat'iy ushlanma, so'm
    percent: float             # ushlanma foizi
    min_amount: float          # eng kam yechish summasi
