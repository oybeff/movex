"""
Push-bildirishnomalar: Firebase Cloud Messaging, HTTP v1 API.

Ikki qoida bu yerda hamma narsadan muhim.

1. PUSH HECH QACHON ASOSIY AMALNI BUZMAYDI. Buyurtma yaratildi, lekin push
   ketmadi — bu buyurtmani bekor qilish uchun sabab emas. Shuning uchun
   barcha xatolar yutiladi va faqat jurnalga yoziladi.

2. SOZLANMAGAN BO'LSA — JIM TURADI. Firebase loyihasi hali yo'q, va shu
   holatda ham ilova ishlashi kerak: xabarnomalar ilova ichida odatdagidek
   ko'rinadi, push esa yuborilmaydi.

Nega google-auth kutubxonasi emas. FCM v1 uchun kerak bo'ladigan narsa —
xizmat akkaunti kaliti bilan imzolangan JWT va uni access token'ga
almashtirish. python-jose loyihada allaqachon bor (JWT autentifikatsiyasi
uchun), shuning uchun yangi bog'liqlik qo'shmaymiz.

Sozlash: docs/backend/NOTIFICATIONS.md
"""
import json
import logging
import os
import threading
import time
from typing import Dict, List, Optional

import requests
from jose import jwt
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.notification import DeviceToken

logger = logging.getLogger(__name__)

GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
FCM_SEND_URL = "https://fcm.googleapis.com/v1/projects/{project}/messages:send"

#: Access token bir soat yashaydi; muddatidan sal oldin yangilaymiz.
TOKEN_LIFETIME_SECONDS = 3600
TOKEN_REFRESH_MARGIN = 120

REQUEST_TIMEOUT = 10

_token_lock = threading.Lock()
_access_token: Optional[str] = None
_access_token_expires_at: float = 0.0

_warned_not_configured = False


# ------------------------------------------------------------ kalit fayli

def _load_credentials() -> Optional[Dict[str, str]]:
    path = settings.FCM_CREDENTIALS_FILE
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        logger.exception("FCM kalit faylini o'qib bo'lmadi: %s", path)
        return None

    if not data.get("client_email") or not data.get("private_key"):
        logger.error("FCM kalit faylida client_email yoki private_key yo'q: %s", path)
        return None
    return data


def _fetch_access_token() -> Optional[str]:
    """Xizmat akkaunti kaliti bilan imzolangan JWT -> access token."""
    creds = _load_credentials()
    if creds is None:
        return None

    now = int(time.time())
    claims = {
        "iss": creds["client_email"],
        "scope": FCM_SCOPE,
        "aud": creds.get("token_uri", GOOGLE_TOKEN_URL),
        "iat": now,
        "exp": now + TOKEN_LIFETIME_SECONDS,
    }

    try:
        assertion = jwt.encode(claims, creds["private_key"], algorithm="RS256")
        response = requests.post(
            creds.get("token_uri", GOOGLE_TOKEN_URL),
            data={
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": assertion,
            },
            timeout=REQUEST_TIMEOUT,
        )
        if response.status_code != 200:
            logger.error(
                "FCM access token olinmadi: %s %s",
                response.status_code,
                response.text[:300],
            )
            return None
        return response.json().get("access_token")
    except Exception:
        logger.exception("FCM access token olishda xato")
        return None


def _access_token_cached() -> Optional[str]:
    global _access_token, _access_token_expires_at

    with _token_lock:
        if _access_token and time.time() < _access_token_expires_at:
            return _access_token

        token = _fetch_access_token()
        if token:
            _access_token = token
            _access_token_expires_at = (
                time.time() + TOKEN_LIFETIME_SECONDS - TOKEN_REFRESH_MARGIN
            )
        return token


# ---------------------------------------------------------------- yuborish

def _send_to_token(access_token: str, device_token: str, title: str,
                   body: Optional[str], data: Dict[str, str]) -> Optional[int]:
    """Bitta qurilmaga yuboradi. HTTP kodni qaytaradi (xato bo'lsa None)."""
    payload = {
        "message": {
            "token": device_token,
            "notification": {"title": title, "body": body or ""},
            # data — faqat matn qiymatlari, FCM boshqasini qabul qilmaydi
            "data": {k: str(v) for k, v in data.items() if v is not None},
            "android": {"priority": "high"},
            "apns": {"headers": {"apns-priority": "10"}},
        }
    }
    try:
        response = requests.post(
            FCM_SEND_URL.format(project=settings.FCM_PROJECT_ID),
            json=payload,
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=REQUEST_TIMEOUT,
        )
        if response.status_code >= 400:
            logger.warning(
                "FCM yuborilmadi (%s): %s", response.status_code, response.text[:200]
            )
        return response.status_code
    except Exception:
        logger.exception("FCM so'rovi bajarilmadi")
        return None


def send_to_user(
    db: Session,
    user_id: int,
    title: str,
    body: Optional[str] = None,
    data: Optional[Dict[str, str]] = None,
) -> int:
    """
    Foydalanuvchining barcha qurilmalariga push.

    Muvaffaqiyatli yuborilganlar sonini qaytaradi. Sozlanmagan bo'lsa 0 —
    va bu xato emas.
    """
    global _warned_not_configured

    if not settings.fcm_configured:
        if not _warned_not_configured:
            logger.info(
                "Push yuborilmaydi: FCM sozlanmagan "
                "(FCM_PROJECT_ID va FCM_CREDENTIALS_FILE). "
                "Xabarnomalar ilova ichida ko'rinadi."
            )
            _warned_not_configured = True
        return 0

    try:
        tokens: List[DeviceToken] = (
            db.query(DeviceToken).filter(DeviceToken.user_id == user_id).all()
        )
        if not tokens:
            return 0

        access_token = _access_token_cached()
        if access_token is None:
            return 0

        sent = 0
        dead: List[DeviceToken] = []
        for device in tokens:
            status = _send_to_token(
                access_token, device.token, title, body, data or {}
            )
            if status == 200:
                sent += 1
            elif status in (400, 403, 404):
                # 404 UNREGISTERED — ilova o'chirilgan yoki token almashgan.
                # 400 INVALID_ARGUMENT — token buzilgan.
                # Bunday tokenlarni saqlashning ma'nosi yo'q: har safar
                # bekorga so'rov ketaveradi.
                dead.append(device)

        if dead:
            for device in dead:
                db.delete(device)
            db.commit()
            logger.info("Yaroqsiz %d ta qurilma tokeni o'chirildi", len(dead))

        return sent
    except Exception:
        logger.exception("Push yuborishda xato: user=%s", user_id)
        try:
            db.rollback()
        except Exception:
            pass
        return 0
