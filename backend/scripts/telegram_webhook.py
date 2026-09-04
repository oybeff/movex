#!/usr/bin/env python3
"""
Telegram vebhukini ro'yxatdan o'tkazish, o'chirish va tekshirish.

Prodda bot yangiliklari VEBHUK orqali keladi, so'rab turish orqali emas:
uvicorn bir necha jarayonda ishlaydi va har biri o'zicha so'rasa,
Telegram 409 qaytaradi (bitta botni ikki joydan so'rab bo'lmaydi).

    python scripts/telegram_webhook.py info
    python scripts/telegram_webhook.py set https://movex.example.uz
    python scripts/telegram_webhook.py delete

`set` .env dagi TELEGRAM_WEBHOOK_SECRET ni ishlatadi va uni Telegramga
beradi — shundan keyin Telegram har bir so'rovga shu so'zni qo'shadi.
So'z bo'sh bo'lsa manzil ilovada YOPIQ (404), shuning uchun `set` ham
ishlamaydi: aks holda bot jim bo'lib qolardi va buni hech kim sezmasdi.
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import requests  # noqa: E402

from app.core.config import settings  # noqa: E402

PATH = "/auth/telegram/webhook"


def _api(method: str) -> str:
    return f"https://api.telegram.org/bot{settings.TELEGRAM_BOT_TOKEN}/{method}"


def _require_token() -> None:
    if not settings.TELEGRAM_BOT_TOKEN:
        sys.exit("TELEGRAM_BOT_TOKEN .env da yo'q")


def info() -> None:
    _require_token()
    data = requests.get(_api("getWebhookInfo"), timeout=20).json()
    result = data.get("result", {})
    url = result.get("url") or "(yo'q — so'rab turish rejimi)"
    print(f"Manzil:            {url}")
    print(f"Maxfiy so'z bor:   {'ha' if result.get('has_custom_certificate') is not None and result.get('url') else '—'}")
    print(f"Kutayotgan:        {result.get('pending_update_count', 0)}")
    if result.get("last_error_message"):
        print(f"Oxirgi xato:       {result['last_error_message']}")


def set_webhook(base: str) -> None:
    _require_token()
    if not settings.TELEGRAM_WEBHOOK_SECRET:
        sys.exit(
            "TELEGRAM_WEBHOOK_SECRET .env da bo'sh.\n"
            "Bo'sh so'z bilan manzil ilovada YOPIQ (404) — vebhuk jim qolardi.\n"
            "Yarating:  openssl rand -hex 32"
        )
    if not base.startswith("https://"):
        sys.exit("Telegram faqat https manzilni qabul qiladi")

    url = base.rstrip("/") + PATH
    data = requests.post(
        _api("setWebhook"),
        json={
            "url": url,
            "secret_token": settings.TELEGRAM_WEBHOOK_SECRET,
            "allowed_updates": ["message"],
            # Eski, so'rab turish paytida yig'ilgan yangiliklarni tashlaymiz:
            # ular allaqachon ishlangan yoki muddati o'tgan
            "drop_pending_updates": True,
        },
        timeout=20,
    ).json()
    if not data.get("ok"):
        sys.exit(f"Telegram rad etdi: {data.get('description')}")
    print(f"Vebhuk o'rnatildi: {url}")
    print("Endi .env da TELEGRAM_POLLING=false bo'lsin — ikkalasi birga kerak emas.")


def delete_webhook() -> None:
    _require_token()
    data = requests.post(_api("deleteWebhook"), json={"drop_pending_updates": False}, timeout=20).json()
    if not data.get("ok"):
        sys.exit(f"Telegram rad etdi: {data.get('description')}")
    print("Vebhuk o'chirildi. So'rab turish uchun TELEGRAM_POLLING=true qiling.")


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0] == "info":
        info()
    elif args[0] == "set" and len(args) == 2:
        set_webhook(args[1])
    elif args[0] == "delete":
        delete_webhook()
    else:
        sys.exit(__doc__)
