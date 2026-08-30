from sqlalchemy import select
from sqlalchemy.orm import Session
from app.models.equipment import Equipment
from app.models.order import Order
from app.models.payment import Payment
from app.schemas.payment import PaymentCreate, PaymentUpdate


def create_payment(db: Session, payment: PaymentCreate, user_id: int):
    """Yangi to'lov yaratish"""
    payment_data = payment.dict()
    db_payment = Payment(**payment_data)
    db.add(db_payment)
    db.commit()
    db.refresh(db_payment)
    return db_payment


def get_payment(db: Session, payment_id: int):
    """Bitta to'lovni olish"""
    return db.query(Payment).filter(Payment.id == payment_id).first()


def get_payments(db: Session, skip: int = 0, limit: int = 100, current_user=None):
    """
    Foydalanuvchiga tegishli to'lovlar: o'z buyurtmalari va o'z texnikasiga
    kelgan buyurtmalar bo'yicha. Admin uchun — hammasi.

    Ilgari bu yerda tizimdagi barcha to'lovlar summalari bilan qaytarilardi.
    """
    query = db.query(Payment)

    if current_user is not None and getattr(current_user, "role", None) != "admin":
        own_equipment = (
            db.query(Equipment.id)
            .filter(Equipment.owner_id == current_user.id)
            .subquery()
        )
        visible_orders = (
            db.query(Order.id)
            .filter(
                (Order.user_id == current_user.id)
                | (Order.equipment_id.in_(select(own_equipment.c.id)))
            )
            .subquery()
        )
        query = query.filter(Payment.order_id.in_(select(visible_orders.c.id)))

    return query.order_by(Payment.id.desc()).offset(skip).limit(limit).all()


def update_payment(db: Session, payment_id: int, payment: PaymentUpdate):
    """To'lovni yangilash"""
    db_payment = db.query(Payment).filter(Payment.id == payment_id).first()
    if not db_payment:
        return None
    for key, value in payment.dict(exclude_unset=True).items():
        setattr(db_payment, key, value)
    db.commit()
    db.refresh(db_payment)
    return db_payment


def delete_payment(db: Session, payment_id: int):
    """To'lovni o'chirish"""
    db_payment = db.query(Payment).filter(Payment.id == payment_id).first()
    if db_payment:
        db.delete(db_payment)
        db.commit()
    return db_payment
