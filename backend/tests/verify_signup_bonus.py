"""
Ro'yxatdan o'tganlik uchun sovg'a.

Qoida: sovg'a faqat TEXNIKA EGASIGA (role='owner') va 26.11.2026 dan
ro'yxatdan o'tganda EMAS, admin haydovchi hujjatlarini tasdiqlaganda
beriladi (bir marta). Mijoz hech narsa olmaydi.

Miqdor va yoqilganligi app_settings da — adminkadan boshqariladi. Shuning
uchun bu yerda ikkalasi ham tekshiriladi: yoqilganda beriladi, o'chirilganda
berilmaydi.

Test IDEMPOTENT: sozlamalarni o'zgartiradi, oxirida qaytaradi; yaratilgan
sinov hisoblarini o'zi o'chiradi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_signup_bonus.py
"""
import os
import sys
import time
from datetime import datetime
from decimal import Decimal

import requests

from _topup import topup as _rahmat_topup

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import otp_code  # noqa: E402

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND)

API = __import__("os").environ.get("API", "http://127.0.0.1:8000")

ok_count = 0
fail_count = 0
created_phones = []


def check(label, condition, detail=""):
    global ok_count, fail_count
    if condition:
        ok_count += 1
        print(f"  [OK]   {label}")
    else:
        fail_count += 1
        print(f"  [FAIL] {label}  {detail}")


def head(t):
    print(f"\n{'=' * 66}\n{t}\n{'=' * 66}")


def _settings(values: dict):
    from app.db.session import SessionLocal
    from app.models.app_settings import AppSettings

    db = SessionLocal()
    try:
        for key, value in values.items():
            row = db.query(AppSettings).filter(AppSettings.key == key).first()
            if row is None:
                db.add(AppSettings(key=key, value=value))
            else:
                row.value = value
        db.commit()
    finally:
        db.close()


def _read_setting(key):
    from app.db.session import SessionLocal
    from app.models.app_settings import AppSettings

    db = SessionLocal()
    try:
        row = db.query(AppSettings).filter(AppSettings.key == key).first()
        return None if row is None else row.value
    finally:
        db.close()


def _fresh_phone(tail: int) -> str:
    """Har safar yangi raqam: ro'yxatdan o'tish bir marta bo'ladi."""
    return f"9989{int(time.time()) % 100000000:08d}"[:9] + f"{tail:03d}"


def register(role: str) -> tuple:
    """Yangi hisob yaratadi va (telefon, sarlavha) qaytaradi."""
    phone = _fresh_phone(len(created_phones))
    code = otp_code(phone, API)
    requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": code})
    response = requests.post(
        f"{API}/auth/register",
        json={"full_name": f"Sinov {role}", "phone": phone, "role": role},
    )
    if response.status_code != 200:
        raise RuntimeError(f"ro'yxatdan o'tmadi {phone}: {response.status_code} {response.text}")
    created_phones.append(phone)

    login = requests.post(
        f"{API}/auth/verify-otp",
        json={"phone": phone, "otp_code": otp_code(phone, API)},
    ).json()
    return phone, {"Authorization": f"Bearer {login['access_token']}"}


import base64 as _b64
PNG = _b64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")
DOCS = ("id_front", "id_back", "license_front", "license_back", "tech_front", "tech_back",
        "car_front", "car_back", "car_left", "car_right")


def approve_docs(phone, hdr):
    """Haydovchi hujjatlarini yuklaydi va admin sifatida hammasini tasdiqlaydi."""
    from app.core.config import settings
    secret = {"X-Admin-Secret": settings.ADMIN_INTERNAL_SECRET}
    for kind in DOCS:
        requests.post(f"{API}/drivers/me/documents/{kind}", headers=hdr,
                      files={"file": ("doc.png", PNG, "image/png")})
    q = requests.get(f"{API}/drivers/internal/queue", headers=secret).json()
    uid = _user_id(phone)
    me = next(i for i in q if i["user_id"] == uid)
    for d in me["documents"]:
        requests.post(f"{API}/drivers/internal/documents/{d['id']}/review", headers=secret,
                      json={"approve": True})
    return uid


def _user_id(phone):
    from sqlalchemy import text
    from app.db.session import SessionLocal
    db = SessionLocal()
    try:
        return db.execute(text("SELECT id FROM users WHERE phone=:p"), {"p": phone}).scalar()
    finally:
        db.close()


def balance_of(hdr) -> Decimal:
    body = requests.get(f"{API}/balance/me", headers=hdr).json()
    return Decimal(str(body["balance"]))


def transactions_of(hdr):
    return requests.get(f"{API}/balance/transactions", headers=hdr).json()


def cleanup():
    """Sinov hisoblarini o'chiradi — baza toza qolsin."""
    from sqlalchemy import text
    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        for phone in created_phones:
            db.execute(text("DELETE FROM users WHERE phone = :p"), {"p": phone})
        db.execute(
            text("DELETE FROM otp_verifications WHERE phone = ANY(:ps)"),
            {"ps": created_phones},
        )
        db.commit()
    finally:
        db.close()



def topup(hdr, amount):
    """
    Hisob to'ldirish — Rahmat (Multicard) orqali.

    Mantiq _topup.py da: ilgari bu funksiya har bir testda o'z nusxasi
    bilan turardi va to'lov tizimi almashganda oltita joyni tuzatish
    kerak bo'ldi.
    """
    return _rahmat_topup(hdr, amount, API)


def payout_settings(hdr):
    return requests.get(f"{API}/payouts/settings", headers=hdr).json()


def request_payout(hdr, amount):
    return requests.post(f"{API}/payouts/", headers=hdr, json={
        "amount": str(amount),
        "card_number": "8600123412341234",
        "card_holder": "SINOV",
    })


def raw_balance(phone):
    from sqlalchemy import text
    from app.db.session import SessionLocal
    db = SessionLocal()
    try:
        return db.execute(text("""
            SELECT b.balance, b.frozen_balance, b.bonus_balance
              FROM balances b JOIN users u ON u.id = b.user_id
             WHERE u.phone = :p
        """), {"p": phone}).fetchone()
    finally:
        db.close()


def main():
    saved_enabled = _read_setting("signup_bonus_enabled")
    saved_amount = _read_setting("signup_bonus_amount")

    try:
        head("Sovg'a yoqilganda: texnika egasi oladi, mijoz olmaydi")
        _settings({"signup_bonus_enabled": "1", "signup_bonus_amount": "50000"})

        phone1, owner = register("owner")
        check("ro'yxatdan o'tganda sovg'a YO'Q (tekshiruvgacha)",
              balance_of(owner) == Decimal("0"), f"balans={balance_of(owner)}")
        approve_docs(phone1, owner)
        owner_balance = balance_of(owner)
        check(
            "hujjatlar tasdiqlangach balansga 50 000 tushdi",
            owner_balance == Decimal("50000"),
            f"balans={owner_balance}",
        )

        txs = transactions_of(owner)
        bonus_txs = [t for t in txs if t.get("type") == "bonus"]
        check("sovg'a 'bonus' turi bilan yozildi", len(bonus_txs) == 1, f"topildi={len(bonus_txs)}")
        if bonus_txs:
            check(
                "sovg'a tranzaksiyasi yakunlangan holatda",
                bonus_txs[0].get("status") == "completed",
                str(bonus_txs[0].get("status")),
            )
            check(
                "izoh xom kalit emas",
                "tx." not in str(bonus_txs[0].get("description") or ""),
                str(bonus_txs[0].get("description")),
            )

        _, client = register("client")
        client_balance = balance_of(client)
        check("mijozga sovg'a berilmadi", client_balance == Decimal("0"), f"balans={client_balance}")

        head("Adminkadan boshqarish")
        _settings({"signup_bonus_amount": "25000"})
        phone2, owner2 = register("owner")
        approve_docs(phone2, owner2)
        check(
            "summa sozlamadan olinadi (25 000)",
            balance_of(owner2) == Decimal("25000"),
            f"balans={balance_of(owner2)}",
        )

        _settings({"signup_bonus_enabled": "0"})
        phone3, owner3 = register("owner")
        approve_docs(phone3, owner3)
        check(
            "o'chirilganda sovg'a berilmaydi",
            balance_of(owner3) == Decimal("0"),
            f"balans={balance_of(owner3)}",
        )

        head("Qayta tasdiqlash ikkinchi sovg'a bermaydi")
        _settings({"signup_bonus_enabled": "1", "signup_bonus_amount": "50000"})
        from sqlalchemy import text as _t
        from app.db.session import SessionLocal as _S
        _db = _S()
        _db.execute(_t("UPDATE driver_documents SET status='pending' WHERE user_id=:u AND kind='tech_front'"),
                    {"u": _user_id(phone1)})
        _db.commit(); _db.close()
        approve_docs(phone1, owner)
        check("qayta tasdiqdan keyin ham 50 000 (ikki marta emas)",
              balance_of(owner) == Decimal("50000"), f"balans={balance_of(owner)}")

        head("Sovg'ani KARTAGA yechib bo'lmaydi")
        _settings({"signup_bonus_enabled": "1", "signup_bonus_amount": "50000"})
        phone4, owner4 = register("owner")
        approve_docs(phone4, owner4)

        row = raw_balance(phone4)
        check("sovg'a alohida belgilandi",
              row is not None and Decimal(str(row[2])) == Decimal("50000"),
              f"bonus_balance={row[2] if row else None}")

        body = requests.get(f"{API}/balance/me", headers=owner4).json()
        check("server sovg'a miqdorini ilovaga aytadi",
              Decimal(str(body.get("bonus_balance", 0))) == Decimal("50000"),
              str(body.get("bonus_balance")))

        # Eng kam yechish summasi 50 000, shuning uchun aynan shuni so'raymiz:
        # kichikroq summa boshqa sababdan rad etilardi va tekshiruv aldardi.
        r = request_payout(owner4, 50000)
        check("sovg'ani yechish RAD ETILDI", r.status_code == 400,
              f"status={r.status_code} {r.text[:160]}")
        check("sabab tushunarli aytilgan",
              "sovg" in r.text.lower() or "yechilmaydi" in r.text.lower(),
              r.text[:160])

        head("O'z puli yechiladi, sovg'a esa qoladi")
        topup(owner4, 60000)
        r = request_payout(owner4, 60000)
        check("o'z puli yechildi", r.status_code in (200, 201),
              f"status={r.status_code} {r.text[:160]}")

        head("Sarflaganda avval O'Z puli ketadi")
        phone5, owner5 = register("owner")
        topup(owner5, 70000)
        # 120 000 bor: 50 000 sovg'a + 70 000 o'z puli.
        r = request_payout(owner5, 70000)
        check("o'z 70 000 yechishga ruxsat", r.status_code in (200, 201),
              f"status={r.status_code} {r.text[:160]}")
        r = request_payout(owner5, 50000)
        check("qolgan sovg'adan yechib bo'lmaydi", r.status_code == 400,
              f"status={r.status_code} {r.text[:160]}")
    finally:
        restore = {}
        if saved_enabled is not None:
            restore["signup_bonus_enabled"] = saved_enabled
        if saved_amount is not None:
            restore["signup_bonus_amount"] = saved_amount
        if restore:
            _settings(restore)
        cleanup()

    print(f"\n{'=' * 66}\nITOG: {ok_count} o'tdi, {fail_count} yiqildi\n{'=' * 66}")
    return 1 if fail_count else 0


if __name__ == "__main__":
    sys.exit(main())
