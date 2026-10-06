"""
Rahmat (Multicard) to'lov shlyuzi — loyihadagi YAGONA to'lov integratsiyasi.

Hujjat: https://docs.multicard.uz/

Nega bittasi. Multicard chekaut sahifasida Payme, Click, Uzum, Anorbank,
Oson, Alif, Xazna, Beepul, Trastpay va karta orqali to'lash allaqachon bor.
Ilgari loyihada Click va Payme uchun O'Z integratsiyalari yozilgan edi —
ya'ni bir xil pul uchun uchta mustaqil hisoblash yo'li. Ular olib tashlandi.

Ish tartibi (balansni to'ldirish):

    1. POST /auth                     — 24 soatlik token, kesh bilan
    2. POST /payment/invoice          — invoys, javobda checkout_url va uuid
    3. odam checkout_url da to'laydi
    4. Multicard -> POST /balance/rahmat/callback   (muvaffaqiyatli to'lov)
       Multicard -> POST /balance/rahmat/webhook    (har bir holat o'zgarishi)
    5. GET /payment/{uuid}            — shubha bo'lsa haqiqatni shundan olamiz

Kartaga pul chiqarish (payouts):

    POST /payment/credit              — confirmable=false bo'lsa bir so'rovda
    GET  /payment/credit/{uuid}       — ERROR_UNKNOWN yoki timeout bo'lsa holat

MUHIM: Multicard summani TIYINDA oladi va qaytaradi, bizda esa so'mda
yuritiladi. O'girish faqat shu fayldagi ikki funksiya orqali bo'ladi
(`to_tiyin` / `to_sum`). Ikkinchi joyda `* 100` yozilsa, ertami-kechmi
bittasida nol adashadi va pul yuz barobar ko'p yoki kam yechiladi.
"""
from __future__ import annotations

import hashlib
import logging
import threading
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional

import requests

from app.core.config import settings

logger = logging.getLogger(__name__)

#: Multicard callback'lari faqat shu manzildan keladi. Hujjatda aytilgan:
#: imzoni tekshirish YOKI IP bo'yicha cheklash. Biz IKKALASINI ham
#: qilamiz — imzo asosiy, IP qo'shimcha to'siq (nginx real IP uzatmasa
#: tekshiruv o'chiriladi, shuning uchun u yolg'iz qolib qolmasligi kerak).
CALLBACK_SOURCE_IP = "195.158.26.90"

#: Multicard tranzaksiya holatlari (PaymentStatusEnum + hold).
STATUS_DRAFT = "draft"
STATUS_PROGRESS = "progress"
STATUS_BILLING = "billing"
STATUS_HOLD = "hold"
STATUS_SUCCESS = "success"
STATUS_ERROR = "error"
STATUS_REVERT = "revert"

#: Shlyuz holati -> bizning balance_transactions.status.
#: 'billing' va 'hold' ham kutish holati: pul hali bizga tegishli emas.
STATUS_MAP = {
    STATUS_DRAFT: "pending",
    STATUS_PROGRESS: "pending",
    STATUS_BILLING: "pending",
    STATUS_HOLD: "pending",
    STATUS_SUCCESS: "completed",
    STATUS_ERROR: "failed",
    STATUS_REVERT: "canceled",
}

#: Fiskal chek uchun standart qiymatlar. Sinov kassasining o'z
#: sozlamalaridan olingan (GET /payment/invoice javobidagi store.tax_*).
#: Haqiqiy ИКПУ tasnif.soliq.uz dan olinadi va ADMINKAGA yoziladi, kodga
#: emas: kod almashtirish uchun yangi versiya chiqarish kerak bo'lmasin.
DEFAULT_OFD_MXIK = "10204001001000000"
DEFAULT_OFD_PACKAGE_CODE = "1500169"
DEFAULT_OFD_VAT = 0

OFD_MXIK_KEY = "rahmat_ofd_mxik"
OFD_PACKAGE_CODE_KEY = "rahmat_ofd_package_code"
OFD_VAT_KEY = "rahmat_ofd_vat"


class RahmatError(Exception):
    """
    Shlyuz xatosi.

    `code` saqlanadi, chunki bitta kod alohida ma'noga ega:
    ERROR_UNKNOWN — natija NOMA'LUM, so'rovni qaytarish emas, holatni
    so'rab aniqlash kerak (hujjat shuni talab qiladi).
    """

    def __init__(self, code: str, details: str = "", status_code: Optional[int] = None):
        self.code = code or "ERROR_UNKNOWN"
        self.details = details or ""
        self.status_code = status_code
        super().__init__(f"{self.code}: {self.details}" if self.details else self.code)

    @property
    def is_unknown(self) -> bool:
        """Natijasi aniqlanmagan xato — holatni so'rab tekshirish kerak."""
        return self.code == "ERROR_UNKNOWN"


# --------------------------------------------------------------- summalar

def to_tiyin(amount_sum) -> int:
    """So'm -> tiyin. 12 500,50 so'm -> 1 250 050 tiyin."""
    value = Decimal(str(amount_sum)) * 100
    return int(value.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def to_sum(amount_tiyin) -> Decimal:
    """Tiyin -> so'm. Decimal qaytadi: float bilan tiyinlar yo'qoladi."""
    return (Decimal(str(amount_tiyin)) / 100).quantize(Decimal("0.01"))


# ------------------------------------------------------------------ token
#
# Token 24 soat yashaydi va hujjat uni keshlashni talab qiladi. Kesh
# PROTSESS ichida: uvicorn bir necha ishchi bilan ishlaydi, har biri o'zi
# uchun token oladi — bu normal, Multicard tokenni yagona qilib
# talab qilmaydi (Telegram polling bilan bo'lgan 409 muammosi bu yerda yo'q).

_token_lock = threading.Lock()
_token_value: Optional[str] = None
_token_expires_at: Optional[datetime] = None

#: Muddati tugashidan shu qadar oldin yangilaymiz: so'rov yo'lda
#: ketayotganda token o'lib qolmasligi kerak.
_TOKEN_RENEW_MARGIN = timedelta(minutes=5)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def reset_token_cache() -> None:
    """Keshni tozalash. 401 kelganda va testlarda ishlatiladi."""
    global _token_value, _token_expires_at
    with _token_lock:
        _token_value = None
        _token_expires_at = None


def _fetch_token() -> str:
    """POST /auth. Javob success/data bilan O'RALMAGAN — tekis JSON."""
    url = f"{settings.rahmat_base_url}/auth"
    try:
        response = requests.post(
            url,
            json={
                "application_id": settings.RAHMAT_APPLICATION_ID,
                "secret": settings.RAHMAT_SECRET,
            },
            timeout=settings.RAHMAT_TIMEOUT_SECONDS,
        )
    except requests.RequestException as exc:
        raise RahmatError("ERROR_NETWORK", f"Multicard javob bermadi: {exc}") from exc

    try:
        payload = response.json()
    except ValueError:
        raise RahmatError(
            "ERROR_BAD_RESPONSE",
            f"/auth JSON emas (HTTP {response.status_code})",
            response.status_code,
        )

    token = payload.get("token")
    if not token:
        error = payload.get("error") or {}
        raise RahmatError(
            error.get("code", "ERROR_AUTH"),
            error.get("details", "token olinmadi"),
            response.status_code,
        )

    global _token_value, _token_expires_at
    _token_value = token
    # Javobdagi "expiry" — "2026-09-30 14:06:16", mintaqasiz. Uni o'qiy
    # olmasak, 12 soatga ishonamiz: xato tomoni xavfsiz — tokenni
    # kerakdan ko'proq yangilaymiz, muddati o'tganini ishlatmaymiz.
    expiry = payload.get("expiry")
    parsed: Optional[datetime] = None
    if isinstance(expiry, str):
        try:
            parsed = datetime.strptime(expiry, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        except ValueError:
            parsed = None
    _token_expires_at = parsed or (_now() + timedelta(hours=12))
    return token


def _token() -> str:
    """Keshdagi token yoki yangisi."""
    with _token_lock:
        if (
            _token_value
            and _token_expires_at
            and _now() + _TOKEN_RENEW_MARGIN < _token_expires_at
        ):
            return _token_value
        return _fetch_token()


# --------------------------------------------------------------- so'rovlar

def _request(
    method: str,
    path: str,
    payload: Optional[Dict[str, Any]] = None,
    *,
    retry_on_401: bool = True,
) -> Dict[str, Any]:
    """
    Shlyuzga so'rov. Javobning `data` qismini qaytaradi.

    401 bir marta qaytariladi: token muddati tugagan bo'lishi mumkin, va
    bu haqiqiy xato emas — shunchaki yangi token olish kerak.
    """
    if not settings.rahmat_configured:
        raise RahmatError(
            "ERROR_NOT_CONFIGURED",
            "Rahmat kalitlari yoki ochiq callback manzili sozlanmagan",
        )

    url = f"{settings.rahmat_base_url}{path}"
    try:
        response = requests.request(
            method,
            url,
            json=payload if payload is not None else None,
            headers={
                "Authorization": f"Bearer {_token()}",
                "Content-Type": "application/json",
            },
            timeout=settings.RAHMAT_TIMEOUT_SECONDS,
        )
    except requests.Timeout as exc:
        # Timeout = natija NOMA'LUM. Aynan shuning uchun ERROR_UNKNOWN
        # qaytaramiz: chaqiruvchi so'rovni qaytarmasligi, holatni
        # so'rashi kerak.
        raise RahmatError("ERROR_UNKNOWN", f"{method} {path}: javob kutilmadi ({exc})") from exc
    except requests.RequestException as exc:
        raise RahmatError("ERROR_NETWORK", f"{method} {path}: {exc}") from exc

    if response.status_code == 401 and retry_on_401:
        reset_token_cache()
        return _request(method, path, payload, retry_on_401=False)

    try:
        body = response.json()
    except ValueError:
        raise RahmatError(
            "ERROR_BAD_RESPONSE",
            f"{method} {path}: JSON emas (HTTP {response.status_code})",
            response.status_code,
        )

    if not body.get("success"):
        error = body.get("error") or {}
        raise RahmatError(
            error.get("code", "ERROR_UNKNOWN"),
            error.get("details", f"HTTP {response.status_code}"),
            response.status_code,
        )

    data = body.get("data")
    return data if isinstance(data, dict) else {"data": data}


# ------------------------------------------------------------ fiskal chek

def _setting(db, key: str) -> Optional[str]:
    from app.models.app_settings import AppSettings

    row = db.query(AppSettings).filter(AppSettings.key == key).first()
    return None if row is None or row.value is None else str(row.value).strip() or None


def build_ofd(db, amount_sum, name: str) -> List[Dict[str, Any]]:
    """
    Bitta umumlashtirilgan chek satri.

    Bizda alohida tovar yo'q — balans to'ldirilmoqda, shuning uchun bir
    satr yetadi. ИКПУ va qadoq kodi adminkadagi sozlamadan olinadi:
    soliq ma'lumotnomasidagi kod o'zgarsa, kodni tahrirlash kerak
    bo'lmasligi uchun.
    """
    total = to_tiyin(amount_sum)
    vat_raw = _setting(db, OFD_VAT_KEY)
    try:
        vat = int(vat_raw) if vat_raw is not None else DEFAULT_OFD_VAT
    except (TypeError, ValueError):
        vat = DEFAULT_OFD_VAT

    return [
        {
            "qty": 1,
            "vat": vat,
            "price": total,
            "total": total,
            "mxik": _setting(db, OFD_MXIK_KEY) or DEFAULT_OFD_MXIK,
            "package_code": _setting(db, OFD_PACKAGE_CODE_KEY) or DEFAULT_OFD_PACKAGE_CODE,
            "name": name,
        }
    ]


# ----------------------------------------------------------------- invoys

def callback_url() -> str:
    return f"{settings.RAHMAT_CALLBACK_BASE_URL.rstrip('/')}/balance/rahmat/callback"


def create_invoice(
    *,
    invoice_id: str,
    amount_sum,
    lang: str = "uz",
    ofd: Optional[List[Dict[str, Any]]] = None,
    phone: Optional[str] = None,
    ttl_seconds: Optional[int] = None,
) -> Dict[str, Any]:
    """
    Invoys yaratadi. Javobda `uuid` va `checkout_url`.

    `invoice_id` — BIZNING tranzaksiya raqami. U callback imzosiga kiradi
    va callback'da qaytadi, ya'ni pulni qaysi tranzaksiyaga yozishni
    aynan shu belgilaydi.
    """
    body: Dict[str, Any] = {
        "store_id": settings.RAHMAT_STORE_ID,
        "amount": to_tiyin(amount_sum),
        "invoice_id": str(invoice_id),
        "lang": lang if lang in ("ru", "uz", "en") else "uz",
        "callback_url": callback_url(),
        "return_url": settings.RAHMAT_RETURN_URL,
        "return_error_url": settings.RAHMAT_RETURN_ERROR_URL,
    }
    if ofd:
        body["ofd"] = ofd
    if phone:
        # Hujjat 998XXXXXXXXX ko'rinishini talab qiladi — faqat raqamlar.
        digits = "".join(ch for ch in str(phone) if ch.isdigit())
        if len(digits) == 12:
            body["sms"] = digits
    if ttl_seconds:
        body["ttl"] = int(ttl_seconds)

    return _request("POST", "/payment/invoice", body)


# -------------------------------------------- to'g'ridan-to'g'ri to'lov tizimi
#
# `/payment/invoice` Multicard'ning UMUMIY sahifasini beradi: u yerda
# Payme, Click, Uzum va boshqalar tugma sifatida turadi, lekin bosganda
# o'sha ilova OCHILMAYDI — hammasi sahifaning o'z ichida bo'ladi.
#
# `/payment` esa boshqacha: `payment_system` beriladi va javobdagi
# `checkout_url` — aynan o'sha ilovaning havolasi (Universal/App Link).
# Telefonda bosilganda Payme, Click, Uzum, Alif ilovasi ochiladi; ilova
# o'rnatilmagan bo'lsa — o'sha tizimning sayti.
#
# 06.10.2026 da jangovar kassada hammasi tekshirildi va ishladi.

#: Ilovada tugma sifatida ko'rsatiladigan tizimlar.
#:
#: `sbp` ataylab YO'Q: u Rossiyaning Tezkor to'lovlar tizimi (qr.nspk.ru),
#: O'zbekistondagi odamda bunday ilova bo'lmaydi va tugma faqat chalg'itadi.
PAYMENT_SYSTEMS: List[str] = [
    "payme",
    "click",
    "uzum",
    "alif",
    "anorbank",
    "oson",
    "xazna",
    "beepul",
    "trastpay",
]

#: Tugmadagi nom. Tarjimaga qo'yilmadi: bular BRAND nomlari, ular
#: o'zbekchada ham, ruschada ham bir xil yoziladi.
PAYMENT_SYSTEM_TITLES: Dict[str, str] = {
    "payme": "Payme",
    "click": "Click",
    "uzum": "Uzum",
    "alif": "Alif",
    "anorbank": "Anorbank",
    "oson": "Oson",
    "xazna": "Xazna",
    "beepul": "Beepul",
    "trastpay": "Trastpay",
}


def return_url_for_app() -> str:
    """
    To'lovdan keyin qaytish manzili.

    `/payment` endpointi ilova sxemasini (`movexgo://`) QABUL QILMAYDI —
    "Значение «Return Url» не является правильным URL" deb rad etadi.
    Shuning uchun oraliq sahifa: u brauzerda ochiladi va darhol ilovaga
    qaytaradi.
    """
    base = settings.RAHMAT_CALLBACK_BASE_URL.rstrip("/")
    return f"{base}/static/pay/done.html"


def create_direct_payment(
    *,
    payment_system: str,
    invoice_id: str,
    amount_sum,
    ofd: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """
    Tanlangan to'lov tizimi uchun to'lov yaratadi.

    Javobda `uuid` va `checkout_url` — o'sha ilovaning havolasi.
    Qolgan hammasi invoys bilan bir xil: callback ham, imzo ham, holatlar
    ham. Ya'ni pul yo'li o'zgarmaydi, faqat odam qayerda to'lashi
    o'zgaradi.
    """
    if payment_system not in PAYMENT_SYSTEMS:
        raise RahmatError("ERROR_FIELDS", f"noma'lum to'lov tizimi: {payment_system}")

    body: Dict[str, Any] = {
        "payment_system": payment_system,
        # Bu endpoint store_id ni SON sifatida kutadi (invoysda satr ham
        # ishlaydi), shuning uchun aniq o'tkazamiz.
        "store_id": int(settings.RAHMAT_STORE_ID),
        "amount": to_tiyin(amount_sum),
        "invoice_id": str(invoice_id),
        "callback_url": callback_url(),
        "return_url": return_url_for_app(),
    }
    if ofd:
        body["ofd"] = ofd

    return _request("POST", "/payment", body)


def get_invoice(uuid: str) -> Dict[str, Any]:
    return _request("GET", f"/payment/invoice/{uuid}")


def cancel_invoice(uuid: str) -> Dict[str, Any]:
    """To'lanmagan invoysni bekor qilish."""
    return _request("DELETE", f"/payment/invoice/{uuid}")


def get_payment(uuid: str) -> Dict[str, Any]:
    """Tranzaksiyaning HAQIQIY holati. Shubha bo'lganda manba shu."""
    return _request("GET", f"/payment/{uuid}")


def refund(uuid: str) -> Dict[str, Any]:
    """To'lovni to'liq qaytarish."""
    return _request("DELETE", f"/payment/{uuid}")


def partial_refund(uuid: str, amount_sum) -> Dict[str, Any]:
    """Qismini qaytarish."""
    return _request("DELETE", f"/payment/{uuid}/partial", {"amount": to_tiyin(amount_sum)})


# ----------------------------------------------------------------- outlay

def create_payout(*, pan: str, amount_sum, invoice_id: str) -> Dict[str, Any]:
    """
    Kartaga pul o'tkazish (Uzcard/Humo), platforma depozitidan.

    `confirmable=false` — bir so'rovda o'tadi, OTP so'ralmaydi. Sinov
    stendida tekshirilgan: javobda darhol status=success keladi.
    """
    body = {
        "card": {"pan": "".join(ch for ch in str(pan) if ch.isdigit())},
        "amount": to_tiyin(amount_sum),
        "store_id": settings.RAHMAT_STORE_ID,
        "invoice_id": str(invoice_id),
        "confirmable": False,
    }
    return _request("POST", "/payment/credit", body)


def confirm_payout(uuid: str, otp: str) -> Dict[str, Any]:
    """OTP bilan tasdiqlash — confirmable=true bilan yaratilgan o'tkazma uchun."""
    return _request("PUT", f"/payment/credit/{uuid}", {"otp": str(otp)})


def get_payout(uuid: str) -> Dict[str, Any]:
    """O'tkazma holati. ERROR_UNKNOWN yoki timeoutdan keyin SHU so'raladi."""
    return _request("GET", f"/payment/credit/{uuid}")


def application_info() -> Dict[str, Any]:
    """Ilova ma'lumoti. `wallet_sum` — depozit qoldig'i, tiyinda."""
    return _request("GET", "/payment/application")


# ------------------------------------------------------------------ imzo
#
# Ikki xil callback bor va imzolari HAR XIL — hujjatda shunday:
#
#   muvaffaqiyatli to'lov:  md5({store_id}{invoice_id}{amount}{secret})
#   holat o'zgarishi:       sha1({uuid}{invoice_id}{amount}{secret})
#
# Vebhuk sahifasining matnida yana bir ko'rinish yozilgan
# (md5({uuid}{amount}{secret})), maydon tavsifida esa yuqoridagi sha1.
# Ikkisi ham qabul qilinadi: mos kelmagan imzo so'rovni RAD ETADI, ya'ni
# noto'g'ri tanlov "pul tushmadi" degan nosozlikka olib kelardi. Soxta
# so'rov uchun esa hech qanday yengillik yo'q — sir bo'lmasa, hech qaysi
# ko'rinish to'g'ri chiqmaydi.


def _digest(algorithm: str, raw: str) -> str:
    return hashlib.new(algorithm, raw.encode("utf-8")).hexdigest()


def _matches(candidates: List[str], sign: Optional[str]) -> bool:
    if not sign:
        return False
    given = str(sign).strip().lower()
    # Taqqoslash doimiy vaqtda: imzoni harf-harf tanlab olishning
    # iloji bo'lmasin.
    from hmac import compare_digest

    return any(compare_digest(given, candidate) for candidate in candidates)


def verify_callback_sign(*, store_id, invoice_id, amount_tiyin, sign: Optional[str]) -> bool:
    """Muvaffaqiyatli to'lov callback'ining imzosi."""
    secret = settings.RAHMAT_SECRET
    if not secret:
        return False
    raw = f"{store_id}{invoice_id}{amount_tiyin}{secret}"
    return _matches([_digest("md5", raw)], sign)


def verify_webhook_sign(*, uuid, invoice_id, amount_tiyin, sign: Optional[str]) -> bool:
    """Holat o'zgarishi haqidagi vebhuk imzosi — ikki ko'rinishi qabul qilinadi."""
    secret = settings.RAHMAT_SECRET
    if not secret:
        return False
    return _matches(
        [
            _digest("sha1", f"{uuid}{invoice_id}{amount_tiyin}{secret}"),
            _digest("md5", f"{uuid}{amount_tiyin}{secret}"),
        ],
        sign,
    )


def map_status(gateway_status: Optional[str]) -> Optional[str]:
    """Shlyuz holatini bizning tranzaksiya holatiga o'girish."""
    if not gateway_status:
        return None
    return STATUS_MAP.get(str(gateway_status).strip().lower())
