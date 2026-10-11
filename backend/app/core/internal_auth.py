"""
PHP adminkasi uchun ichki kirish (X-Admin-Secret).

Panel bazaga to'g'ridan-to'g'ri yozib pul harakatlantirmasligi kerak:
pul mantig'i BITTA joyda — servislarda — turishi shart. Ilgari payouts.php
shu mantiqni takrorlardi va ikkisi ajralib ketishi mumkin edi. Endi panel
pul bilan bog'liq amallarni (kartaga o'tkazish, sovg'a berish) shu kalit
bilan API orqali bajaradi.

Maxfiy so'z bo'sh bo'lsa manzil YO'Q (404): imzosiz manzil orqali istalgan
odam chet kartaga pul jo'natishni yoki o'ziga sovg'a yozishni buyurgan
bo'lardi.
"""
from hmac import compare_digest
from typing import Optional

from fastapi import Header, HTTPException

from app.core.config import settings


def require_internal_admin(secret: Optional[str] = Header(None, alias="X-Admin-Secret")):
    if not settings.ADMIN_INTERNAL_SECRET:
        raise HTTPException(status_code=404, detail="Not Found")
    if not secret or not compare_digest(str(secret), settings.ADMIN_INTERNAL_SECRET):
        raise HTTPException(status_code=403, detail="Forbidden")
    return True
