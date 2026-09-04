"""
Telegram orqali kirish.

NEGA SHUNDAY, VA BOSHQACHA QILIB BO'LMAYDI.

Telegram boti odamga birinchi bo'lib yoza olmaydi: bu Telegramning
qat'iy qoidasi, spamga qarshi. Va botda "telefon raqami bo'yicha
foydalanuvchini topish" degan imkoniyat umuman yo'q.

Shundan kelib chiqib, kirish ikki bosqichli:

  BIRINCHI MARTA — chuqur havola:
    ilova  → t.me/<bot>?start=<token>
    odam   → Start bosadi
    bot    → "Raqamingizni ulashing" tugmasi
    odam   → bosadi, Telegram O'ZI raqamni yuboradi
    server → raqam ↔ chat_id ni saqlaydi, kirishni tasdiqlaydi
    ilova  → kirdi

  KEYINGI MARTALAR — kod:
    bog'lanish saqlangan, shuning uchun kod to'g'ridan-to'g'ri
    Telegramga yuboriladi. Havola ham, SMS ham kerak emas.

Raqamni odam qo'lda yozmaydi — u Telegramning contact xabaridan keladi,
ya'ni Telegram tomonidan tasdiqlangan. Begona raqamni yozib yuborib
bo'lmaydi.

SMS zaxira bo'lib qoladi: Telegrami yo'q odam ham kira olishi kerak.
"""
import logging
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

import httpx
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.telegram import (
    LOGIN_REQUEST_TTL_MINUTES,
    TelegramAccount,
    TelegramLoginRequest,
)

logger = logging.getLogger(__name__)


class TelegramError(Exception):
    """Telegram so'rovni rad etdi. Matnida sabab."""

    @property
    def blocked(self) -> bool:
        """Bot bloklanganmi. Bunda bog'lanishni saqlashning ma'nosi yo'q."""
        text = str(self).lower()
        return "blocked by the user" in text or "user is deactivated" in text

API = "https://api.telegram.org"


def _now() -> datetime:
    return datetime.now(timezone.utc)


def is_configured() -> bool:
    return bool(settings.TELEGRAM_BOT_TOKEN)


def _url(method: str) -> str:
    return f"{API}/bot{settings.TELEGRAM_BOT_TOKEN}/{method}"


def normalize_phone(raw: Optional[str]) -> str:
    """+998 90 123-45-67 va 998901234567 — bitta raqam."""
    digits = "".join(ch for ch in (raw or "") if ch.isdigit())
    if len(digits) == 9:
        digits = "998" + digits
    return digits


# ------------------------------------------------------- havola orqali

def create_login_request(db: Session) -> dict:
    """
    Kirish havolasini yaratadi.

    Token tasodifiy va 10 daqiqa yashaydi: havola begonaga tushsa ham,
    u bilan boshqa hisobga kirib bo'lmaydi.
    """
    token = secrets.token_urlsafe(24)[:40]

    request = TelegramLoginRequest(
        token=token,
        status=TelegramLoginRequest.STATUS_PENDING,
        expires_at=_now() + timedelta(minutes=LOGIN_REQUEST_TTL_MINUTES),
    )
    db.add(request)
    db.commit()

    username = settings.TELEGRAM_BOT_USERNAME.lstrip("@")
    return {
        "token": token,
        "url": f"https://t.me/{username}?start={token}",
        "expires_in": LOGIN_REQUEST_TTL_MINUTES * 60,
    }


def check_login_request(db: Session, token: str) -> dict:
    """Ilova shu yerni so'rab turadi: tasdiqlandimi."""
    request = (
        db.query(TelegramLoginRequest)
        .filter(TelegramLoginRequest.token == token)
        .first()
    )
    if request is None:
        return {"status": "not_found"}

    if request.status == TelegramLoginRequest.STATUS_PENDING and request.expires_at < _now():
        return {"status": "expired"}

    return {
        "status": request.status,
        "phone": request.phone,
    }


def consume_login_request(db: Session, token: str) -> Optional[str]:
    """
    Tasdiqlangan so'rovni "ishlatilgan" deb belgilaydi va raqamni
    qaytaradi. Bir marta — takroriy chaqiruv hech narsa bermaydi.
    """
    request = (
        db.query(TelegramLoginRequest)
        .filter(
            TelegramLoginRequest.token == token,
            TelegramLoginRequest.status == TelegramLoginRequest.STATUS_CONFIRMED,
        )
        .with_for_update()
        .first()
    )
    if request is None:
        return None
    if request.expires_at < _now():
        return None

    request.status = TelegramLoginRequest.STATUS_USED
    db.commit()
    return request.phone


# --------------------------------------------------- bot bilan ishlash

async def _call(method: str, payload: dict) -> Optional[dict]:
    if not is_configured():
        return None
    try:
        async with httpx.AsyncClient(timeout=25) as client:
            response = await client.post(_url(method), json=payload)
            data = response.json()
            if not data.get("ok"):
                description = data.get("description") or ""
                logger.warning("Telegram %s xato: %s", method, description)
                # Sababni chaqiruvchiga yetkazamiz: "bot bloklangan" bilan
                # oddiy tarmoq xatosi bir xil emas, ular boshqacha
                # ishlov talab qiladi.
                raise TelegramError(description)
            return data.get("result")
    except Exception as exc:  # noqa: BLE001 — tarmoq xatosi kirishni buzmasin
        logger.error("Telegram %s uzildi: %s", method, exc)
        return None


async def send_message(chat_id: int, text: str, keyboard: Optional[dict] = None) -> bool:
    """Xato bo'lsa TelegramError ko'tariladi — sababi bilan."""
    payload = {"chat_id": chat_id, "text": text, "parse_mode": "HTML"}
    if keyboard is not None:
        payload["reply_markup"] = keyboard
    return await _call("sendMessage", payload) is not None



async def _notify(chat_id: int, text: str, keyboard: Optional[dict] = None) -> None:
    """
    Xabar yuborishga urinadi va xatoni yutadi.

    Yangiliklarni qayta ishlashda ishlatiladi: agar javob yuborilmasa
    ham, asosiy ish (raqamni bog'lash, kirishni tasdiqlash) bajarilishi
    kerak. Aks holda tarmoqdagi bir soniyalik uzilish odamni kirishdan
    mahrum qilardi.
    """
    try:
        await send_message(chat_id, text, keyboard)
    except TelegramError as exc:
        logger.warning("Telegramga javob yuborilmadi: %s", exc)


async def send_code(db: Session, phone: str, code: str, language: str = "uz") -> bool:
    """
    Kodni Telegramga yuboradi. Bog'lanish yo'q bo'lsa — False, va
    chaqiruvchi SMS ga o'tadi.
    """
    account = (
        db.query(TelegramAccount)
        .filter(TelegramAccount.phone == normalize_phone(phone))
        .first()
    )
    if account is None:
        return False

    if language == "ru":
        text = (f"<b>{code}</b> — код для входа в MoveX GO\n\n"
                f"Никому не сообщайте этот код.")
    else:
        text = (f"<b>{code}</b> — MoveX GO ga kirish kodi\n\n"
                f"Kodni hech kimga bermang.")

    try:
        return await send_message(account.chat_id, text)
    except TelegramError as exc:
        if exc.blocked:
            # Odam botni bloklagan yoki suhbatni o'chirgan. Bog'lanishni
            # SAQLAB QOLISH mumkin emas: har safar kod Telegramga
            # urinardi, muvaffaqiyatsiz bo'lardi va odam ilovaga hech
            # qachon kira olmasdi — SMS ham har doim yo'q.
            #
            # Bog'lanishni o'chirsak, ilova yana "Telegram orqali kirish"
            # tugmasini ko'rsatadi, odam botni qayta ishga tushiradi va
            # hammasi tiklanadi.
            logger.info("Telegram bloklangan, bog'lanish o'chirildi: %s", account.phone)
            db.delete(account)
            db.commit()
            return False
        logger.warning("Telegram kod yuborilmadi: %s", exc)
        return False


# ------------------------------------------------- yangiliklar oqimi

async def handle_update(db: Session, update: dict) -> None:
    """
    Botdan kelgan bitta yangilikni qayta ishlaydi.

    Ikki holat muhim: "/start <token>" va contact xabari.
    """
    message = update.get("message") or {}
    chat = message.get("chat") or {}
    chat_id = chat.get("id")
    if chat_id is None:
        return

    text = (message.get("text") or "").strip()
    contact = message.get("contact")

    # 1. Raqam ulashildi — asosiy hodisa
    if contact:
        await _handle_contact(db, chat_id, contact, message.get("from") or {})
        return

    # 2. Chuqur havoladan kirish: /start <token>
    if text.startswith("/start"):
        parts = text.split(maxsplit=1)
        token = parts[1].strip() if len(parts) > 1 else ""
        await _handle_start(db, chat_id, token, message.get("from") or {})
        return

    # 3. Boshqa hamma narsa — qisqa tushuntirish
    await _notify(
        chat_id,
        "Bu bot MoveX GO ga kirish uchun.\n"
        "Ilovada «Telegram orqali kirish» tugmasini bosing.",
    )


async def _handle_start(db: Session, chat_id: int, token: str, sender: dict) -> None:
    """Start bosildi. Token bo'lsa — raqam so'raymiz."""
    if not token:
        await _notify(
            chat_id,
            "Salom! Bu bot MoveX GO ilovasiga kirish uchun.\n"
            "Ilovadagi «Telegram orqali kirish» tugmasini bosing.",
        )
        return

    request = (
        db.query(TelegramLoginRequest)
        .filter(TelegramLoginRequest.token == token)
        .first()
    )
    if request is None or request.expires_at < _now():
        await _notify(
            chat_id,
            "Havolaning muddati o'tgan. Ilovada tugmani qayta bosing.",
        )
        return

    # Chat allaqachon bog'langan bo'lsa, raqamni qayta so'ramaymiz —
    # odam bir marta bergan, ikkinchi marta bezovta qilishning hojati yo'q.
    account = (
        db.query(TelegramAccount)
        .filter(TelegramAccount.chat_id == chat_id)
        .first()
    )
    if account is not None:
        request.phone = account.phone
        request.chat_id = chat_id
        request.status = TelegramLoginRequest.STATUS_CONFIRMED
        db.commit()
        await _notify(chat_id, "Kirish tasdiqlandi. Ilovaga qayting.")
        return

    request.chat_id = chat_id
    db.commit()

    await _notify(
        chat_id,
        "Kirishni tasdiqlash uchun telefon raqamingizni ulashing.\n\n"
        "Raqamni qo'lda yozish shart emas — pastdagi tugmani bosing.",
        keyboard={
            "keyboard": [[{
                "text": "📱 Raqamni ulashish",
                "request_contact": True,
            }]],
            "resize_keyboard": True,
            "one_time_keyboard": True,
        },
    )


async def _handle_contact(db: Session, chat_id: int, contact: dict, sender: dict) -> None:
    """
    Raqam keldi. Uni Telegramning O'ZI yuboradi, ya'ni tasdiqlangan.

    MUHIM: begona raqamni ulashishga yo'l qo'ymaymiz. Telegram contact
    xabarida user_id bo'ladi — u xabar yuboruvchiga teng bo'lsa, raqam
    o'ziniki. Aks holda odam boshqa birovning kontaktini yuborib, uning
    hisobiga kirib olardi.
    """
    contact_user_id = contact.get("user_id")
    sender_id = sender.get("id")
    if contact_user_id is None or sender_id is None or contact_user_id != sender_id:
        await _notify(
            chat_id,
            "Faqat O'Z raqamingizni ulashish mumkin. "
            "Tugmani bosing, raqamni qo'lda yubormang.",
        )
        return

    phone = normalize_phone(contact.get("phone_number"))
    if len(phone) != 12:
        await _notify(chat_id, "Raqam tanilmadi. Qayta urinib ko'ring.")
        return

    account = (
        db.query(TelegramAccount)
        .filter(TelegramAccount.chat_id == chat_id)
        .first()
    )
    if account is None:
        # Shu raqam boshqa chatga bog'langan bo'lishi mumkin — masalan
        # odam Telegram akkauntini almashtirgan. Bog'lanishni yangisiga
        # o'tkazamiz, aks holda u hech qachon kira olmaydi.
        account = (
            db.query(TelegramAccount)
            .filter(TelegramAccount.phone == phone)
            .first()
        )
        if account is None:
            account = TelegramAccount(chat_id=chat_id, phone=phone)
            db.add(account)
        else:
            account.chat_id = chat_id

    account.phone = phone
    account.username = sender.get("username")
    account.first_name = sender.get("first_name")

    # Shu chat uchun kutayotgan so'rovni tasdiqlaymiz
    request = (
        db.query(TelegramLoginRequest)
        .filter(
            TelegramLoginRequest.chat_id == chat_id,
            TelegramLoginRequest.status == TelegramLoginRequest.STATUS_PENDING,
        )
        .order_by(TelegramLoginRequest.id.desc())
        .first()
    )
    if request is not None and request.expires_at >= _now():
        request.phone = phone
        request.status = TelegramLoginRequest.STATUS_CONFIRMED

    db.commit()

    await _notify(
        chat_id,
        "Rahmat! Kirish tasdiqlandi — ilovaga qayting.\n\n"
        "Bundan keyin kirish kodi shu yerga keladi.",
        keyboard={"remove_keyboard": True},
    )
