from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class NotificationRead(BaseModel):
    id: int
    type: str
    title: str
    body: Optional[str] = None
    order_id: Optional[int] = None
    # Ilova shu kod bo'yicha texnika ikonkasini ko'rsatadi
    equipment_type: Optional[str] = None
    is_read: bool
    created_at: datetime

    class Config:
        from_attributes = True


class UnreadCount(BaseModel):
    unread: int


class DeviceTokenCreate(BaseModel):
    token: str = Field(min_length=8, max_length=255)
    platform: str = Field(pattern="^(android|ios|web)$")


class DeviceTokenRead(BaseModel):
    id: int
    platform: str
    created_at: datetime

    class Config:
        from_attributes = True
