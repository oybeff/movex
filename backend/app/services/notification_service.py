"""
Xabarnomalar.

Xabarnoma yaratish HECH QACHON asosiy amalni buzmasligi kerak: buyurtma
tasdiqlandi, lekin xabarnoma yozilmadi — bu buyurtmani bekor qilish uchun
sabab emas. Shuning uchun create_* funksiyalari xatolarni yutadi.
"""
import logging
from typing import List, Optional

from sqlalchemy.orm import Session

from app.core.equipment_types import type_name
from app.models.equipment import Equipment
from app.models.notification import DeviceToken, Notification
from app.models.order import Order

logger = logging.getLogger(__name__)


def _equipment_label(equipment: Optional[Equipment]) -> str:
    """
    Zaxira sarlavha uchun nom. Ilova sarlavhani equipment_type va
    equipment_model dan o'zi yig'adi, bu esa faqat eski ilovalar va push
    uchun qoladi.

    equipment.type — bu KOD ('backhoe_loader'). Uni to'g'ridan-to'g'ri
    matnga qo'yish mumkin emas: foydalanuvchi "backhoe_loader JCB 3CX"
    ko'rardi. type_name kodni o'qiladigan nomga aylantiradi.
    """
    if equipment is None:
        return "Texnika"
    parts = [p for p in (type_name(equipment.type), equipment.model) if p]
    return " ".join(parts) if parts else "Texnika"


def create(
    db: Session,
    user_id: int,
    type_: str,
    title: str,
    body: Optional[str] = None,
    order_id: Optional[int] = None,
    equipment_type: Optional[str] = None,
    equipment_model: Optional[str] = None,
    commit: bool = True,
) -> Optional[Notification]:
    """Bitta xabarnoma. Xato bo'lsa — jurnalga yozamiz va davom etamiz."""
    try:
        notification = Notification(
            user_id=user_id,
            type=type_,
            title=title,
            body=body,
            order_id=order_id,
            equipment_type=equipment_type,
            equipment_model=equipment_model,
        )
        db.add(notification)
        if commit:
            db.commit()
            db.refresh(notification)
        return notification
    except Exception:
        logger.exception("Xabarnoma yaratilmadi: user=%s type=%s", user_id, type_)
        if commit:
            db.rollback()
        return None


def notify_order_event(db: Session, order: Order, event: str, commit: bool = True) -> None:
    """
    Buyurtma bo'yicha hodisa haqida kerakli tomonlarni xabardor qiladi.

    event: created | confirmed | rejected | cancelled | completed
    """
    try:
        equipment = db.query(Equipment).filter(Equipment.id == order.equipment_id).first()
        label = _equipment_label(equipment)
        eq_type = equipment.type if equipment else None
        eq_model = equipment.model if equipment else None
        owner_id = equipment.owner_id if equipment else None
        client_id = order.user_id

        if event == "created" and owner_id:
            create(db, owner_id, "order_created",
                   f"Yangi buyurtma: {label}",
                   f"Buyurtma #{order.id}, {order.start_date} — {order.end_date}",
                   order.id, eq_type, eq_model, commit=commit)

        elif event == "confirmed":
            create(db, client_id, "order_confirmed",
                   f"Buyurtma tasdiqlandi: {label}",
                   f"Buyurtma #{order.id} egasi tomonidan tasdiqlandi",
                   order.id, eq_type, eq_model, commit=commit)

        elif event == "rejected":
            create(db, client_id, "order_rejected",
                   f"Buyurtma rad etildi: {label}",
                   f"Buyurtma #{order.id} rad etildi, pul hisobingizga qaytarildi",
                   order.id, eq_type, eq_model, commit=commit)

        elif event == "cancelled":
            for uid in {client_id, owner_id} - {None}:
                create(db, uid, "order_cancelled",
                       f"Buyurtma bekor qilindi: {label}",
                       f"Buyurtma #{order.id} bekor qilindi",
                       order.id, eq_type, eq_model, commit=commit)

        elif event == "completed":
            for uid in {client_id, owner_id} - {None}:
                create(db, uid, "order_completed",
                       f"Buyurtma yakunlandi: {label}",
                       f"Buyurtma #{order.id} muvaffaqiyatli yakunlandi",
                       order.id, eq_type, eq_model, commit=commit)

    except Exception:
        logger.exception("Buyurtma xabarnomalari yuborilmadi: order=%s event=%s", order.id, event)


def list_for_user(
    db: Session,
    user_id: int,
    only_unread: bool = False,
    skip: int = 0,
    limit: int = 50,
) -> List[Notification]:
    query = db.query(Notification).filter(Notification.user_id == user_id)
    if only_unread:
        query = query.filter(Notification.is_read.is_(False))
    return query.order_by(Notification.created_at.desc()).offset(skip).limit(limit).all()


def unread_count(db: Session, user_id: int) -> int:
    return (
        db.query(Notification)
        .filter(Notification.user_id == user_id, Notification.is_read.is_(False))
        .count()
    )


def mark_read(db: Session, user_id: int, notification_id: int) -> Optional[Notification]:
    notification = (
        db.query(Notification)
        .filter(Notification.id == notification_id, Notification.user_id == user_id)
        .first()
    )
    if notification is None:
        return None
    notification.is_read = True
    db.commit()
    db.refresh(notification)
    return notification


def mark_all_read(db: Session, user_id: int) -> int:
    count = (
        db.query(Notification)
        .filter(Notification.user_id == user_id, Notification.is_read.is_(False))
        .update({Notification.is_read: True}, synchronize_session=False)
    )
    db.commit()
    return count


def delete(db: Session, user_id: int, notification_id: int) -> bool:
    notification = (
        db.query(Notification)
        .filter(Notification.id == notification_id, Notification.user_id == user_id)
        .first()
    )
    if notification is None:
        return False
    db.delete(notification)
    db.commit()
    return True


# ------------------------------------------------------------ push tokenlari

def register_device(db: Session, user_id: int, token: str, platform: str) -> DeviceToken:
    """
    Qurilma tokenini saqlash.

    Bitta token boshqa foydalanuvchida ro'yxatdan o'tgan bo'lishi mumkin
    (bitta telefonda ikki kishi kirgan) — bunday holda token yangi egasiga
    o'tkaziladi, aks holda push noto'g'ri odamga borardi.
    """
    existing = db.query(DeviceToken).filter(DeviceToken.token == token).first()
    if existing is not None:
        existing.user_id = user_id
        existing.platform = platform
        db.commit()
        db.refresh(existing)
        return existing

    device = DeviceToken(user_id=user_id, token=token, platform=platform)
    db.add(device)
    db.commit()
    db.refresh(device)
    return device


def unregister_device(db: Session, token: str) -> bool:
    """Chiqishda chaqiriladi, aks holda push eski egasiga borib turadi."""
    device = db.query(DeviceToken).filter(DeviceToken.token == token).first()
    if device is None:
        return False
    db.delete(device)
    db.commit()
    return True
