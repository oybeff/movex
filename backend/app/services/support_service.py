"""
«Yordam» chati (Figma «Admin panel» N5): foydalanuvchi ilovadan yozadi,
admin paneldan javob beradi. Bitta foydalanuvchi — bitta ochiq suhbat;
admin yopgandan keyin yozsa — yangi suhbat ochiladi.

Push yo'q (Firebase ulanmagan): ilova suhbatni ochiq turganda so'rab
turadi, admin javobi esa ilova ichidagi bildirishnoma bo'lib ham keladi.
"""
from datetime import datetime, timezone
from typing import Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.media import is_own_media
from app.models.admin_action import AdminAction
from app.models.order_problem import SupportMessage, SupportThread
from app.models.user import User
from app.services import admin_order_service, notification_service

APPS = ("client", "driver")


def _now():
    return datetime.now(timezone.utc)


def _open_thread(db: Session, user_id: int, app: str) -> Optional[SupportThread]:
    return (db.query(SupportThread)
            .filter(SupportThread.user_id == user_id, SupportThread.app == app, SupportThread.status == "open")
            .order_by(SupportThread.id.desc()).first())


def _last_thread(db: Session, user_id: int, app: str) -> Optional[SupportThread]:
    return (db.query(SupportThread)
            .filter(SupportThread.user_id == user_id, SupportThread.app == app)
            .order_by(SupportThread.id.desc()).first())


def _dump(db: Session, t: Optional[SupportThread], viewer_id: int) -> dict:
    if t is None:
        return {"id": None, "status": "none", "messages": []}
    msgs = (db.query(SupportMessage).filter(SupportMessage.thread_id == t.id)
            .order_by(SupportMessage.created_at).all())
    return {
        "id": t.id, "status": t.status,
        "messages": [{"id": m.id, "mine": not m.is_admin and m.author_id == viewer_id, "is_admin": m.is_admin,
                      "text": m.text, "photo": m.photo, "created_at": m.created_at} for m in msgs],
    }


def get_thread(db: Session, user: User, app: str) -> dict:
    if app not in APPS:
        raise HTTPException(400, "app noto'g'ri")
    t = _last_thread(db, user.id, app)
    if t is not None:
        t.user_read_at = _now()
        db.commit()
    return _dump(db, t, user.id)


def unread(db: Session, user: User, app: str) -> int:
    t = _last_thread(db, user.id, app)
    if t is None:
        return 0
    q = db.query(SupportMessage).filter(SupportMessage.thread_id == t.id, SupportMessage.is_admin.is_(True))
    if t.user_read_at is not None:
        q = q.filter(SupportMessage.created_at > t.user_read_at)
    return q.count()


def post(db: Session, user: User, app: str, text: Optional[str], photo: Optional[str]) -> dict:
    if app not in APPS:
        raise HTTPException(400, "app noto'g'ri")
    text = (text or "").strip()[:2000]
    if photo and not (is_own_media(photo) and photo.startswith("/static/problems/")):
        raise HTTPException(400, "Rasm manzili noto'g'ri")
    if not text and not photo:
        raise HTTPException(400, "Xabar bo'sh")
    t = _open_thread(db, user.id, app)
    if t is None:
        t = SupportThread(user_id=user.id, app=app, status="open")
        db.add(t)
        db.flush()
    db.add(SupportMessage(thread_id=t.id, author_id=user.id, is_admin=False, text=text or None, photo=photo))
    t.last_message_at = _now()
    t.user_read_at = _now()
    db.commit()
    return _dump(db, t, user.id)


# =================================================================== admin

def admin_reply(db: Session, admin_id: int, thread_id: int, text: str) -> dict:
    admin_order_service._admin(db, admin_id)
    text = (text or "").strip()[:2000]
    if not text:
        raise HTTPException(400, "Xabar bo'sh")
    t = db.query(SupportThread).filter(SupportThread.id == thread_id).first()
    if t is None:
        raise HTTPException(404, "Suhbat topilmadi")
    if t.status != "open":
        t.status = "open"
    db.add(SupportMessage(thread_id=t.id, author_id=admin_id, is_admin=True, text=text))
    t.last_message_at = _now()
    t.admin_read_at = _now()
    if t.assigned_admin_id is None:
        t.assigned_admin_id = admin_id
    db.commit()
    try:
        notification_service.create_localized(
            db, t.user_id, "support_reply", "support_reply.title", "support_reply.body", None, None, None,
            text=text[:120])
    except Exception:  # noqa: BLE001
        db.rollback()
    return {"ok": True}


def admin_close(db: Session, admin_id: int, thread_id: int) -> dict:
    admin_order_service._admin(db, admin_id)
    t = db.query(SupportThread).filter(SupportThread.id == thread_id).first()
    if t is None:
        raise HTTPException(404, "Suhbat topilmadi")
    t.status = "closed"
    t.admin_read_at = _now()
    db.add(AdminAction(admin_id=admin_id, action="support_close", entity="support", entity_id=t.id, payload=None))
    db.commit()
    return {"ok": True}
