from pydantic import BaseModel, Field
from typing import Optional
from datetime import date, datetime

class OrderBase(BaseModel):
    equipment_id: int
    start_date: date
    end_date: date
    total_amount: float = Field(gt=0, description="Total amount must be positive")
    commission: float = Field(ge=0, description="Commission must be non-negative")
    delivery_latitude: str = Field(..., description="Delivery location latitude")
    delivery_longitude: str = Field(..., description="Delivery location longitude")
    delivery_address: Optional[str] = Field(None, description="Delivery address (optional)")
    delivery_distance: Optional[float] = Field(None, ge=0, description="Delivery distance in km")
    delivery_fee: Optional[float] = Field(None, ge=0, description="Delivery fee")

class OrderCreate(OrderBase):
    """Order yaratish uchun schema (user_id token dan olinadi)"""
    pass

class OrderPriceRequest(BaseModel):
    """
    Narxni oldindan hisoblash uchun. Summalar bu yerda YO'Q — ularni
    server o'zi hisoblaydi, mijozdan qabul qilmaydi.
    """
    equipment_id: int
    start_date: date
    end_date: date
    delivery_latitude: Optional[str] = None
    delivery_longitude: Optional[str] = None


class OrderPricePreview(BaseModel):
    """Ilova ekranda aynan shu raqamlarni ko'rsatadi."""
    days: int
    subtotal: float          # ijara narxi
    commission: float        # platforma ulushi
    delivery_distance: Optional[float] = None  # km
    delivery_fee: float
    total: float


class OrderUpdate(BaseModel):
    """Order yangilash uchun schema (faqat status o'zgartiriladi)"""
    status: Optional[str] = Field(None, description="Order status: pending, confirmed, rejected, cancelled, completed")

class OrderRead(BaseModel):
    id: int
    user_id: int
    equipment_id: int
    start_date: date
    end_date: date
    status: str
    total_amount: float
    commission: float
    frozen_amount: float
    delivery_latitude: str
    delivery_longitude: str
    delivery_address: Optional[str]
    delivery_distance: Optional[float]
    delivery_fee: Optional[float]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
