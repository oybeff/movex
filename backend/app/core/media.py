"""
Yuklangan fayllar: qayerda yotadi va qanday manzilda beriladi.

Bitta joyda turadi, chunki ilgari yo'l ikki xil edi: equipment.py fayllarni
"media/equipment" ga yozardi (JORIY KATALOGGA nisbatan — ya'ni serverni
qayerdan ishga tushirsang, o'sha yerga), main.py esa hech narsa bermasdi.
Natijada har bir yuklangan rasm ochilmas havola bo'lib qolardi.

Endi yo'l absolyut va manzil shu yerdan yasaladi.
"""
import os
import re
import uuid

from fastapi import HTTPException, UploadFile

# backend/media
MEDIA_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "media",
)

URL_PREFIX = "/static"

ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".heic"}
MAX_UPLOAD_BYTES = 8 * 1024 * 1024


def folder(name: str) -> str:
    path = os.path.join(MEDIA_ROOT, name)
    os.makedirs(path, exist_ok=True)
    return path


def save_upload(file: UploadFile, section: str) -> str:
    """
    Faylni saqlaydi va uni ochish uchun manzil qaytaradi.

    Nom SERVERDA yasaladi. Foydalanuvchi yuborgan nomni ishlatib bo'lmaydi:
    unda "../../.env" bo'lishi mumkin va fayl kerakli joydan tashqariga
    yozilardi.
    """
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(
            400,
            f"Rasm formati qo'llab-quvvatlanmaydi: {ext or '—'}. "
            f"Ruxsat etilgan: {', '.join(sorted(ALLOWED_EXTENSIONS))}",
        )

    data = file.file.read()
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(
            400, f"Rasm hajmi {MAX_UPLOAD_BYTES // (1024 * 1024)} MB dan oshmasin"
        )
    if not data:
        raise HTTPException(400, "Fayl bo'sh")

    name = f"{uuid.uuid4().hex}{ext}"
    with open(os.path.join(folder(section), name), "wb") as out:
        out.write(data)

    return f"{URL_PREFIX}/{section}/{name}"


_SAFE_URL = re.compile(r"^/static/[a-z]+/[A-Za-z0-9_.-]+$")


def is_own_media(url: str) -> bool:
    """Manzil shu serverdagi faylgami — o'chirishdan oldin tekshiriladi."""
    return bool(_SAFE_URL.match(url or ""))


def delete_by_url(url: str) -> None:
    if not is_own_media(url):
        return
    path = os.path.join(MEDIA_ROOT, url[len(URL_PREFIX) + 1:])
    if os.path.isfile(path):
        os.remove(path)
