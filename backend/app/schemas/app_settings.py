from pydantic import BaseModel
from typing import Optional, Any, List
from datetime import datetime

class AppSettingsBase(BaseModel):
    key: str
    value: Optional[Any] = None
    description: Optional[str] = None

class AppSettingsCreate(AppSettingsBase):
    pass

class AppSettingsUpdate(BaseModel):
    value: Optional[Any] = None
    description: Optional[str] = None

class AppSettingsRead(AppSettingsBase):
    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ContactMethodBase(BaseModel):
    type: str  # phone, email, telegram, whatsapp, website, sms
    label: str
    value: str
    icon: Optional[str] = None
    order: int = 0
    is_active: int = 1

class ContactMethodCreate(ContactMethodBase):
    pass

class ContactMethodUpdate(BaseModel):
    type: Optional[str] = None
    label: Optional[str] = None
    value: Optional[str] = None
    icon: Optional[str] = None
    order: Optional[int] = None
    is_active: Optional[int] = None

class ContactMethodRead(ContactMethodBase):
    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class TermsAndPrivacyResponse(BaseModel):
    terms_uz: Optional[str] = None
    terms_ru: Optional[str] = None
    privacy_uz: Optional[str] = None
    privacy_ru: Optional[str] = None


class ContactMethodsResponse(BaseModel):
    methods: List[ContactMethodRead]

