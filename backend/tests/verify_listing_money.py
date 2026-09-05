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
import hashlib
import os
import sys
import time
from datetime import datetime, timedelta
from decimal import Decimal

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import otp_code  # noqa: E402

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND)

API = "http://127.0.0.1:8000"
CLICK_SERVICE_ID = "111111"
CLICK_SECRET_KEY = "local_dev_click_secret"

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


def topup(hdr, amount, click_id):
    tx = requests.post(f"{API}/balance/topup", headers=hdr,
                       json={"amount": amount, "payment_method": "click"}).json()
    tx_id, amt = tx["transaction_id"], float(tx["amount"])

    def cb(path, action, extra=None):
        st = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        raw = f"{click_id}{CLICK_SERVICE_ID}{CLICK_SECRET_KEY}{tx_id}{amt}{action}{st}"
        body = {"click_trans_id": click_id, "service_id": CLICK_SERVICE_ID,
                "merchant_trans_id": tx_id, "amount": amt, "action": action,
                "error": 0, "error_note": "Success", "sign_time": st,
                "sign_string": hashlib.md5(raw.encode()).hexdigest()}
        if extra:
            body.update(extra)
        return requests.post(f"{API}/balance/{path}", data=body).json()

    prep = cb("click/prepare", 0)
    cb("click/complete", 1, {"merchant_prepare_id": prep.get("merchant_prepare_id", tx_id)})


def balances(hdr):
    b = requests.get(f"{API}/balance/me", headers=hdr).json()
    return Decimal(str(b["balance"])), Decimal(str(b["frozen_balance"]))


def make_listing(hdr, budget):
    start = datetime.now() + timedelta(days=1)
    r = requests.post(f"{API}/listings/", headers=hdr, json={
        "title": "Sinov e'loni",
        "description": "pul tekshiruvi",
        "budget": str(budget),
        "address": "Toshkent",
        "needed_from": start.strftime("%Y-%m-%d"),
        "needed_to": (start + timedelta(days=2)).strftime("%Y-%m-%d"),
        "contact_phone": "998901110002",
    })
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

        head("1. Balansda pul bo'lmasa — tasdiqlab bo'lmaydi")
        lid = make_listing(author, 100000)
        requests.post(f"{API}/listings/{lid}/take", headers=taker)
        r = requests.post(f"{API}/listings/{lid}/confirm", headers=author)
        check("nol balansda tasdiqlash rad etildi", r.status_code == 400,
              f"status={r.status_code} {r.text[:120]}")
        bal, frozen = balances(author)
        check("hech narsa muzlatilmadi", frozen == 0, f"frozen={frozen}")

        head("2. Pul bor — tasdiqlashda muzlaydi")
        topup(author, 200000, 940000 + int(time.time()) % 10000)
        r = requests.post(f"{API}/listings/{lid}/confirm", headers=author)
        check("tasdiqlandi", r.status_code == 200, f"status={r.status_code} {r.text[:120]}")
        bal, frozen = balances(author)
        check("byudjet muzlatildi", frozen == Decimal("100000"), f"frozen={frozen}")
        check("balans o'zgarmadi", bal == Decimal("200000"), f"balans={bal}")

        head("3. Rad etishda pul muallifda qoladi")
        # rad etish faqat "taken" holatida — avval yangi e'lon bilan tekshiramiz
        lid2 = make_listing(author, 50000)
        requests.post(f"{API}/listings/{lid2}/take", headers=taker)
        requests.post(f"{API}/listings/{lid2}/confirm", headers=author)
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

        head("5. Foiz rejimi ham ishlaydi")
        set_commission("percent", percent=10)
        lid3 = make_listing(author, 100000)
        requests.post(f"{API}/listings/{lid3}/take", headers=taker)
        topup(author, 100000, 950000 + int(time.time()) % 10000)
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
