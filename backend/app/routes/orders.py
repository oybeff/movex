from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime, date
from app.schemas import order as order_schema
from app.models import order as order_model
from app.services import order_service
from app.dependencies import get_db, get_current_user

router = APIRouter()

@router.post("/", response_model=order_schema.OrderRead)
def create_order(order: order_schema.OrderCreate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return order_service.create_order(db, order, current_user.id)

@router.get("/", response_model=list[order_schema.OrderRead])
def get_orders(skip: int = 0, limit: int = 100, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return order_service.get_orders(db, skip, limit)

@router.get("/{order_id}", response_model=order_schema.OrderRead)
def get_order(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    db_order = order_service.get_order(db, order_id)
    if not db_order:
        raise HTTPException(status_code=404, detail="Order not found")
    return db_order

@router.put("/{order_id}", response_model=order_schema.OrderRead)
def update_order(order_id: int, order: order_schema.OrderUpdate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """
    Buyurtma statusini o'zgartirish

    - pending -> confirmed: Egasi tasdiqladi (faqat equipment egasi)
    - pending -> rejected: Egasi rad etdi (faqat equipment egasi)
    - pending -> cancelled: Client bekor qildi (faqat buyurtma egasi)
    - confirmed -> completed: Ish yakunlandi
    """
    return order_service.update_order(db, order_id, order, current_user.id)


@router.delete("/{order_id}", response_model=dict)
def delete_order(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    order_service.delete_order(db, order_id)
    return {"message": "Order deleted successfully"}


@router.get("/statistics/summary", response_model=dict)
def get_order_statistics(
    start_date: Optional[date] = Query(None, description="Boshlanish sanasi (YYYY-MM-DD)"),
    end_date: Optional[date] = Query(None, description="Tugash sanasi (YYYY-MM-DD)"),
    status: Optional[str] = Query(None, description="Buyurtma holati filter"),
    equipment_id: Optional[int] = Query(None, description="Texnika ID filter"),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    """
    Buyurtmalar statistikasini olish (faqat owner uchun)

    Returns:
    - total_orders: Jami buyurtmalar soni
    - total_income: Jami daromad
    - orders_by_status: Status bo'yicha buyurtmalar
    - orders_by_date: Sana bo'yicha buyurtmalar
    - orders_by_equipment: Texnika bo'yicha buyurtmalar
    """
    return order_service.get_order_statistics(
        db=db,
        owner_id=current_user.id,
        start_date=start_date,
        end_date=end_date,
        status=status,
        equipment_id=equipment_id
    )
