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
    amount: float
    status: str
    card_masked: str
    card_holder: Optional[str] = None
    comment: Optional[str] = None
    admin_comment: Optional[str] = None
    processed_at: Optional[datetime] = None
    created_at: datetime

    class Config:
        from_attributes = True


class PayoutRequestResolve(BaseModel):
    """Admin arizani hal qiladi."""

    admin_comment: Optional[str] = Field(None, max_length=500)
