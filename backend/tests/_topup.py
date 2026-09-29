"""
Testlar uchun hisob to'ldirish yordamchisi.

Nega alohida fayl. To'lov tizimi orqali balansni to'ldirish OLTI testda
kerak bo'ladi (pul, komissiya, sovg'a, e'lonlar, pul yechish, xabarnomalar).
Ilgari har birida Click callback'ini yasaydigan o'ziga xos nusxa turardi —
ya'ni to'lov tizimi almashganda oltita joyni tuzatish kerak bo'ldi.
Aynan shu holat sodir bo'ldi.

Ish tartibi haqiqiy to'lov bilan bir xil:

    POST /balance/topup              — tranzaksiya 'pending', invoys ochiladi
    POST /balance/rahmat/callback    — Multicard nomidan, imzo bilan
    balans ortadi

Imzo: md5({store_id}{invoice_id}{amount_tiyin}{secret}) — hujjatdagi
ko'rinish. Sir .env dan o'qiladi, kodda takrorlanmaydi: ikkinchi nusxa
kalit almashganda jimgina eskirib qolardi.

MUHIM: bu yerda `/balance/topup` HAQIQATAN Multicard sinov stendiga
murojaat qiladi (invoys yaratiladi). Ya'ni testlar ishlashi uchun
RAHMAT_* kalitlari va RAHMAT_CALLBACK_BASE_URL to'ldirilgan bo'lishi
kerak. Sozlanmagan bo'lsa test aniq xabar bilan to'xtaydi, "nimadir
ishlamadi" degan tushunarsiz xato bermaydi.
"""
import hashlib
import os
import sys

import requests

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

API = "http://127.0.0.1:8000"

PAYMENT_METHOD = "rahmat"


def _settings():
    from app.core.config import settings

    return settings


def configured() -> bool:
    """Kalitlar va ochiq manzil bormi."""
    return bool(_settings().rahmat_configured)


def require_configured() -> None:
    if not configured():
        raise RuntimeError(
            "Rahmat sozlanmagan: backend/.env da RAHMAT_APPLICATION_ID, "
            "RAHMAT_SECRET, RAHMAT_STORE_ID va RAHMAT_CALLBACK_BASE_URL "
            "to'ldirilishi kerak"
        )


def to_tiyin(amount_sum) -> int:
    """So'm -> tiyin. Shlyuz faqat tiyinda ishlaydi."""
    from app.services.rahmat_service import to_tiyin as convert

    return convert(amount_sum)


def callback_sign(store_id, invoice_id, amount_tiyin: int) -> str:
    settings = _settings()
    raw = f"{store_id}{invoice_id}{amount_tiyin}{settings.RAHMAT_SECRET}"
    return hashlib.md5(raw.encode("utf-8")).hexdigest()


def webhook_sign(uuid, invoice_id, amount_tiyin: int) -> str:
    settings = _settings()
    raw = f"{uuid}{invoice_id}{amount_tiyin}{settings.RAHMAT_SECRET}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()


def start_topup(headers: dict, amount, api: str = API) -> dict:
    """Tranzaksiya yaratadi va shlyuzda invoys ochadi."""
    require_configured()
    response = requests.post(
        f"{api}/balance/topup",
        headers=headers,
        json={"amount": amount, "payment_method": PAYMENT_METHOD},
    )
    data = response.json()
    if response.status_code != 200 or "transaction_id" not in data:
        raise RuntimeError(f"to'ldirish arizasi yaratilmadi: {response.status_code} {data}")
    return data


def send_callback(transaction_id: int, amount, api: str = API, **extra) -> dict:
    """Multicard nomidan muvaffaqiyatli to'lov callback'i."""
    settings = _settings()
    amount_tiyin = to_tiyin(amount)
    payload = {
        "store_id": settings.RAHMAT_STORE_ID,
        "invoice_id": str(transaction_id),
        "amount": amount_tiyin,
        "billing_id": f"test-{transaction_id}",
        "payment_time": "2026-09-29 12:00:00",
        "phone": "998901110002",
        "card_pan": "860053******8829",
        "ps": "uzcard",
        "card_token": "test-token",
        "receipt_url": "https://example.invalid/check/test",
        "sign": callback_sign(settings.RAHMAT_STORE_ID, transaction_id, amount_tiyin),
    }
    payload.update(extra)
    return requests.post(f"{api}/balance/rahmat/callback", json=payload).json()


def send_webhook(uuid: str, transaction_id: int, amount, status: str, api: str = API) -> dict:
    """Holat o'zgarishi haqidagi vebhuk."""
    amount_tiyin = to_tiyin(amount)
    payload = {
        "uuid": uuid,
        "invoice_id": str(transaction_id),
        "amount": amount_tiyin,
        "status": status,
        "billing_id": f"test-{transaction_id}",
        "payment_time": "2026-09-29 12:00:00",
        "refund_time": None,
        "phone": "998901110002",
        "card_pan": "860053******8829",
        "ps": "uzcard",
        "card_token": "test-token",
        "receipt_url": None,
        "sign": webhook_sign(uuid, transaction_id, amount_tiyin),
    }
    return requests.post(f"{api}/balance/rahmat/webhook", json=payload).json()


def topup(headers: dict, amount, api: str = API) -> int:
    """
    To'liq yo'l: ariza -> callback -> balans ortdi.

    Tranzaksiya raqamini qaytaradi.
    """
    started = start_topup(headers, amount, api)
    transaction_id = started["transaction_id"]
    result = send_callback(transaction_id, started["amount"], api)
    if not result.get("success"):
        raise RuntimeError(f"callback qabul qilinmadi: {result}")
    return transaction_id
