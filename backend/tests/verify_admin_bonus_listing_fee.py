"""
Adminkadan sovg'a va e'lon joylash narxi.

Sovg'a (POST /balance/internal/bonus):
- maxfiy kalitsiz ishlamaydi;
- balans oshadi, lekin kartaga yechiladigan summa O'ZGARMAYDI (sovg'a);
- ikki marta bosilsa ikkinchisi rad etiladi;
- adminga berib bo'lmaydi.

E'lon narxi:
- 0 — bepul (standart);
- umumiy narx qo'yilsa: pul yetmasa 402 va e'lon YARATILMAYDI;
  yetsa — yechiladi, tranzaksiya 'listing_fee', daromad budget_reserves da;
- shaxsiy narx umumiydan ustun: 0 — bepul, boshqa summa — o'shancha;
- GET /listings/fee shu odam uchun to'g'ri narxni ko'rsatadi.

Test sozlamani o'zgartiradi va oxirida qaytaradi, yaratgan hisoblarini o'chiradi.
"""
import os
import sys
import time
from decimal import Decimal

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import otp_code  # noqa: E402

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND)

from sqlalchemy import text  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402

API = "http://127.0.0.1:8000"
SECRET = {"X-Admin-Secret": settings.ADMIN_INTERNAL_SECRET}

ok_count = fail_count = 0
created_ids, created_phones = [], []


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


def sql(q, **p):
    db = SessionLocal()
    try:
        r = db.execute(text(q), p)
        db.commit()
        try:
            return r.fetchall()
        except Exception:
            return None
    finally:
        db.close()


def register(role):
    phone = f"9989{int(time.time() * 1000) % 100000000:08d}"[:12]
    requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": otp_code(phone)})
    r = requests.post(f"{API}/auth/register",
                      json={"full_name": f"Sinov bonus {role}", "phone": phone, "role": role})
    body = r.json()
    created_ids.append(body["user_id"])
    created_phones.append(phone)
    time.sleep(0.01)
    return body["user_id"], {"Authorization": f"Bearer {body['access_token']}"}


def balance(hdr):
    return requests.get(f"{API}/balance/me", headers=hdr).json()


def set_fee(value):
    if value is None:
        sql("DELETE FROM app_settings WHERE key='listing_fee_amount'")
        return
    if sql("SELECT 1 FROM app_settings WHERE key='listing_fee_amount'"):
        sql("UPDATE app_settings SET value=to_jsonb(CAST(:v AS text)) WHERE key='listing_fee_amount'", v=str(value))
    else:
        sql("INSERT INTO app_settings (key, value) VALUES ('listing_fee_amount', to_jsonb(CAST(:v AS text)))",
            v=str(value))


def create_listing(hdr, title="Sinov e'lon narxi"):
    return requests.post(f"{API}/listings/", headers=hdr, json={"title": title, "description": "test"})


def main():
    head("1. Sovg'a: kalitsiz ishlamaydi")
    uid, hdr = register("client")
    r = requests.post(f"{API}/balance/internal/bonus", json={"user_id": uid, "amount": 30000})
    check("kalitsiz — 403/404", r.status_code in (403, 404), r.status_code)
    r = requests.post(f"{API}/balance/internal/bonus", headers={"X-Admin-Secret": "xato"},
                      json={"user_id": uid, "amount": 30000})
    check("noto'g'ri kalit — 403", r.status_code == 403, r.status_code)

    head("2. Sovg'a beriladi, lekin kartaga yechilmaydi")
    before = balance(hdr)
    r = requests.post(f"{API}/balance/internal/bonus", headers=SECRET,
                      json={"user_id": uid, "amount": 30000, "comment": "aksiya"})
    check("berildi — 200", r.status_code == 200, f"{r.status_code} {r.text}")
    after = balance(hdr)
    check("balans 30 000 ga oshdi",
          Decimal(str(after["balance"])) - Decimal(str(before["balance"])) == 30000, after)
    bonus = sql("SELECT bonus_balance FROM balances WHERE user_id=:u", u=uid)[0][0]
    check("hammasi sovg'a sifatida", Decimal(str(bonus)) == 30000, bonus)
    tx = sql("SELECT type, payment_method, description FROM balance_transactions "
             "WHERE user_id=:u ORDER BY id DESC LIMIT 1", u=uid)[0]
    check("tranzaksiya: bonus / admin", tx[0] == "bonus" and tx[1] == "admin", tx)
    check("izoh tarixda ko'rinadi", "aksiya" in (tx[2] or ""), tx)

    r = requests.post(f"{API}/balance/internal/bonus", headers=SECRET,
                      json={"user_id": uid, "amount": 30000})
    check("ikki marta bosilsa — 409", r.status_code == 409, r.status_code)

    admin_id = sql("SELECT id FROM users WHERE role='admin' LIMIT 1")[0][0]
    r = requests.post(f"{API}/balance/internal/bonus", headers=SECRET,
                      json={"user_id": admin_id, "amount": 1000})
    check("adminga — 400", r.status_code == 400, r.status_code)

    head("3. E'lon narxi: standart — bepul")
    set_fee(None)
    check("/listings/fee = 0", requests.get(f"{API}/listings/fee", headers=hdr).json()["amount"] == 0)
    r = create_listing(hdr)
    check("bepul e'lon joylandi", r.status_code == 200, f"{r.status_code} {r.text}")

    head("4. Umumiy narx: pul yetmasa — e'lon yo'q")
    set_fee(10000)
    poor_id, poor = register("client")
    check("/listings/fee = 10000", requests.get(f"{API}/listings/fee", headers=poor).json()["amount"] == 10000)
    count_before = sql("SELECT count(*) FROM listings WHERE client_id=:u", u=poor_id)[0][0]
    r = create_listing(poor)
    check("pul yo'q — 402", r.status_code == 402, f"{r.status_code} {r.text}")
    check("sabab tushunarli", "10 000" in r.text, r.text)
    count_after = sql("SELECT count(*) FROM listings WHERE client_id=:u", u=poor_id)[0][0]
    check("e'lon yaratilmadi", count_after == count_before, (count_before, count_after))

    head("5. Pul yetsa — yechiladi (sovg'a bilan ham)")
    bal0 = Decimal(str(balance(hdr)["balance"]))
    r = create_listing(hdr, "Pullik e'lon")
    check("joylandi — 200", r.status_code == 200, f"{r.status_code} {r.text}")
    listing_id = r.json().get("id")
    bal1 = Decimal(str(balance(hdr)["balance"]))
    check("balansdan 10 000 yechildi", bal0 - bal1 == 10000, (bal0, bal1))
    fee_tx = sql("SELECT amount FROM balance_transactions WHERE user_id=:u AND type='listing_fee'", u=uid)
    check("tranzaksiya 'listing_fee'", bool(fee_tx) and Decimal(str(fee_tx[-1][0])) == 10000, fee_tx)
    reserve = sql("SELECT amount FROM budget_reserves WHERE listing_id=:l", l=listing_id)
    check("daromad budget_reserves da", bool(reserve) and Decimal(str(reserve[0][0])) == 10000, reserve)

    head("6. Shaxsiy narx umumiydan ustun")
    sql("UPDATE users SET listing_fee_override=0 WHERE id=:u", u=poor_id)
    check("/listings/fee = 0 (bepul)", requests.get(f"{API}/listings/fee", headers=poor).json()["amount"] == 0)
    r = create_listing(poor, "Bepul odam")
    check("pul yo'q, lekin bepul — 200", r.status_code == 200, f"{r.status_code} {r.text}")

    sql("UPDATE users SET listing_fee_override=5000 WHERE id=:u", u=uid)
    bal0 = Decimal(str(balance(hdr)["balance"]))
    r = create_listing(hdr, "Shaxsiy narx")
    bal1 = Decimal(str(balance(hdr)["balance"]))
    check("shaxsiy narx 5 000 yechildi", r.status_code == 200 and bal0 - bal1 == 5000, (r.status_code, bal0, bal1))


def cleanup(saved_fee):
    db = SessionLocal()
    try:
        db.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM otp_verifications WHERE phone = ANY(:ps)"), {"ps": created_phones})
        db.commit()
    finally:
        db.close()
    set_fee(saved_fee)


if __name__ == "__main__":
    row = sql("SELECT value FROM app_settings WHERE key='listing_fee_amount'")
    saved = row[0][0] if row else None
    try:
        main()
    finally:
        cleanup(saved)
    print(f"\nNATIJA: {ok_count} OK, {fail_count} FAIL")
    sys.exit(1 if fail_count else 0)
