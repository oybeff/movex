"""
Ma'lumotga kirish huquqini tekshirish.

Ilgari bu tekshiruvlar umuman yo'q edi: har qanday tizimga kirgan
foydalanuvchi begona buyurtmalarni ko'rar va o'chirar, begona yozishmalarni
o'qir, hatto boshqa foydalanuvchining telefon raqamini o'zgartira olardi.

Qoida bitta joyda turadi, chunki uni har bir endpointda takrorlash — aynan
shu xatolarga olib keladi.
"""
from typing import Iterable, Optional, Set

from sqlalchemy import select

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.models.chat import Chat
from app.models.equipment import Equipment
from app.models.order import Order

FORBIDDEN = "Bu ma'lumotga kirish huquqingiz yo'q"


def is_admin(user) -> bool:
    return getattr(user, "role", None) == "admin"


def order_participant_ids(db: Session, order: Order) -> Set[int]:
    """Buyurtma ishtirokchilari: mijoz va texnika egasi."""
    participants = {order.user_id}
    equipment = db.query(Equipment).filter(Equipment.id == order.equipment_id).first()
    if equipment is not None:
        participants.add(equipment.owner_id)
    return participants


def assert_order_access(db: Session, order: Order, user) -> None:
    if is_admin(user):
        return
    if user.id not in order_participant_ids(db, order):
        raise HTTPException(status_code=403, detail=FORBIDDEN)


def chat_participant_ids(db: Session, chat: Chat) -> Set[int]:
    """Chat buyurtmaga bog'langan, demak ishtirokchilar ham o'shalar."""
    order = db.query(Order).filter(Order.id == chat.order_id).first()
    if order is None:
        return set()
    return order_participant_ids(db, order)


def assert_chat_access(db: Session, chat: Chat, user) -> None:
    if is_admin(user):
        return
    if user.id not in chat_participant_ids(db, chat):
        raise HTTPException(status_code=403, detail=FORBIDDEN)


def assert_self_or_admin(user, target_user_id: int) -> None:
    """O'z profili yoki admin. Tahrirlash uchun shu tekshiruv."""
    if is_admin(user):
        return
    if user.id != target_user_id:
        raise HTTPException(status_code=403, detail=FORBIDDEN)


def share_an_order(db: Session, user_id: int, other_user_id: int) -> bool:
    """
    Ikki foydalanuvchi bitta buyurtma bo'yicha uchrashganmi: biri mijoz,
    ikkinchisi texnika egasi.
    """
    if user_id == other_user_id:
        return True

    a_equipment = db.query(Equipment.id).filter(Equipment.owner_id == user_id).subquery()
    b_equipment = db.query(Equipment.id).filter(Equipment.owner_id == other_user_id).subquery()

    exists = (
        db.query(Order.id)
        .filter(
            ((Order.user_id == user_id) & (Order.equipment_id.in_(select(b_equipment.c.id))))
            | ((Order.user_id == other_user_id) & (Order.equipment_id.in_(select(a_equipment.c.id))))
        )
        .first()
    )
    return exists is not None


def assert_can_view_user(db: Session, user, target_user_id: int) -> None:
    """
    Boshqa foydalanuvchining profilini ko'rish.

    Ruxsat beriladi: o'zi, admin, yoki bitta buyurtma bo'yicha kontragent —
    mijoz va texnika egasi bir-birining ismi va telefonini ko'rishi kerak,
    aks holda ular bog'lana olmaydi.

    Ilgari bu yerda tekshiruv umuman yo'q edi: istalgan foydalanuvchi
    bazadagi har kimning telefon raqamini olishi mumkin edi.
    """
    if is_admin(user) or user.id == target_user_id:
        return
    if not share_an_order(db, user.id, target_user_id):
        raise HTTPException(status_code=403, detail=FORBIDDEN)


def visible_order_ids(db: Session, user) -> Optional[Iterable[int]]:
    """
    Foydalanuvchi ko'ra oladigan buyurtmalar.
    Admin uchun None — ya'ni cheklov yo'q.
    """
    if is_admin(user):
        return None

    own_equipment = db.query(Equipment.id).filter(Equipment.owner_id == user.id).subquery()
    rows = (
        db.query(Order.id)
        .filter((Order.user_id == user.id) | (Order.equipment_id.in_(own_equipment)))
        .all()
    )
    return [row[0] for row in rows]
