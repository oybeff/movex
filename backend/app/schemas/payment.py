from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class PaymentBase(BaseModel):
    order_id: int
    amount: float
    commission: float
    payment_method: Optional[str]
    status: str
    paid_at: Optional[datetime]

class PaymentCreate(PaymentBase):
    pass

class PaymentUpdate(BaseModel):
    amount: Optional[float]
    commission: Optional[float]
    payment_method: Optional[str]
    status: Optional[str]
    paid_at: Optional[datetime]

class PaymentRead(PaymentBase):
    id: int

    class Config:
        from_attributes = True
