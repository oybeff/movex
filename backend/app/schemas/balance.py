from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

# Balance Schemas
class BalanceBase(BaseModel):
    user_id: int
    balance: float = Field(ge=0, description="Balance must be non-negative")

class BalanceCreate(BaseModel):
    user_id: int

class BalanceUpdate(BaseModel):
    balance: Optional[float] = Field(None, ge=0)

class BalanceRead(BaseModel):
    id: int
    user_id: int
    balance: float
    frozen_balance: float
    #: Sovg'aning ishlatilmagan qismi. Ilova ichida ishlatiladi, kartaga
    #: yechilmaydi — shuning uchun ilovaga ham ayta olishimiz kerak, aks
    #: holda u yechish ekranida yechib bo'lmaydigan pulni ko'rsatardi.
    bonus_balance: float = 0
    created_at: datetime
    updated_at: Optional[datetime] = None

    @property
    def available_balance(self) -> float:
        """Mavjud balans (muzlatilmagan)"""
        return self.balance - self.frozen_balance

    class Config:
        from_attributes = True


# Balance Transaction Schemas
class BalanceTransactionBase(BaseModel):
    amount: float = Field(gt=0, description="Amount must be positive")
    payment_method: str = Field(..., description="Payment method (click, payme, etc.)")

class BalanceTransactionCreate(BalanceTransactionBase):
    phone_number: Optional[str] = Field(None, description="Phone number for Click payment")

class BalanceTransactionUpdate(BaseModel):
    status: Optional[str] = None
    description: Optional[str] = None

class BalanceTransactionRead(BaseModel):
    id: int
    user_id: int
    amount: float
    type: str
    status: str
    payment_method: Optional[str] = None
    description: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


# Click to'lov uchun response schema
class BalanceTopUpResponse(BaseModel):
    """Hisob to'ldirish response - Click URL bilan"""
    transaction_id: int
    amount: float
    payment_method: str
    status: str
    payment_url: Optional[str] = None  # Click to'lov URL'i

    class Config:
        from_attributes = True

