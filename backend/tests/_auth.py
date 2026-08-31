"""
Testlar uchun kirish yordamchisi.

Nega alohida fayl. Test rejimida OTP kodi javobda keladi va testlar shundan
foydalanadi. Lekin ADMIN uchun server kodni ataylab bermaydi: server
tashqaridan ochilganda (tunnel, demo stend, sinov serveri) telefon raqami
ma'lum bo'lgan admin hisobini istalgan odam olib qo'ya olardi — kodni
so'rab, javobdan o'qib, token oladi.

Testlar shu mashinada, baza yonida ishlaydi, shuning uchun admin kodini
to'g'ridan-to'g'ri bazadan o'qiydi. Bu API'ni zaiflashtirmaydi: tashqaridan
bazaga kirish yo'q.
"""
import os
import re
import sys

import requests

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

API = "http://127.0.0.1:8000"


def _code_from_db(phone: str) -> str:
    from sqlalchemy import text

    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        code = db.execute(
            text(
                "SELECT otp_code FROM otp_verifications "
                "WHERE phone = :p AND is_verified = false "
                "ORDER BY id DESC LIMIT 1"
            ),
            {"p": phone},
        ).scalar()
    finally:
        db.close()

    if not code:
        raise RuntimeError(f"OTP kodi topilmadi: {phone}")
    return str(code)


def otp_code(phone: str, api: str = API) -> str:
    """Kodni javobdan, bo'lmasa bazadan oladi."""
    response = requests.post(f"{api}/auth/send-otp", json={"phone": phone})
    match = re.search(r"(\d{4})\s*$", response.json().get("message", ""))
    return match.group(1) if match else _code_from_db(phone)


def token(phone: str, api: str = API) -> dict:
    """Authorization sarlavhasi."""
    response = requests.post(
        f"{api}/auth/verify-otp",
        json={"phone": phone, "otp_code": otp_code(phone, api)},
    )
    data = response.json()
    if "access_token" not in data:
        raise RuntimeError(f"kirish bajarilmadi: {phone}: {data}")
    return {"Authorization": f"Bearer {data['access_token']}"}
