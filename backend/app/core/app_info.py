"""
Ilova kim va qaysi versiyada — har so'rovda (Admin P5).

Ilova `X-App-Version`, `X-App-Platform` (android|ios|web) va
`X-App-Flavor` (client|driver) sarlavhalarini yuboradi. Shundan:
push auditoriyasi «oxirgi faollik», «eski versiyada» ustuni (S4).

Yozish arzon bo'lsin: o'zgarmagan bo'lsa va oxirgi belgi 5 daqiqadan
yangi bo'lsa — bazaga tegmaymiz. Xato so'rovni buzmaydi.
"""
import logging
import re
from datetime import datetime, timedelta, timezone

logger = logging.getLogger(__name__)

_VERSION = re.compile(r"^\d{1,3}(\.\d{1,3}){1,3}$")


def touch_app_info(db, user, request) -> None:
    if request is None or user is None:
        return
    try:
        h = request.headers
        version = (h.get("x-app-version") or "").strip()
        platform = (h.get("x-app-platform") or "").strip().lower()
        flavor = (h.get("x-app-flavor") or "").strip().lower()
        version = version if _VERSION.match(version) else None
        platform = platform if platform in ("android", "ios", "web") else None
        flavor = flavor if flavor in ("client", "driver") else None

        now = datetime.now(timezone.utc)
        changed = (
            (version and version != user.app_version)
            or (platform and platform != user.app_platform)
            or (flavor and flavor != user.app_flavor)
        )
        stale = user.last_seen_at is None or user.last_seen_at < now - timedelta(minutes=5)
        if not changed and not stale:
            return
        if version:
            user.app_version = version
        if platform:
            user.app_platform = platform
        if flavor:
            user.app_flavor = flavor
        user.last_seen_at = now
        db.commit()
    except Exception as e:  # noqa: BLE001 — statistika so'rovni yiqitmasin
        logger.warning("touch_app_info failed: %s", e)
        try:
            db.rollback()
        except Exception:  # noqa: BLE001
            pass
