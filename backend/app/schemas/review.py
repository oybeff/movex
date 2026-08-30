from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class ReviewBase(BaseModel):
    equipment_id: Optional[int] = None
    rating: int = Field(ge=1, le=5, description="Baho 1 dan 5 gacha")
    comment: Optional[str] = Field(None, max_length=1000)


class ReviewCreate(ReviewBase):
    """
    Sharh yaratish uchun.

    user_id ATAYLAB yo'q: ilgari u so'rov tanasidan kelardi va boshqa
    odamning nomidan sharh qoldirish mumkin edi. Endi u tokendan olinadi.
    """
    pass


class ReviewUpdate(BaseModel):
    rating: Optional[int] = Field(None, ge=1, le=5)
    comment: Optional[str] = Field(None, max_length=1000)


class ReviewRead(ReviewBase):
    id: int
    user_id: int
    created_at: datetime

    class Config:
        from_attributes = True
