from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.schemas import payment as payment_schema
from app.services import payment_service
from app.dependencies import get_db, get_current_user
from app.core.access import assert_order_access
from app.core.roles import role_checker
from app.models.order import Order

router = APIRouter()


def _assert_payment_access(db: Session, payment, current_user):
    """To'lov buyurtmaga bog'langan — ishtirokchilar o'shalar."""
    order = db.query(Order).filter(Order.id == payment.order_id).first()
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found")
    assert_order_access(db, order, current_user)


# Создание платежа
@router.post("/", response_model=payment_schema.PaymentRead)
def create_payment(
    payment: payment_schema.PaymentCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    """To'lov yozuvi faqat o'zi ishtirok etayotgan buyurtma uchun."""
    order = db.query(Order).filter(Order.id == payment.order_id).first()
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found")
    assert_order_access(db, order, current_user)
    return payment_service.create_payment(db, payment, current_user.id)


# Получение списка платежей
@router.get("/", response_model=list[payment_schema.PaymentRead])
def get_payments(
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Faqat o'ziga tegishli to'lovlar."""
    return payment_service.get_payments(db, skip, limit, current_user)


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
    _assert_payment_access(db, db_payment, current_user)
    return db_payment


# Обновление платежа
@router.put("/{payment_id}", response_model=payment_schema.PaymentRead)
def update_payment(
    payment_id: int,
    payment: payment_schema.PaymentUpdate,
    db: Session = Depends(get_db),
    current_user=Depends(role_checker(["admin"]))
):
    """To'lov yozuvini o'zgartirish — faqat admin: bu moliyaviy hujjat."""
    db_payment = payment_service.get_payment(db, payment_id)
    if not db_payment:
        raise HTTPException(status_code=404, detail="Payment not found")
    return payment_service.update_payment(db, payment_id, payment)


# Удаление платежа
@router.delete("/{payment_id}", response_model=dict)
def delete_payment(
    payment_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(role_checker(["admin"]))
):
    """To'lov yozuvini o'chirish — faqat admin."""
    if payment_service.delete_payment(db, payment_id) is None:
        raise HTTPException(status_code=404, detail="Payment not found")
    return {"message": "Payment deleted successfully"}
