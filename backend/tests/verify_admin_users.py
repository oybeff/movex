"""
Admin P4 (24.11.2026): bloklash sababi va muddati bilan, xabar, hujjat muddati.

Tekshiriladi:
- /users/internal/* — sirsiz 403; admin hisobini bloklab bo'lmaydi;
  noma'lum sabab/muddat — 400;
- blok: token bilan ham 403 va X-Account-Blocked, matnda sabab; jurnalda
  yozuv; muddati o'tsa — keyingi so'rovda o'zi olinadi; doimiy — qoladi;
- blokdan chiqarish ishlaydi;
- faol buyurtma ro'yxati; «hozir bekor qilish» — buyurtma bekor, mijoz
  puli muzlatishdan chiqadi (yechilmaydi);
- «Xabar yuborish» — ilovada bildirishnoma (system);
- hujjat muddati: o'tgan sana bilan tasdiqlab bo'lmaydi; muddat va kim
  tekshirgani saqlanadi; muddat o'tsa — hujjat «rad etilgan (muddati
  o'tgan)», haydovchi buyurtma ololmaydi (403).
"""
import base64
import os
import sys
import time
from datetime import date, timedelta
from decimal import Decimal

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import otp_code  # noqa: E402

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND)

from sqlalchemy import text  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402

API = os.environ.get("API", "http://127.0.0.1:8000")
SECRET = {"X-Admin-Secret": settings.ADMIN_INTERNAL_SECRET}
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")
ok_count = fail_count = 0
created_ids, created_phones = [], []
D = lambda x: Decimal(str(x))  # noqa: E731


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
    r = requests.post(f"{API}/auth/register", json={"full_name": f"Sinov Admin {role}", "phone": phone, "role": role})
    body = r.json()
    created_ids.append(body["user_id"])
    created_phones.append(phone)
    time.sleep(0.01)
    return body["user_id"], {"Authorization": f"Bearer {body['access_token']}"}


def money(uid):
    r = sql("SELECT balance, frozen_balance FROM balances WHERE user_id=:u", u=uid)
    return (D(r[0][0]), D(r[0][1])) if r else (D(0), D(0))


def set_money(uid, b):
    if sql("SELECT 1 FROM balances WHERE user_id=:u", u=uid):
        sql("UPDATE balances SET balance=:b, frozen_balance=0, bonus_balance=0 WHERE user_id=:u", b=b, u=uid)
    else:
        sql("INSERT INTO balances (user_id, balance, frozen_balance, bonus_balance) VALUES (:u,:b,0,0)", b=b, u=uid)


def admin_id():
    return sql("SELECT id FROM users WHERE role='admin' ORDER BY id LIMIT 1")[0][0]


def main():
    adm = admin_id()
    cid, client = register("client")

    head("1. Himoya va tekshiruvlar")
    r = requests.post(f"{API}/users/internal/{cid}/block", json={"reason": "abuse", "duration": "24h"})
    check("sirsiz — rad", r.status_code in (401, 403, 404), r.status_code)
    r = requests.post(f"{API}/users/internal/{adm}/block", headers=SECRET,
                      json={"admin_id": adm, "reason": "abuse", "duration": "24h"})
    check("admin hisobini bloklab bo'lmaydi", r.status_code == 400, r.status_code)
    r = requests.post(f"{API}/users/internal/{cid}/block", headers=SECRET,
                      json={"admin_id": adm, "reason": "xyz", "duration": "24h"})
    check("noma'lum sabab — 400", r.status_code == 400, r.status_code)
    r = requests.post(f"{API}/users/internal/{cid}/block", headers=SECRET,
                      json={"admin_id": adm, "reason": "abuse", "duration": "1y"})
    check("noma'lum muddat — 400", r.status_code == 400, r.status_code)

    head("2. Muddatli blok")
    r = requests.post(f"{API}/users/internal/{cid}/block", headers=SECRET, json={
        "admin_id": adm, "reason": "abuse", "duration": "7d", "note": "ichki izoh"})
    # SMS bu yerda YUBORILMAYDI: sinov raqami tasodifiy — haqiqiy odamga ketishi mumkin.
    check("bloklandi", r.status_code == 200, r.text[:200])
    if r.status_code == 200:
        check("SMS so'ralmagan — yuborilmadi", r.json().get("sms") is None, r.json())
    me = requests.get(f"{API}/users/me", headers=client)
    check("token bilan ham 403", me.status_code == 403, me.status_code)
    check("X-Account-Blocked sarlavhasi", me.headers.get("X-Account-Blocked") == "1")
    check("matnda sabab, ichki izoh yo'q", "Haqoratli" in me.text and "ichki izoh" not in me.text, me.text[:200])
    row = sql("SELECT blocked_by, block_reason_code, block_note, blocked_until IS NOT NULL FROM users WHERE id=:u", u=cid)[0]
    check("kim, sabab, izoh, muddat saqlandi", row[0] == adm and row[1] == "abuse" and row[2] == "ichki izoh" and row[3], row)
    log = sql("SELECT COUNT(*) FROM admin_actions WHERE action='user_block' AND entity='user' AND entity_id=:u", u=cid)[0][0]
    check("audit jurnalida yozuv", log == 1, log)

    sql("UPDATE users SET blocked_until = NOW() - INTERVAL '1 minute' WHERE id=:u", u=cid)
    me = requests.get(f"{API}/users/me", headers=client)
    check("muddat o'tdi — blok o'zi olindi", me.status_code == 200, f"{me.status_code} {me.text[:120]}")
    check("bazada ham olingan", sql("SELECT is_blocked FROM users WHERE id=:u", u=cid)[0][0] is False)

    head("3. Doimiy blok va blokdan chiqarish")
    requests.post(f"{API}/users/internal/{cid}/block", headers=SECRET,
                  json={"admin_id": adm, "reason": "fraud", "duration": "forever"})
    check("doimiy — blocked_until yo'q", sql("SELECT blocked_until FROM users WHERE id=:u", u=cid)[0][0] is None)
    check("doimiy — 403", requests.get(f"{API}/users/me", headers=client).status_code == 403)
    r = requests.post(f"{API}/users/internal/{cid}/unblock", headers=SECRET, json={"admin_id": adm})
    check("blokdan chiqarildi", r.status_code == 200 and requests.get(f"{API}/users/me", headers=client).status_code == 200)

    head("4. Faol buyurtma va «hozir bekor qilish»")
    saved = sql("SELECT base_fee, price_per_km, price_mode, has_body_choice FROM delivery_vehicles WHERE code='gazel'")[0]
    sql("UPDATE delivery_vehicles SET base_fee=30000, price_per_km=4000, price_mode='km', has_body_choice=true WHERE code='gazel'")
    try:
        set_money(cid, 1_000_000)
        r = requests.post(f"{API}/freight/orders", headers=client, json={
            "vehicle_code": "gazel", "body_type": "tent", "from_latitude": 41.30, "from_longitude": 69.24,
            "to_latitude": 41.35, "to_longitude": 69.30, "payment_method": "balance"})
        check("yuk buyurtmasi yaratildi", r.status_code == 200, r.text[:150])
        fid = r.json().get("id") if r.status_code == 200 else None
        frozen_before = money(cid)[1]
        act = requests.get(f"{API}/users/internal/{cid}/active-orders", headers=SECRET).json()
        check("faol buyurtma ro'yxatda (mijoz)", any(a["kind"] == "freight" and a["id"] == fid and a["role"] == "client"
                                                     for a in act), act)
        r = requests.post(f"{API}/users/internal/{cid}/block", headers=SECRET, json={
            "admin_id": adm, "reason": "fraud", "duration": "24h", "cancel_active": True})
        check("bloklandi va bekor qilindi", r.status_code == 200 and f"freight#{fid}" in r.json().get("cancelled", []),
              r.text[:200])
        st = sql("SELECT status FROM freight_orders WHERE id=:i", i=fid)[0][0]
        check("buyurtma bekor", st == "cancelled", st)
        bal, frozen = money(cid)
        check("pul muzlatishdan chiqdi, yechilmadi", frozen == 0 and bal == 1_000_000 and frozen_before > 0,
              f"{bal} {frozen} {frozen_before}")
        requests.post(f"{API}/users/internal/{cid}/unblock", headers=SECRET, json={"admin_id": adm})
    finally:
        sql("UPDATE delivery_vehicles SET base_fee=:a, price_per_km=:b, price_mode=:c, has_body_choice=:d WHERE code='gazel'",
            a=saved[0], b=saved[1], c=saved[2], d=saved[3])

    head("5. Xabar yuborish")
    r = requests.post(f"{API}/users/internal/{cid}/message", headers=SECRET,
                      json={"admin_id": adm, "text": "Salom, sinov xabari"})
    check("xabar yuborildi", r.status_code == 200, r.text[:150])
    n = sql("SELECT COUNT(*) FROM notifications WHERE user_id=:u AND type='system' AND body LIKE 'Salom, sinov%'", u=cid)[0][0]
    check("ilovada bildirishnoma bor", n == 1, n)

    head("6. Hujjat muddati")
    did, driver = register("owner")
    requests.post(f"{API}/drivers/me/documents/license_front", headers=driver, files={"file": ("a.png", PNG, "image/png")})
    doc = sql("SELECT id FROM driver_documents WHERE user_id=:u AND kind='license_front'", u=did)[0][0]
    r = requests.post(f"{API}/drivers/internal/documents/{doc}/review", headers=SECRET,
                      json={"approve": True, "expires_on": str(date.today() - timedelta(days=1)), "admin_id": adm})
    check("o'tgan muddat bilan tasdiqlab bo'lmaydi", r.status_code == 400, r.status_code)
    exp = date.today() + timedelta(days=20)
    r = requests.post(f"{API}/drivers/internal/documents/{doc}/review", headers=SECRET,
                      json={"approve": True, "expires_on": str(exp), "admin_id": adm})
    check("tasdiqlandi muddat bilan", r.status_code == 200 and r.json().get("expires_on") == str(exp), r.text[:150])
    row = sql("SELECT expires_on, reviewed_by FROM driver_documents WHERE id=:i", i=doc)[0]
    check("muddat va kim tekshirgani saqlandi", row[0] == exp and row[1] == adm, row)
    me = requests.get(f"{API}/drivers/me", headers=driver).json()
    d0 = next(d for d in me["documents"] if d["kind"] == "license_front")
    check("ilovaga muddat beriladi", d0.get("expires_on") == str(exp), d0)
    r = requests.post(f"{API}/drivers/freight/orders/999999999/accept", headers=driver)
    check("muddati bor hujjat bilan — tekshiruvdan o'tadi (404, 403 emas)", r.status_code != 403, r.status_code)

    sql("UPDATE driver_documents SET expires_on = CURRENT_DATE - 1 WHERE id=:i", i=doc)
    me = requests.get(f"{API}/drivers/me", headers=driver).json()
    d0 = next(d for d in me["documents"] if d["kind"] == "license_front")
    check("muddat o'tdi — hujjat rad etilgan, sababi «Muddati o'tgan»",
          d0["status"] == "rejected" and (d0.get("reject_reason") or "").startswith("Muddati o'tgan"), d0)
    r = requests.post(f"{API}/drivers/freight/orders/999999999/accept", headers=driver)
    check("muddati o'tgan — buyurtma olib bo'lmaydi (403)", r.status_code == 403, r.status_code)
    n = sql("SELECT COUNT(*) FROM notifications WHERE user_id=:u AND type='driver_document_rejected'", u=did)[0][0]
    check("haydovchiga xabar ketdi", n >= 1, n)
    _, plain_owner = register("owner")
    r = requests.post(f"{API}/drivers/freight/orders/999999999/accept", headers=plain_owner)
    check("hujjat topshirmagan ega bu tekshiruvga tushmaydi", r.status_code != 403, r.status_code)


def cleanup():
    db = SessionLocal()
    try:
        db.execute(text("DELETE FROM freight_orders WHERE client_id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM admin_actions WHERE entity='user' AND entity_id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM otp_verifications WHERE phone = ANY(:ps)"), {"ps": created_phones})
        db.commit()
    finally:
        db.close()


if __name__ == "__main__":
    try:
        main()
    finally:
        cleanup()
    print(f"\nITOG: {ok_count} o'tdi, {fail_count} yiqildi")
    sys.exit(1 if fail_count else 0)
