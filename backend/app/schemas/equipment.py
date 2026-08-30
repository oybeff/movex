# app/schemas/equipment.py
from pydantic import BaseModel, Field, condecimal
from typing import Optional, List
from datetime import datetime

class EquipmentPhotoRead(BaseModel):
    id: int
    url: str
    is_primary: bool
    created_at: datetime

    class Config:
        from_attributes = True

class EquipmentBase(BaseModel):
    type: str = Field(..., max_length=50)
    model: str = Field(..., max_length=100)
    year: Optional[int] = None
    power_hp: Optional[int] = None

    price_per_hour: Optional[condecimal(max_digits=10, decimal_places=2)] = None
    price_per_shift: Optional[condecimal(max_digits=10, decimal_places=2)] = None
    price_per_day: condecimal(max_digits=10, decimal_places=2)
    delivery_price_per_km: Optional[condecimal(max_digits=10, decimal_places=2)] = None

    address: Optional[str] = None
    latitude: Optional[condecimal(max_digits=9, decimal_places=6)] = None
    longitude: Optional[condecimal(max_digits=9, decimal_places=6)] = None

    payload_kg: Optional[int] = None
    dimensions: Optional[str] = None
    description: Optional[str] = None

    status: Optional[str] = Field(default="available")  # available | busy | maintenance
    available: Optional[bool] = True

    company_id: Optional[int] = None  # если техника принадлежит компании

class EquipmentCreate(EquipmentBase):
    pass

class EquipmentUpdate(BaseModel):
    type: Optional[str] = None
    model: Optional[str] = None
    year: Optional[int] = None
    power_hp: Optional[int] = None

    price_per_hour: Optional[condecimal(max_digits=10, decimal_places=2)] = None
    price_per_shift: Optional[condecimal(max_digits=10, decimal_places=2)] = None
    price_per_day: Optional[condecimal(max_digits=10, decimal_places=2)] = None
    delivery_price_per_km: Optional[condecimal(max_digits=10, decimal_places=2)] = None

    address: Optional[str] = None
    latitude: Optional[condecimal(max_digits=9, decimal_places=6)] = None
    longitude: Optional[condecimal(max_digits=9, decimal_places=6)] = None

    payload_kg: Optional[int] = None
    dimensions: Optional[str] = None
    description: Optional[str] = None

    status: Optional[str] = None
    available: Optional[bool] = None
    company_id: Optional[int] = None

class EquipmentRead(EquipmentBase):
    id: int
    owner_id: int
    created_at: datetime
    updated_at: datetime
    photos: List[EquipmentPhotoRead] = []

    class Config:
        from_attributes = True
