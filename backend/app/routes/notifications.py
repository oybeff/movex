"""
Xabarnomalar: ilova ichidagi ro'yxat va push uchun qurilma tokenlari.

Har bir endpoint faqat O'Z xabarnomalari bilan ishlaydi — begonasini
ko'rish ham, o'chirish ham mumkin emas.
"""
from typing import List

from fastapi import APIRouter, Body, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.routes.auth import get_current_user
from app.schemas.notification import (
    DeviceTokenCreate,
    DeviceTokenRead,
    NotificationRead,
    UnreadCount,
)
from app.services import notification_service

router = APIRouter()


@router.get("/", response_model=List[NotificationRead])
def list_notifications(
    only_unread: bool = Query(False, description="Faqat o'qilmaganlar"),
    skip: int = 0,
    limit: int = Query(50, le=200),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    return notification_service.list_for_user(db, current_user.id, only_unread, skip, limit)


@router.get("/unread-count", response_model=UnreadCount)
def get_unread_count(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Ilovadagi qo'ng'iroq belgisidagi raqam uchun."""
    return {"unread": notification_service.unread_count(db, current_user.id)}


@router.post("/{notification_id}/read", response_model=NotificationRead)
def mark_notification_read(
    notification_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    notification = notification_service.mark_read(db, current_user.id, notification_id)
    if notification is None:
        raise HTTPException(status_code=404, detail="Xabarnoma topilmadi")
    return notification


@router.post("/read-all", response_model=UnreadCount)
def mark_all_notifications_read(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    notification_service.mark_all_read(db, current_user.id)
    return {"unread": 0}


# ------------------------------------------------------------ push tokenlari
#
# DIQQAT: "/devices" yo'llari "/{notification_id}" dan OLDIN turishi shart.
# Aks holda FastAPI "devices" so'zini xabarnoma raqami deb o'qishga urinadi
# va 422 qaytaradi.

@router.post("/devices", response_model=DeviceTokenRead)
def register_device(
    data: DeviceTokenCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    Push uchun qurilma tokenini ro'yxatdan o'tkazish.

    Firebase ulanmaguncha push yuborilmaydi, lekin ilova tokenni hozirdan
    yuborishi mumkin — server tomoni tayyor.
    """
    return notification_service.register_device(db, current_user.id, data.token, data.platform)


@router.delete("/devices", response_model=dict)
def unregister_device(
    token: str = Body(..., embed=True),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Chiqishda chaqiriladi, aks holda push eski egasiga borib turadi."""
    notification_service.unregister_device(db, token)
    return {"message": "Qurilma o'chirildi"}


# ------------------------------------------------ xabarnomaning o'zi bo'yicha

@router.delete("/{notification_id}", response_model=dict)
def delete_notification(
    notification_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    if not notification_service.delete(db, current_user.id, notification_id):
        raise HTTPException(status_code=404, detail="Xabarnoma topilmadi")
    return {"message": "Xabarnoma o'chirildi"}
