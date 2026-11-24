"""
Admin «Push xabarlar» (Figma «Admin panel» 08, P1–P4).

Kampaniya = har bir qabul qiluvchiga bitta `notifications` yozuvi
(type='system', campaign_id) + FCM push (sozlanmagan bo'lsa — faqat ilova
ichida, bu xato emas). Shuning uchun raqamlar haqiqiy:
- «Yetkazildi» = yozilgan bildirishnomalar soni (recipients),
- «Ochildi»    = shulardan is_read = true — hisoblanadi, saqlanmaydi.

Auditoriya (JSON):
    role         all | client | driver   (driver = role 'owner')
    langs        ['uz', 'ru'] — kamida bittasi
    active_days  null | N — oxirgi N kunda ilovani ochganlar (last_seen_at)
    zone_id      null | price_zones.id — nuqtasi shu hududda bo'lganlar:
                 haydovchi — oxirgi GPS (driver_locations), mijoz — qidiruv
                 nuqtasi. Nuqtasi yo'q odam hudud filtriga tushmaydi.
Bloklangan, o'chirilgan va adminlar hech qachon kirmaydi.

Jim soatlar 22:00–08:00 (Toshkent): shu oraliqqa tushgan yuborish 08:00 ga
suriladi — «hozir» ham. Rejalashtirilganlarni fon sikli yuboradi
(`run_due`), ikki worker bir kampaniyani ikki marta olmaydi:
status 'scheduled' → 'sending' bitta UPDATE ... RETURNING bilan o'tadi.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Iterable, List, Optional

from fastapi import HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.admin_action import AdminAction
from app.models.admin_p5 import PushCampaign
from app.services import push_service
from app.services.zone_service import point_in_polygon

logger = logging.getLogger(__name__)

TASHKENT = timezone(timedelta(hours=5))
QUIET_FROM, QUIET_TO = 22, 8
DAILY_LIMIT = 2
TITLE_MAX, BODY_MAX = 65, 240


def _now() -> datetime:
    return datetime.now(timezone.utc)


def shift_quiet(when: datetime) -> datetime:
    """22:00–08:00 Toshkent oralig'i → keyingi 08:00."""
    local = when.astimezone(TASHKENT)
    if local.hour >= QUIET_FROM:
        local = (local + timedelta(days=1)).replace(hour=QUIET_TO, minute=0, second=0, microsecond=0)
    elif local.hour < QUIET_TO:
        local = local.replace(hour=QUIET_TO, minute=0, second=0, microsecond=0)
    return local.astimezone(timezone.utc)


def normalize_audience(a: dict) -> dict:
    role = a.get("role") or "all"
    if role not in ("all", "client", "driver"):
        raise HTTPException(400, "Auditoriya noto'g'ri")
    # Kalit bor-u bo'sh — admin ikkala tilni ham olib tashlagan: «hammaga»
    # emas, xato. Kalit umuman yo'q bo'lsa — ikkala til.
    raw_langs = a["langs"] if "langs" in a else ["uz", "ru"]
    langs = [x for x in (raw_langs or []) if x in ("uz", "ru")]
    if not langs:
        raise HTTPException(400, "Kamida bitta til tanlang")
    days = a.get("active_days")
    days = int(days) if days not in (None, "", 0, "0") else None
    if days is not None and not 1 <= days <= 365:
        raise HTTPException(400, "Faollik 1–365 kun")
    zone = a.get("zone_id")
    zone = int(zone) if zone not in (None, "", 0, "0") else None
    return {"role": role, "langs": sorted(set(langs)), "active_days": days, "zone_id": zone}


def _candidates(db: Session, aud: dict) -> List[tuple]:
    """[(user_id, language, lat, lon)] — hududdan oldingi ro'yxat."""
    where = ["u.role IN ('client','owner')", "COALESCE(u.is_blocked, false) = false",
             "u.phone NOT LIKE 'deleted-%'", "u.language = ANY(:langs)"]
    params = {"langs": aud["langs"]}
    if aud["role"] == "client":
        where.append("u.role = 'client'")
    elif aud["role"] == "driver":
        where.append("u.role = 'owner'")
    if aud["active_days"]:
        where.append("u.last_seen_at >= NOW() - make_interval(days => :days)")
        params["days"] = aud["active_days"]
    sql = (
        "SELECT u.id, u.language, COALESCE(dl.latitude, u.search_latitude), "
        "COALESCE(dl.longitude, u.search_longitude) FROM users u "
        "LEFT JOIN driver_locations dl ON dl.user_id = u.id WHERE " + " AND ".join(where)
    )
    return db.execute(text(sql), params).fetchall()


def resolve(db: Session, aud: dict) -> List[tuple]:
    rows = _candidates(db, aud)
    if not aud["zone_id"]:
        return [(r[0], r[1]) for r in rows]
    poly = db.execute(text("SELECT polygon FROM price_zones WHERE id = :id"), {"id": aud["zone_id"]}).scalar()
    if not poly:
        return []
    return [(r[0], r[1]) for r in rows
            if r[2] is not None and r[3] is not None and point_in_polygon(float(r[2]), float(r[3]), poly)]


def audience_stats(db: Session, raw: dict) -> dict:
    aud = normalize_audience(raw)
    users = resolve(db, aud)
    by_lang = {"uz": 0, "ru": 0}
    for _, lang in users:
        by_lang[lang if lang in by_lang else "uz"] += 1
    ids = [u for u, _ in users]
    with_device = 0
    if ids:
        with_device = db.execute(text("SELECT COUNT(DISTINCT user_id) FROM device_tokens WHERE user_id = ANY(:ids)"),
                                 {"ids": ids}).scalar() or 0
    role_totals = dict(db.execute(text(
        "SELECT role, COUNT(*) FROM users WHERE role IN ('client','owner') AND COALESCE(is_blocked,false)=false "
        "AND phone NOT LIKE 'deleted-%' GROUP BY role")).fetchall())
    today = db.execute(text(
        "SELECT COUNT(*) FROM push_campaigns WHERE status IN ('sent','sending') "
        "AND (sent_at AT TIME ZONE 'Asia/Tashkent')::date = (NOW() AT TIME ZONE 'Asia/Tashkent')::date "
        "AND (audience->>'role' = :r OR audience->>'role' = 'all' OR :r = 'all')"), {"r": aud["role"]}).scalar() or 0
    return {
        "audience": aud, "total": len(users), "by_lang": by_lang, "with_device": int(with_device),
        "clients_total": int(role_totals.get("client", 0)), "drivers_total": int(role_totals.get("owner", 0)),
        "sent_today": int(today), "daily_limit": DAILY_LIMIT,
        "push_configured": bool(settings.fcm_configured),
    }


def _validate_content(d: dict) -> dict:
    t_uz = (d.get("title_uz") or "").strip()
    b_uz = (d.get("body_uz") or "").strip()
    if not t_uz or not b_uz:
        raise HTTPException(400, "O'zbekcha sarlavha va matn majburiy")
    t_ru = (d.get("title_ru") or "").strip() or None
    b_ru = (d.get("body_ru") or "").strip() or None
    if (t_ru is None) != (b_ru is None):
        raise HTTPException(400, "Ruscha sarlavha va matn birga to'ldiriladi")
    for v, n in ((t_uz, TITLE_MAX), (t_ru, TITLE_MAX)):
        if v and len(v) > n:
            raise HTTPException(400, f"Sarlavha {n} belgidan oshmasin")
    for v in (b_uz, b_ru):
        if v and len(v) > BODY_MAX:
            raise HTTPException(400, f"Matn {BODY_MAX} belgidan oshmasin")
    return {"title_uz": t_uz, "body_uz": b_uz, "title_ru": t_ru, "body_ru": b_ru}


def _log(db: Session, admin_id: Optional[int], action: str, cid: int, payload: dict) -> None:
    db.add(AdminAction(admin_id=admin_id, action=action, entity="push", entity_id=cid, payload=payload))


def create(db: Session, admin_id: int, data: dict) -> dict:
    """mode: draft | now | schedule (scheduled_at ISO, Toshkent yoki UTC)."""
    content = _validate_content(data)
    aud = normalize_audience(data.get("audience") or {})
    mode = data.get("mode") or "draft"
    c = PushCampaign(**content, audience=aud, created_by=admin_id, status="draft")
    if mode in ("now", "schedule"):
        if mode == "now":
            when = _now()
        else:
            try:
                when = datetime.fromisoformat(str(data.get("scheduled_at")))
            except (TypeError, ValueError):
                raise HTTPException(400, "Yuborish vaqti noto'g'ri")
            if when.tzinfo is None:
                when = when.replace(tzinfo=TASHKENT)
            if when < _now() - timedelta(minutes=1):
                raise HTTPException(400, "Yuborish vaqti o'tib ketgan")
        shifted = shift_quiet(when)
        if not resolve(db, aud):
            raise HTTPException(400, "Tanlangan filtrga mos foydalanuvchi yo'q (0)")
        c.status = "scheduled"
        c.scheduled_at = shifted
    db.add(c)
    db.flush()
    _log(db, admin_id, "push_" + ("draft" if c.status == "draft" else "scheduled"), c.id,
         {"title": c.title_uz, "audience": aud,
          "scheduled_at": c.scheduled_at.isoformat() if c.scheduled_at else None})
    db.commit()
    if c.status == "scheduled" and c.scheduled_at <= _now():
        send(db, c.id)
        db.refresh(c)
    return to_dict(c)


def cancel(db: Session, admin_id: int, cid: int) -> dict:
    c = db.query(PushCampaign).filter(PushCampaign.id == cid).with_for_update().first()
    if c is None:
        raise HTTPException(404, "Xabar topilmadi")
    if c.status not in ("draft", "scheduled"):
        raise HTTPException(409, "Yuborilgan xabarni bekor qilib bo'lmaydi")
    c.status = "cancelled"
    _log(db, admin_id, "push_cancelled", c.id, {"title": c.title_uz})
    db.commit()
    return to_dict(c)


def _claim(db: Session, cid: Optional[int] = None) -> List[int]:
    sql = ("UPDATE push_campaigns SET status = 'sending' WHERE status = 'scheduled' AND scheduled_at <= NOW()"
           + (" AND id = :id" if cid else "") + " RETURNING id")
    ids = [r[0] for r in db.execute(text(sql), {"id": cid} if cid else {}).fetchall()]
    db.commit()
    return ids


def _deliver(db: Session, c: PushCampaign, users: Iterable[tuple]) -> int:
    n = 0
    rows = []
    for uid, lang in users:
        ru = lang == "ru" and c.title_ru
        rows.append({"u": uid, "t": c.title_ru if ru else c.title_uz, "b": c.body_ru if ru else c.body_uz,
                     "c": c.id})
    for i in range(0, len(rows), 1000):
        chunk = rows[i:i + 1000]
        db.execute(text("INSERT INTO notifications (user_id, type, title, body, campaign_id, is_read, created_at) "
                        "VALUES (:u, 'system', :t, :b, :c, false, NOW())"), chunk)
        n += len(chunk)
    db.commit()
    return n


def send(db: Session, cid: int) -> None:
    for claimed in _claim(db, cid):
        _send_claimed(db, claimed)


def _send_claimed(db: Session, cid: int) -> None:
    c = db.query(PushCampaign).filter(PushCampaign.id == cid).first()
    try:
        users = resolve(db, normalize_audience(c.audience))
        c.recipients = _deliver(db, c, users)
        pushed = 0
        if settings.fcm_configured:
            for uid, lang in users:
                ru = lang == "ru" and c.title_ru
                pushed += push_service.send_to_user(db, uid, c.title_ru if ru else c.title_uz,
                                                    c.body_ru if ru else c.body_uz,
                                                    {"type": "system", "campaign_id": str(c.id)})
        c.pushed = pushed
        c.status = "sent"
        c.sent_at = _now()
        c.error = None if c.recipients else "Qabul qiluvchi qolmadi"
        db.add(AdminAction(admin_id=None, action="push_sent", entity="push", entity_id=c.id,
                           payload={"recipients": c.recipients, "pushed": pushed}))
        db.commit()
    except Exception as e:  # noqa: BLE001
        db.rollback()
        logger.exception("Push campaign %s failed", cid)
        c = db.query(PushCampaign).filter(PushCampaign.id == cid).first()
        c.status = "failed"
        c.error = str(e)[:500]
        db.commit()


def run_due(db: Session) -> int:
    ids = _claim(db)
    for cid in ids:
        _send_claimed(db, cid)
    return len(ids)


def test_send(db: Session, admin_id: int, data: dict) -> dict:
    """Bitta telefon raqamga sinov — o'sha odamning ilovasida ko'rinadi."""
    content = _validate_content(data)
    digits = "".join(ch for ch in str(data.get("phone") or "") if ch.isdigit())
    if len(digits) == 9:
        digits = "998" + digits
    uid = db.execute(text("SELECT id FROM users WHERE phone = :p"), {"p": digits}).scalar()
    if uid is None:
        raise HTTPException(404, "Bu raqamda foydalanuvchi yo'q")
    lang = db.execute(text("SELECT language FROM users WHERE id = :u"), {"u": uid}).scalar()
    ru = lang == "ru" and content["title_ru"]
    title = "[TEST] " + (content["title_ru"] if ru else content["title_uz"])
    body = content["body_ru"] if ru else content["body_uz"]
    db.execute(text("INSERT INTO notifications (user_id, type, title, body, is_read, created_at) "
                    "VALUES (:u, 'system', :t, :b, false, NOW())"), {"u": uid, "t": title, "b": body})
    _log(db, admin_id, "push_test", 0, {"phone": digits})
    db.commit()
    pushed = push_service.send_to_user(db, uid, title, body, {"type": "system"})
    return {"ok": True, "user_id": uid, "pushed": pushed}


def to_dict(c: PushCampaign) -> dict:
    return {"id": c.id, "status": c.status, "recipients": c.recipients, "pushed": c.pushed,
            "scheduled_at": c.scheduled_at.isoformat() if c.scheduled_at else None,
            "sent_at": c.sent_at.isoformat() if c.sent_at else None, "error": c.error}
