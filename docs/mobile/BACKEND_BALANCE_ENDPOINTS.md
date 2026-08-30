# Backend: Hisob to'ldirish uchun kerakli endpoint'lar

## 1. Database Model (SQLAlchemy)

### Balance Table
```python
# models/balance.py
from sqlalchemy import Column, Integer, Float, DateTime, ForeignKey
from sqlalchemy.sql import func
from database import Base

class Balance(Base):
    __tablename__ = "balances"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True, nullable=False)
    balance = Column(Float, default=0.0, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
```

### BalanceTransaction Table
```python
# models/balance_transaction.py
from sqlalchemy import Column, Integer, Float, String, DateTime, ForeignKey
from sqlalchemy.sql import func
from database import Base

class BalanceTransaction(Base):
    __tablename__ = "balance_transactions"
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    amount = Column(Float, nullable=False)
    type = Column(String(20), nullable=False)  # 'topup' or 'payment'
    status = Column(String(20), nullable=False)  # 'pending', 'completed', 'failed'
    payment_method = Column(String(50), nullable=True)  # 'click', 'payme', etc.
    description = Column(String(500), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
```

## 2. Pydantic Schemas

```python
# schemas/balance.py
from pydantic import BaseModel
from datetime import datetime
from typing import Optional

class BalanceRead(BaseModel):
    id: int
    user_id: int
    balance: float
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True

class BalanceTransactionCreate(BaseModel):
    amount: float
    payment_method: str

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
```

## 3. API Endpoints

### Router: `/balance`

```python
# routers/balance.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from database import get_db
from models.balance import Balance
from models.balance_transaction import BalanceTransaction
from schemas.balance import BalanceRead, BalanceTransactionCreate, BalanceTransactionRead
from dependencies import get_current_user

router = APIRouter(prefix="/balance", tags=["Balance"])

@router.get("/me", response_model=BalanceRead)
async def get_my_balance(
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Joriy foydalanuvchi balansini olish"""
    balance = db.query(Balance).filter(Balance.user_id == current_user.id).first()
    
    if not balance:
        # Agar balans yo'q bo'lsa, yangi yaratish
        balance = Balance(user_id=current_user.id, balance=0.0)
        db.add(balance)
        db.commit()
        db.refresh(balance)
    
    return balance

@router.post("/topup", response_model=BalanceTransactionRead)
async def top_up_balance(
    transaction_data: BalanceTransactionCreate,
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Hisob to'ldirish (vaqtinchalik - to'g'ridan-to'g'ri qabul qilish)
    
    Haqiqiy integratsiyada:
    1. Click/Payme API'ga so'rov yuborish
    2. To'lov URL'ini qaytarish
    3. Callback orqali to'lov holatini yangilash
    """
    
    # Validatsiya
    if transaction_data.amount < 10000 or transaction_data.amount > 10000000:
        raise HTTPException(status_code=400, detail="Invalid amount")
    
    # Tranzaksiya yaratish
    transaction = BalanceTransaction(
        user_id=current_user.id,
        amount=transaction_data.amount,
        type="topup",
        status="pending",  # Haqiqiy integratsiyada 'pending' bo'ladi
        payment_method=transaction_data.payment_method,
        description=f"Hisob to'ldirish - {transaction_data.payment_method}"
    )
    db.add(transaction)
    db.commit()
    
    # VAQTINCHALIK: To'g'ridan-to'g'ri 'completed' qilish
    # Haqiqiy integratsiyada bu callback orqali bo'ladi
    transaction.status = "completed"
    
    # Balansni yangilash
    balance = db.query(Balance).filter(Balance.user_id == current_user.id).first()
    if not balance:
        balance = Balance(user_id=current_user.id, balance=0.0)
        db.add(balance)
    
    balance.balance += transaction_data.amount
    db.commit()
    db.refresh(transaction)
    
    return transaction

@router.get("/transactions", response_model=List[BalanceTransactionRead])
async def get_transaction_history(
    skip: int = 0,
    limit: int = 100,
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Hisob to'ldirish tarixini olish"""
    transactions = db.query(BalanceTransaction)\
        .filter(BalanceTransaction.user_id == current_user.id)\
        .order_by(BalanceTransaction.created_at.desc())\
        .offset(skip)\
        .limit(limit)\
        .all()
    
    return transactions

@router.get("/transactions/{transaction_id}", response_model=BalanceTransactionRead)
async def get_transaction(
    transaction_id: int,
    current_user = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Bitta tranzaksiyani olish"""
    transaction = db.query(BalanceTransaction)\
        .filter(
            BalanceTransaction.id == transaction_id,
            BalanceTransaction.user_id == current_user.id
        )\
        .first()
    
    if not transaction:
        raise HTTPException(status_code=404, detail="Transaction not found")
    
    return transaction
```

## 4. Main app'ga qo'shish

```python
# main.py
from routers import balance

app.include_router(balance.router)
```

## 5. Migration

```bash
# Alembic migration yaratish
alembic revision --autogenerate -m "Add balance and balance_transactions tables"
alembic upgrade head
```

## 6. Click integratsiyasi (keyingi bosqich)

Click bilan integratsiya uchun:
1. Click merchant account yaratish
2. Click API credentials olish
3. `/balance/topup` endpoint'ini o'zgartirish:
   - Click API'ga to'lov so'rovi yuborish
   - To'lov URL'ini qaytarish
4. Click callback endpoint yaratish:
   - `/balance/click/callback` - to'lov holatini yangilash

### Click callback endpoint namunasi:

```python
@router.post("/click/callback")
async def click_callback(
    callback_data: dict,
    db: Session = Depends(get_db)
):
    """
    Click'dan kelgan callback'ni qayta ishlash
    """
    # Click signature'ni tekshirish
    # ...
    
    # Tranzaksiya holatini yangilash
    transaction_id = callback_data.get("merchant_trans_id")
    transaction = db.query(BalanceTransaction).filter(
        BalanceTransaction.id == transaction_id
    ).first()
    
    if not transaction:
        return {"error": -5, "error_note": "Transaction not found"}
    
    if callback_data.get("error") == 0:
        # To'lov muvaffaqiyatli
        transaction.status = "completed"
        
        # Balansni yangilash
        balance = db.query(Balance).filter(
            Balance.user_id == transaction.user_id
        ).first()
        balance.balance += transaction.amount
    else:
        # To'lov muvaffaqiyatsiz
        transaction.status = "failed"
    
    db.commit()
    
    return {"error": 0, "error_note": "Success"}
```

## 7. Test qilish

```bash
# Balansni olish
curl -X GET "http://localhost:8000/balance/me" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Hisob to'ldirish
curl -X POST "http://localhost:8000/balance/topup" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "amount": 100000,
    "payment_method": "click"
  }'

# Tranzaksiyalar tarixini olish
curl -X GET "http://localhost:8000/balance/transactions" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Eslatma

Hozirda `/balance/topup` endpoint'i vaqtinchalik to'g'ridan-to'g'ri to'lovni qabul qiladi va balansni yangilaydi. 
Haqiqiy ishlab chiqarishda Click/Payme integratsiyasi qo'shilishi kerak.

