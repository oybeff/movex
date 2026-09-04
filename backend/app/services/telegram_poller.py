"""
Botdan yangiliklarni so'rab turuvchi fon vazifasi.

Nega vebhuk emas. Vebhukka OCHIQ HTTPS manzil kerak, ya'ni ishlaydigan
domen va sertifikat. Loyihada prod hali ko'tarilmagan, sinovlar esa
vaqtinchalik tunnellar orqali ketadi va ular kuniga bir necha marta
o'ladi — har safar Telegramda vebhukni qayta ro'yxatdan o'tkazish kerak
bo'lardi.

getUpdates esa hech qanday manzilni talab qilmaydi: server o'zi so'raydi.
Prod ko'tarilgach vebhukka o'tish bir necha satrlik ish.

Vazifa ilova ishga tushganda boshlanadi va TELEGRAM_POLLING bilan
o'chiriladi — masalan testlarda yoki ikkinchi nusxada: bitta botni ikki
joydan so'rash mumkin emas, Telegram 409 qaytaradi.
"""
import asyncio
import logging

import httpx

from app.core.config import settings
from app.db.session import SessionLocal
from app.services import telegram_auth_service as tg

logger = logging.getLogger(__name__)

#: Uzun so'rov: Telegram javobni yangilik kelguncha ushlab turadi
LONG_POLL_TIMEOUT = 25

_task: asyncio.Task | None = None


async def _loop() -> None:
    offset = 0
    logger.info("Telegram: yangiliklarni so'rash boshlandi")

    while True:
        try:
            async with httpx.AsyncClient(timeout=LONG_POLL_TIMEOUT + 10) as client:
                response = await client.get(
                    tg._url("getUpdates"),
                    params={
                        "offset": offset,
                        "timeout": LONG_POLL_TIMEOUT,
                        # Faqat kerakli turdagi yangiliklar — qolganini
                        # so'rab, keyin tashlab yuborishning ma'nosi yo'q
                        "allowed_updates": '["message"]',
                    },
                )
                data = response.json()

            if not data.get("ok"):
                logger.warning("Telegram getUpdates: %s", data.get("description"))
                await asyncio.sleep(5)
                continue

            for update in data.get("result", []):
                offset = update["update_id"] + 1

                # Har bir yangilik uchun alohida sessiya: bittasi xato
                # bersa, qolganlari ishlashda davom etsin.
                db = SessionLocal()
                try:
                    await tg.handle_update(db, update)
                except Exception as exc:  # noqa: BLE001
                    logger.exception("Telegram yangiligi qayta ishlanmadi: %s", exc)
                    db.rollback()
                finally:
                    db.close()

        except asyncio.CancelledError:
            logger.info("Telegram: so'rash to'xtatildi")
            raise
        except Exception as exc:  # noqa: BLE001 — tarmoq uzilishi tabiiy
            logger.warning("Telegram: so'rashda uzilish, qayta urinamiz: %s", exc)
            await asyncio.sleep(5)


def start() -> None:
    global _task
    if not settings.TELEGRAM_POLLING:
        return
    if not tg.is_configured():
        logger.warning("TELEGRAM_POLLING yoqilgan, lekin bot tokeni yo'q")
        return
    if _task is not None and not _task.done():
        return
    _task = asyncio.create_task(_loop())


async def stop() -> None:
    global _task
    if _task is None:
        return
    _task.cancel()
    try:
        await _task
    except asyncio.CancelledError:
        pass
    _task = None
