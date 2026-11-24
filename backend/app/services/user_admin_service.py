"""
Admin P4 (Figma «Admin panel» 03 Mijozlar, 04 Haydovchilar): bloklash
sababi va muddati bilan, blokdan chiqarish, foydalanuvchiga xabar.

Panel bularni to'g'ridan-to'g'ri SQL bilan qilmaydi — `/users/internal/…`
orqali shu yerga keladi: faol buyurtmalarni bekor qilish, SMS va audit
jurnali bitta joyda bo'lsin.

- Muddat: 24h / 7d / 30d / forever. Muddat o'tsa — blok keyingi so'rovda
  o'zi olinadi (account_state.lift_expired_block), fon vazifasi yo'q.
- blocked_reason — FOYDALANUVCHI ko'radigan matn (403 javobida). Ichki
  izoh (block_note) unga ko'rinmaydi.
- Faol buyurtma bo'lsa: mijoz uchun «hozir bekor qilish» (pul faqat
  muzlatishdan chiqadi — admin_order_service.cancel), ijrochi uchun
  panel «ijrochini almashtirish» havolasini ko'rsatadi; bloklash
  buyurtmani o'zi bekor qilmaydi.
- SMS — Eskiz orqali, matnni admin oldindan ko'radi. SMS yuborilmasa ham
  blok qo'yiladi: natija javobda (`sms`).
"""
import asyncio
import logging
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.models.admin_action import AdminAction
from app.models.user import User

logger = logging.getLogger(__name__)

REASONS = {
    "fraud": "To'lov firibgarligi",
    "abuse": "Haqoratli xatti-harakat",
    "cancels": "Ko'p bekor qilish",
    "fake_docs": "Soxta hujjat",
    "other": "Boshqa sabab",
}
DURATIONS = {"24h": timedelta(hours=24), "7d": timedelta(days=7), "30d": timedelta(days=30), "forever": None}


def _now():
    return datetime.now(timezone.utc)


def _target(db: Session, user_id: int) -> User:
    u = db.query(User).filter(User.id == user_id).with_for_update().first()
    if u is None:
        raise HTTPException(404, "Foydalanuvchi topilmadi")
    if u.role == "admin":
        raise HTTPException(400, "Admin hisobini bloklab bo'lmaydi")
    return u


def _log(db: Session, admin_id: Optional[int], action: str, user_id: int, payload: dict) -> None:
    db.add(AdminAction(admin_id=admin_id, action=action, entity="user", entity_id=user_id, payload=payload))


def active_orders(db: Session, user_id: int) -> List[dict]:
    """Faol buyurtmalar — mijoz yoki ijrochi sifatida (barcha turlar)."""
    rows = db.execute(text("""
        SELECT 'equipment' AS kind, o.id, CASE WHEN o.user_id = :u THEN 'client' ELSE 'performer' END AS role,
               o.status, o.total_amount AS amount
          FROM orders o LEFT JOIN equipment e ON e.id = o.equipment_id
         WHERE (o.user_id = :u OR e.owner_id = :u) AND o.status IN ('pending', 'confirmed')
        UNION ALL
        SELECT 'request', r.id, 'client', r.status, r.budget
          FROM equipment_requests r
         WHERE r.client_id = :u AND r.mode = 'quick' AND r.status IN ('open', 'awaiting_payment')
        UNION ALL
        SELECT 'freight', f.id, CASE WHEN f.client_id = :u THEN 'client' ELSE 'performer' END, f.status, f.price
          FROM freight_orders f
         WHERE (f.client_id = :u OR f.driver_id = :u) AND f.status IN ('searching', 'accepted', 'loaded', 'arrived')
        UNION ALL
        SELECT 'material', m.id,
               CASE WHEN m.buyer_id = :u THEN 'client' WHEN m.driver_id = :u THEN 'performer' ELSE 'seller' END,
               m.status, m.total_amount
          FROM material_orders m
         WHERE (m.buyer_id = :u OR m.seller_id = :u OR m.driver_id = :u)
           AND m.status IN ('pending', 'confirmed')
    """), {"u": user_id}).mappings().all()
    return [dict(r) for r in rows]


def _until_text(until: Optional[datetime]) -> str:
    if until is None:
        return "muddatsiz"
    # Toshkent vaqti (UTC+5) — foydalanuvchi o'z soatini ko'radi
    return (until + timedelta(hours=5)).strftime("%d.%m.%Y %H:%M") + " gacha"


# SMS matnlari Eskiz shablonlari bilan HARFMA-HARF bir xil bo'lishi shart
# (my.eskiz.uz «Mening matnlarim», 25.11.2026 da moderatsiyaga berilgan:
# 103853 vaqtincha, 103854 doimiy, 103855 blokdan chiqarildi). Boshqa matnni
# Eskiz rad etadi — shuning uchun admin SMS matnini yozmaydi, faqat yoqadi.
# Sabab — ro'yxatdan (shablonda o'zgaruvchan so'z), tafsilot SMSda yo'q.
SUPPORT_CONTACT = "Telegram: @movex_support"
SMS_REASONS = {
    "fraud": "to'lov firibgarligi",
    "abuse": "haqoratli xatti-harakat",
    "cancels": "ko'p bekor qilish",
    "fake_docs": "soxta hujjat",
    "other": "qoidalarni buzish",
}


def block_sms(reason: str, until: Optional[datetime]) -> str:
    why = SMS_REASONS.get(reason, SMS_REASONS["other"])
    if until is None:
        return f"MoveX GO: hisobingiz bloklandi. Sabab: {why}. Savollar uchun {SUPPORT_CONTACT}"
    when = (until + timedelta(hours=5)).strftime("%d.%m.%Y %H:%M")
    return f"MoveX GO: hisobingiz {when} gacha bloklandi. Sabab: {why}. Savollar uchun {SUPPORT_CONTACT}"


UNBLOCK_SMS = "MoveX GO: hisobingiz blokdan chiqarildi. Ilovadan yana foydalanishingiz mumkin."


def default_sms(reason: str, duration: str) -> str:
    """Oldindan ko'rish uchun (muddat hozirdan hisoblanadi)."""
    delta = DURATIONS.get(duration)
    return block_sms(reason, _now() + delta if delta else None)


def _send_sms(db: Session, phone: str, message: str) -> dict:
    try:
        from app.services.eskiz_service import EskizService

        res = asyncio.run(EskizService(db).send_sms(phone, message))
        ok = bool(res) and res.get("success", True) is not False
        return {"sent": ok, "detail": None if ok else str(res)[:200]}
    except Exception as e:  # noqa: BLE001 — SMS xatosi blokni buzmasin
        logger.warning("Block SMS failed for %s: %s", phone, e)
        return {"sent": False, "detail": str(e)[:200]}


def block(db: Session, user_id: int, admin_id: Optional[int], reason: str, duration: str,
          note: Optional[str] = None, sms_text: Optional[str] = None, cancel_active: bool = False,
          send_sms: bool = False) -> dict:
    if reason not in REASONS:
        raise HTTPException(400, "Sababni tanlang")
    if duration not in DURATIONS:
        raise HTTPException(400, "Muddatni tanlang")
    u = _target(db, user_id)
    if u.phone.startswith("deleted-"):
        raise HTTPException(400, "Akkaunt o'chirilgan")
    delta = DURATIONS[duration]
    until = _now() + delta if delta else None

    cancelled = []
    if cancel_active:
        from app.services import admin_order_service

        for o in active_orders(db, user_id):
            if o["role"] != "client":
                continue  # ijrochining buyurtmasi — almashtiriladi, bekor emas
            try:
                admin_order_service.cancel(db, o["kind"], o["id"], admin_id, "fraud" if reason == "fraud" else "other",
                                           note=f"Mijoz bloklandi: {REASONS[reason]}")
                cancelled.append(f"{o['kind']}#{o['id']}")
            except HTTPException as e:
                db.rollback()
                logger.warning("Block: cancel %s#%s failed: %s", o["kind"], o["id"], e.detail)
        u = _target(db, user_id)

    u.is_blocked = True
    u.blocked_until = until
    u.blocked_at = _now()
    u.blocked_by = admin_id
    u.block_reason_code = reason
    u.block_note = (note or "").strip()[:1000] or None
    u.blocked_reason = (f"Hisobingiz {_until_text(until)} bloklangan. Sabab: {REASONS[reason]}. "
                        f"Savollar bo'lsa — {SUPPORT_CONTACT}")
    _log(db, admin_id, "user_block", user_id,
         {"reason": reason, "duration": duration, "note": u.block_note, "cancelled": cancelled,
          "until": until.isoformat() if until else None})
    db.commit()

    sms = None
    # sms_text — eski panel uchun: matni e'tiborsiz, faqat «yuborilsin» belgisi.
    if send_sms or (sms_text and sms_text.strip()):
        text_ = block_sms(reason, until)
        sms = _send_sms(db, u.phone, text_)
        db.add(AdminAction(admin_id=admin_id, action="user_sms", entity="user", entity_id=user_id,
                           payload={"text": text_, **sms}))
        db.commit()
    return {"user_id": user_id, "blocked_until": until, "cancelled": cancelled, "sms": sms}


def unblock(db: Session, user_id: int, admin_id: Optional[int], send_sms: bool = False) -> dict:
    u = _target(db, user_id)
    if u.phone.startswith("deleted-"):
        raise HTTPException(400, "O'chirilgan akkauntni tiklab bo'lmaydi")
    u.is_blocked = False
    u.blocked_reason = None
    u.blocked_until = None
    _log(db, admin_id, "user_unblock", user_id, {"reason": u.block_reason_code})
    db.commit()
    sms = None
    if send_sms:
        sms = _send_sms(db, u.phone, UNBLOCK_SMS)
        db.add(AdminAction(admin_id=admin_id, action="user_sms", entity="user", entity_id=user_id,
                           payload={"text": UNBLOCK_SMS, **sms}))
        db.commit()
    return {"user_id": user_id, "unblocked": True, "sms": sms}


def message(db: Session, user_id: int, admin_id: Optional[int], body: str, sms: bool = False) -> dict:
    """«Xabar yuborish»: ilova ichida bildirishnoma (+ xohlasa SMS)."""
    from app.services import notification_service

    body = (body or "").strip()
    if not body:
        raise HTTPException(400, "Xabar matnini yozing")
    u = db.query(User).filter(User.id == user_id).first()
    if u is None:
        raise HTTPException(404, "Foydalanuvchi topilmadi")
    notification_service.create(db, user_id, "system", "MoveX GO", body[:1000])
    sms_res = _send_sms(db, u.phone, body[:300]) if sms else None
    _log(db, admin_id, "user_message", user_id, {"text": body[:1000], "sms": sms_res})
    db.commit()
    return {"user_id": user_id, "sms": sms_res}
