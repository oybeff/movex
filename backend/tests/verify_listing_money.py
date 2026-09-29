"""
E'lonlarda pul: muzlatish, hisob-kitob, ulush.

Qoida buyurtmalardagi bilan bir xil:

    tasdiqlash -> muallifning balansida summa MUZLAYDI
    yakunlash  -> summa muallifdan YECHILADI, ijrochiga ulush ayirilib o'tadi
    rad etish / bekor qilish -> faqat muzlatish olib tashlanadi, pul qoladi

Eng muhim tekshiruvlar:
  * balansda pul bo'lmasa, tasdiqlab BO'LMAYDI (ilgari mumkin edi);
  * rad etishda pul muallifda qoladi — yo'qolmaydi va ko'paymaydi;
  * yakunlashda muallifdan chiqqan summa = ijrochiga tushgan + ulush.

Test IDEMPOTENT: o'z hisoblarini yaratadi va oxirida o'chiradi, stavkani
qaytaradi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_listing_money.py
"""
import os
import sys
import time
from datetime import datetime, timedelta
from decimal import Decimal

import requests

from _topup import topup as _rahmat_topup

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import otp_code  # noqa: E402

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND)

API = "http://127.0.0.1:8000"

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


def set_commission(mode, fixed=None, percent=None):
    from app.db.session import SessionLocal
    from app.models.app_settings import AppSettings

    db = SessionLocal()
    try:
        values = {"commission_mode": mode}
        if fixed is not None:
            values["commission_fixed"] = str(fixed)
        if percent is not None:
            values["commission_percent"] = str(percent)
        for key, value in values.items():
            row = db.query(AppSettings).filter(AppSettings.key == key).first()
            if row is None:
                db.add(AppSettings(key=key, value=value))
            else:
                row.value = value
        db.commit()
    finally:
        db.close()


def read_setting(key):
    from app.db.session import SessionLocal
    from app.models.app_settings import AppSettings

    db = SessionLocal()
    try:
        row = db.query(AppSettings).filter(AppSettings.key == key).first()
        return None if row is None else row.value
    finally:
        db.close()


def new_account(role="client"):
    phone = f"9989{(int(time.time() * 1000) + len(created_phones) * 7919) % 100000000:08d}"
    requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": otp_code(phone, API)})
    r = requests.post(f"{API}/auth/register",
                      json={"full_name": "Sinov", "phone": phone, "role": role})
    if r.status_code != 200:
        raise RuntimeError(f"ro'yxatdan o'tmadi {phone}: {r.status_code} {r.text}")
    created_phones.append(phone)
    login = requests.post(f"{API}/auth/verify-otp",
                          json={"phone": phone, "otp_code": otp_code(phone, API)}).json()
    return {"Authorization": f"Bearer {login['access_token']}"}


def topup(hdr, amount):
    """
    Hisob to'ldirish — Rahmat (Multicard) orqali.

    Mantiq _topup.py da: ilgari bu funksiya har bir testda o'z nusxasi
    bilan turardi va to'lov tizimi almashganda oltita joyni tuzatish
    kerak bo'ldi.
    """
    return _rahmat_topup(hdr, amount, API)


def balances(hdr):
    b = requests.get(f"{API}/balance/me", headers=hdr).json()
    return Decimal(str(b["balance"])), Decimal(str(b["frozen_balance"]))


def make_listing_raw(hdr, budget):
    """E'lon yaratish so'rovi — javobni qaytaradi (xato ham tekshiriladi)."""
    start = datetime.now() + timedelta(days=1)
    payload = {
        "title": "Sinov e'loni",
        "description": "pul tekshiruvi",
        "address": "Toshkent",
        "needed_from": start.strftime("%Y-%m-%d"),
        "needed_to": (start + timedelta(days=2)).strftime("%Y-%m-%d"),
        "contact_phone": "998901110002",
    }
    if budget is not None:
        payload["budget"] = str(budget)
    return requests.post(f"{API}/listings/", headers=hdr, json=payload)


def make_listing(hdr, budget):
    r = make_listing_raw(hdr, budget)
    if r.status_code not in (200, 201):
        raise RuntimeError(f"e'lon yaratilmadi: {r.status_code} {r.text}")
    return r.json()["id"]


def budget_rows(listing_id):
    from sqlalchemy import text
    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        return db.execute(
            text("SELECT amount FROM budget_reserves WHERE listing_id = :i"),
            {"i": listing_id},
        ).fetchall()
    finally:
        db.close()


def cleanup():
    from sqlalchemy import text
    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        if created_phones:
            db.execute(text("DELETE FROM users WHERE phone = ANY(:ps)"), {"ps": created_phones})
            db.execute(text("DELETE FROM otp_verifications WHERE phone = ANY(:ps)"),
                       {"ps": created_phones})
            db.commit()
    finally:
        db.close()


def main():
    saved_mode = read_setting("commission_mode")
    saved_fixed = read_setting("commission_fixed")

    try:
        set_commission("fixed", fixed=5000)
        author = new_account("client")
        taker = new_account("client")

        head("1. Balansda pul bo'lmasa — byudjetli e'lon JOYLAB bo'lmaydi")
        # Yangi qoida: byudjet e'lon joylanganda muzlatiladi. Puli yo'q odam
        # byudjetli e'lon joylay olmaydi — buyurtma va materiallardagi bilan
        # bir xil. Ilgari e'lon joylanardi, kimdir olardi, muallif esa
        # tasdiqlay olmasdi — ijrochi bekorga kutardi.
        r = make_listing_raw(author, 100000)
        check("nol balansda byudjetli e'lon rad etildi", r.status_code == 400,
              f"status={r.status_code} {r.text[:120]}")
        _, frozen = balances(author)
        check("hech narsa muzlatilmadi", frozen == 0, f"frozen={frozen}")

        head("2. Pul bor — JOYLANGANDA muzlaydi")
        topup(author, 200000)
        lid = make_listing(author, 100000)
        bal, frozen = balances(author)
        check("byudjet joylashda muzlatildi", frozen == Decimal("100000"), f"frozen={frozen}")
        check("balansdan yechilmadi", bal == Decimal("200000"), f"balans={bal}")

        # "olish" pulga tegmaydi, tasdiqlash ham qayta muzlatmaydi
        requests.post(f"{API}/listings/{lid}/take", headers=taker)
        _, frozen_after_take = balances(author)
        check("olishda muzlatish o'zgarmadi", frozen_after_take == Decimal("100000"),
              f"frozen={frozen_after_take}")
        r = requests.post(f"{API}/listings/{lid}/confirm", headers=author)
        check("tasdiqlandi", r.status_code == 200, f"status={r.status_code} {r.text[:120]}")
        bal, frozen = balances(author)
        check("tasdiqlashda qayta muzlatilmadi", frozen == Decimal("100000"), f"frozen={frozen}")

        head("3. Bekor qilishda pul muallifda qoladi")
        lid2 = make_listing(author, 50000)
        _, frozen_before = balances(author)
        requests.post(f"{API}/listings/{lid2}/cancel", headers=author)
        bal_after, frozen_after = balances(author)
        check("bekor qilishda muzlatish qaytdi",
              frozen_after == frozen_before - Decimal("50000"),
              f"{frozen_before} -> {frozen_after}")
        check("pul yo'qolmadi", bal_after == Decimal("200000"), f"balans={bal_after}")

        head("4. Yakunlashda pul ijrochiga o'tadi, ulush ushlanadi")
        taker_before, _ = balances(taker)
        r = requests.post(f"{API}/listings/{lid}/finish", headers=author)
        check("yakunlandi", r.status_code == 200, f"status={r.status_code} {r.text[:120]}")
        bal, frozen = balances(author)
        check("muallifdan 100 000 yechildi", bal == Decimal("100000"), f"balans={bal}")
        check("muzlatish tozalandi", frozen == 0, f"frozen={frozen}")

        taker_after, _ = balances(taker)
        check("ijrochiga 95 000 tushdi (100 000 - 5 000)",
              taker_after - taker_before == Decimal("95000"),
              f"farq={taker_after - taker_before}")

        rows = budget_rows(lid)
        check("ulush budjetga yozildi", len(rows) == 1 and Decimal(str(rows[0][0])) == Decimal("5000"),
              str(rows))

        head("5. Rad etishda pul band turadi (e'lon yana ochiq)")
        # reject_taker e'lonni "open" ga qaytaradi — byudjet band turishi
        # kerak, boshqa ijrochi olishi mumkin.
        topup(author, 100000)
        lid_r = make_listing(author, 60000)
        _, frozen_before = balances(author)
        requests.post(f"{API}/listings/{lid_r}/take", headers=taker)
        requests.post(f"{API}/listings/{lid_r}/reject", headers=author)
        _, frozen_after = balances(author)
        check("rad etishda muzlatish saqlanib qoldi",
              frozen_after == frozen_before, f"{frozen_before} -> {frozen_after}")
        requests.post(f"{API}/listings/{lid_r}/cancel", headers=author)  # tozalash

        head("6. Muddat tugaganda muzlatish qaytadi")
        # Byudjet joylashda muzlatiladi; e'lon olinmasdan muddati tugasa,
        # pul abadiy band bo'lib qolmasligi kerak. Muddatni bazadan
        # o'tmishga suramiz va lentani so'raganda expire_stale ishga tushadi.
        topup(author, 70000)
        lid_exp = make_listing(author, 70000)
        _, frozen_before = balances(author)
        from sqlalchemy import text as _text
        from app.db.session import SessionLocal as _Session
        db = _Session()
        try:
            db.execute(
                _text("UPDATE listings SET expires_at = NOW() - INTERVAL '1 day' WHERE id = :i"),
                {"i": lid_exp},
            )
            db.commit()
        finally:
            db.close()
        requests.get(f"{API}/listings/feed", headers=taker)   # expire_stale chaqiradi
        _, frozen_after = balances(author)
        check("muddat tugaganda muzlatish qaytdi",
              frozen_after == frozen_before - Decimal("70000"),
              f"{frozen_before} -> {frozen_after}")

        head("7. Foiz rejimi ham ishlaydi")
        set_commission("percent", percent=10)
        lid3 = make_listing(author, 100000)
        requests.post(f"{API}/listings/{lid3}/take", headers=taker)
        requests.post(f"{API}/listings/{lid3}/confirm", headers=author)
        taker_before, _ = balances(taker)
        requests.post(f"{API}/listings/{lid3}/finish", headers=author)
        taker_after, _ = balances(taker)
        check("foizda ijrochiga 90 000 tushdi",
              taker_after - taker_before == Decimal("90000"),
              f"farq={taker_after - taker_before}")
    finally:
        restore = {}
        if saved_mode is not None:
            restore["mode"] = saved_mode
        set_commission(saved_mode or "fixed",
                       fixed=saved_fixed if saved_fixed is not None else 5000)
        cleanup()

    print(f"\n{'=' * 66}\nITOG: {ok_count} o'tdi, {fail_count} yiqildi\n{'=' * 66}")
    return 1 if fail_count else 0


if __name__ == "__main__":
    sys.exit(main())
