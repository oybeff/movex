from pydantic import BaseModel, EmailStr, Field
from typing import Optional
from datetime import datetime

class UserBase(BaseModel):
    full_name: str
    email: Optional[EmailStr] = None  # Optional (not used)
    phone: str  # Required
    role: str

class UserCreate(UserBase):
    password: str = "dummy"  # Optional, backend generates random password

class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None

    # Interfeys tili. Ilova til almashtirilganda yuboradi — shundan keyin
    # xabarnomalar va push shu tilda keladi.
    language: Optional[str] = Field(default=None, pattern="^(uz|ru)$")

class UserRead(UserBase):
    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
