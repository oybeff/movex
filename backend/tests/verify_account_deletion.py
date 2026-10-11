"""
Hisobni o'zi o'chirishi: DELETE /users/me.

Qoidalar:
- yechish mumkin bo'lgan pul, muzlatilgan summa yoki tugallanmagan
  bitim bo'lsa — 409, hech narsa o'zgarmaydi;
- faqat sovg'a qolgan bo'lsa — o'chiriladi (sovg'ani baribir yechib bo'lmaydi);
- o'chirish = anonimlashtirish: ism/telefon yo'qoladi, eski token shu
  zahoti ishlamaydi, texnika katalogdan olinadi, surat fayli diskdan
  o'chadi, ikkinchi tomonning buyurtmasi QOLADI;
- shu raqam bilan yangidan ro'yxatdan o'tish mumkin.

Test o'zi yaratgan hisob va yozuvlarni oxirida o'chiradi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_account_deletion.py
"""
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

from app.db.session import SessionLocal  # noqa: E402

API = "http://127.0.0.1:8000"

ok_count = 0
fail_count = 0
created_phones = []
created_user_ids = []


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


def sql(query, **params):
    db = SessionLocal()
    try:
        result = db.execute(text(query), params)
        db.commit()
        try:
            return result.fetchall()
        except Exception:
            return None
    finally:
        db.close()


def fresh_phone() -> str:
    return f"9989{int(time.time() * 1000) % 100000000:08d}"[:12]


def register(role: str, phone: str = None):
    phone = phone or fresh_phone()
    requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": otp_code(phone)})
    r = requests.post(
        f"{API}/auth/register",
        json={"full_name": f"Sinov o'chirish {role}", "phone": phone, "role": role},
    )
    if r.status_code != 200:
        raise RuntimeError(f"ro'yxatdan o'tmadi {phone}: {r.status_code} {r.text}")
    body = r.json()
    created_phones.append(phone)
    created_user_ids.append(body["user_id"])
    time.sleep(0.01)
    return phone, body["user_id"], {"Authorization": f"Bearer {body['access_token']}"}


def set_balance(user_id, balance, frozen=0, bonus=0):
    sql("UPDATE balances SET balance=:b, frozen_balance=:f, bonus_balance=:bo WHERE user_id=:u",
        b=balance, f=frozen, bo=bonus, u=user_id)
    if not sql("SELECT 1 FROM balances WHERE user_id=:u", u=user_id):
        sql("INSERT INTO balances (user_id, balance, frozen_balance, bonus_balance) "
            "VALUES (:u, :b, :f, :bo)", u=user_id, b=balance, f=frozen, bo=bonus)


def check_delete(hdr):
    return requests.get(f"{API}/users/me/deletion-check", headers=hdr).json()


def main():
    head("1. Mijoz: pul bor ekan — o'chirib bo'lmaydi")
    phone, uid, hdr = register("client")
    check("yangi hisobni o'chirish mumkin", check_delete(hdr).get("can_delete") is True,
          check_delete(hdr))

    set_balance(uid, 100000)
    c = check_delete(hdr)
    check("pul bor — can_delete=false", c.get("can_delete") is False, c)
    r = requests.delete(f"{API}/users/me", headers=hdr)
    check("pul bor — DELETE 409", r.status_code == 409, f"{r.status_code} {r.text}")
    check("javobda sabab yozilgan", "kartaga" in r.text or "карту" in r.text, r.text)
    alive = requests.get(f"{API}/users/me", headers=hdr)
    check("rad etilgandan keyin hisob ishlayapti", alive.status_code == 200)

    set_balance(uid, 50000, frozen=50000)
    r = requests.delete(f"{API}/users/me", headers=hdr)
    check("muzlatilgan summa — 409", r.status_code == 409, f"{r.status_code} {r.text}")

    head("2. Faqat sovg'a qolgan — o'chiriladi")
    set_balance(uid, 50000, frozen=0, bonus=50000)
    c = check_delete(hdr)
    check("sovg'a o'chirishga to'sqinlik qilmaydi", c.get("can_delete") is True, c)
    r = requests.delete(f"{API}/users/me", headers=hdr)
    check("DELETE 200", r.status_code == 200, f"{r.status_code} {r.text}")
    row = sql("SELECT full_name, phone, is_blocked FROM users WHERE id=:u", u=uid)[0]
    check("ism almashtirildi", "Sinov" not in row[0], row)
    check("telefon bo'shatildi", row[1] == f"deleted-{uid}", row)
    check("hisob bloklandi", row[2] is True, row)
    r = requests.get(f"{API}/users/me", headers=hdr)
    check("eski token darhol ishlamaydi", r.status_code in (401, 403), r.status_code)

    head("3. Shu raqam bilan yangidan ro'yxatdan o'tish mumkin")
    _, uid2, hdr2 = register("client", phone=phone)
    check("yangi hisob boshqa id bilan", uid2 != uid, (uid, uid2))
    check("yangi hisob ishlaydi", requests.get(f"{API}/users/me", headers=hdr2).status_code == 200)

    head("4. Egasi: faol buyurtma bor ekan — o'chirib bo'lmaydi")
    _, owner_id, owner_hdr = register("owner")
    set_balance(owner_id, 50000, bonus=50000)   # ro'yxatdan o'tish sovg'asi
    eq = requests.post(f"{API}/equipment/", headers=owner_hdr, json={
        "type": "excavator", "model": "Sinov o'chirish", "price_per_day": "500000",
        "latitude": "41.31", "longitude": "69.24", "status": "available", "available": True,
    })
    check("texnika qo'shildi", eq.status_code == 200, f"{eq.status_code} {eq.text}")
    eq_id = eq.json()["id"]

    # surat fayli — diskdan o'chishini tekshirish uchun
    from app.core import media
    media_dir = media.folder("equipment")
    photo_name = f"sinov_delete_{owner_id}.jpg"
    open(os.path.join(media_dir, photo_name), "wb").write(b"x")
    photo_url = f"/static/equipment/{photo_name}"
    sql("INSERT INTO equipment_photos (equipment_id, url) VALUES (:e, :u)", e=eq_id, u=photo_url)

    _, client_id, _ = register("client")
    today = date.today()
    sql("INSERT INTO orders (user_id, equipment_id, start_date, end_date, status, total_amount, "
        "commission, frozen_amount, delivery_latitude, delivery_longitude) "
        "VALUES (:c, :e, :s, :d, 'confirmed', 500000, 5000, 500000, '41.3', '69.2')",
        c=client_id, e=eq_id, s=today, d=today + timedelta(days=1))
    order_id = sql("SELECT id FROM orders WHERE equipment_id=:e", e=eq_id)[0][0]

    r = requests.delete(f"{API}/users/me", headers=owner_hdr)
    check("faol buyurtma — 409", r.status_code == 409, f"{r.status_code} {r.text}")
    check("sabab: tugallanmagan bitim", "buyurtma" in r.text.lower() or "заказ" in r.text.lower(), r.text)

    sql("UPDATE orders SET status='completed' WHERE id=:o", o=order_id)
    r = requests.delete(f"{API}/users/me", headers=owner_hdr)
    check("buyurtma yakunlangach — 200", r.status_code == 200, f"{r.status_code} {r.text}")

    deleted_at = sql("SELECT deleted_at FROM equipment WHERE id=:e", e=eq_id)[0][0]
    check("texnika katalogdan olindi (deleted_at)", deleted_at is not None)
    catalog = requests.get(f"{API}/equipment/?limit=100", headers=hdr2).json()
    check("katalogda ko'rinmaydi", all(e["id"] != eq_id for e in catalog))
    check("surat fayli diskdan o'chdi",
          not os.path.exists(os.path.join(media_dir, photo_name)))
    check("ikkinchi tomonning buyurtmasi qoldi",
          bool(sql("SELECT 1 FROM orders WHERE id=:o", o=order_id)))

    head("5. Admin ilovadan o'chira olmaydi")
    from _auth import token
    admin_phone = sql("SELECT phone FROM users WHERE role='admin' AND is_blocked=false "
                      "ORDER BY id LIMIT 1")[0][0]
    admin_hdr = token(admin_phone)
    c = check_delete(admin_hdr)
    check("adminga can_delete=false", c.get("can_delete") is False, c)
    r = requests.delete(f"{API}/users/me", headers=admin_hdr)
    check("admin DELETE — 409", r.status_code == 409, f"{r.status_code} {r.text}")


def cleanup():
    db = SessionLocal()
    try:
        ids = list(created_user_ids)
        db.execute(text("DELETE FROM orders WHERE user_id = ANY(:ids)"), {"ids": ids})
        db.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": ids})
        db.execute(text("DELETE FROM otp_verifications WHERE phone = ANY(:ps)"),
                   {"ps": created_phones})
        db.commit()
    finally:
        db.close()


if __name__ == "__main__":
    try:
        main()
    finally:
        cleanup()
    print(f"\nNATIJA: {ok_count} OK, {fail_count} FAIL")
    sys.exit(1 if fail_count else 0)
