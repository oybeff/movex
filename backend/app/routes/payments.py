from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.schemas import payment as payment_schema
from app.services import payment_service
from app.dependencies import get_db, get_current_user

router = APIRouter()

# Создание платежа
@router.post("/", response_model=payment_schema.PaymentRead)
def create_payment(
    payment: payment_schema.PaymentCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    return payment_service.create_payment(db, payment, current_user.id)

# Получение списка платежей
@router.get("/", response_model=list[payment_schema.PaymentRead])
def get_payments(
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    return payment_service.get_payments(db, skip, limit)

# Получение конкретного платежа по id
@router.get("/{payment_id}", response_model=payment_schema.PaymentRead)
def get_payment(
    payment_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    db_payment = payment_service.get_payment(db, payment_id)
    if not db_payment:
        raise HTTPException(status_code=404, detail="Payment not found")
    return db_payment

# Обновление платежа
@router.put("/{payment_id}", response_model=payment_schema.PaymentRead)
def update_payment(
    payment_id: int,
    payment: payment_schema.PaymentUpdate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    return payment_service.update_payment(db, payment_id, payment)

# Удаление платежа
@router.delete("/{payment_id}", response_model=dict)
def delete_payment(
    payment_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    payment_service.delete_payment(db, payment_id)
    return {"message": "Payment deleted successfully"}
