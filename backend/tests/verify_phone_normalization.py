"""
Telefon raqam: "+" bilan yozilgan raqam ham ishlashi kerak.

Odam raqamni turlicha yozadi: +998901234567, 998901234567, 901234567,
00998901234567, +998 90 123 45 67. Hammasi BITTA hisobga olib borishi
kerak.

Ikkita xato shu yerda qo'riqlanadi:

1. Kirish. Server raqamdan "+", probel va qavslarni olib tashlaydi —
   demak har xil yozilgan raqam bitta yozuvni topishi shart.

2. Profilni tahrirlash. Ilgari raqam bazaga QANDAY yozilgan bo'lsa,
   shundayligicha saqlanardi: profilga "+998901234567" deb yozgan odam
   o'z hisobiga kira olmay qolardi — kirish "998901234567" ni qidiradi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_phone_normalization.py
"""
import os
import sys
import time

import requests

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


def new_owner():
    phone = f"9989{(int(time.time() * 1000)) % 100000000:08d}"
    requests.post(f"{API}/auth/verify-otp",
                  json={"phone": phone, "otp_code": otp_code(phone, API)})
    r = requests.post(f"{API}/auth/register",
                      json={"full_name": "Sinov", "phone": phone, "role": "owner"})
    if r.status_code != 200:
        raise RuntimeError(f"ro'yxatdan o'tmadi: {r.status_code} {r.text}")
    created_phones.append(phone)
    login = requests.post(f"{API}/auth/verify-otp",
                          json={"phone": phone, "otp_code": otp_code(phone, API)}).json()
    return phone, {"Authorization": f"Bearer {login['access_token']}"}


def db_phone(user_id):
    from sqlalchemy import text
    from app.db.session import SessionLocal
    db = SessionLocal()
    try:
        return db.execute(text("SELECT phone FROM users WHERE id = :i"),
                          {"i": user_id}).scalar()
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
    try:
        head("Har xil yozilgan raqam BITTA hisobni topadi")
        phone, hdr = new_owner()
        digits = phone[3:]                      # 901234567 qismi

        forms = {
            "raqamning o'zi": phone,
            "+ bilan": f"+{phone}",
            "probellar bilan": f"+{phone[:3]} {digits[:2]} {digits[2:5]} {digits[5:7]} {digits[7:]}",
            "qavs va chiziqcha": f"+{phone[:3]}({digits[:2]}){digits[2:5]}-{digits[5:7]}-{digits[7:]}",
            "xalqaro 00 bilan": f"00{phone}",
        }
        for label, value in forms.items():
            r = requests.post(f"{API}/auth/send-otp", json={"phone": value})
            body = r.text.lower()
            # Muvaffaqiyat yoki "kod allaqachon yuborilgan" — ikkalasi ham
            # raqam TOPILGANINI bildiradi. Xato bo'lsa boshqa matn chiqadi.
            found = r.status_code == 200 or "soniya" in body
            check(f"{label}: raqam tanildi", found, f"{r.status_code} {r.text[:110]}")

        head("Profilga + bilan yozilgan raqam bazani buzmaydi")
        me = requests.get(f"{API}/users/me", headers=hdr).json()
        r = requests.put(f"{API}/users/me", headers=hdr, json={"phone": f"+{phone}"})
        check("profil saqlandi", r.status_code == 200, f"{r.status_code} {r.text[:110]}")

        stored = db_phone(me["id"])
        check("bazada + yo'q — yagona ko'rinish", stored == phone, f"bazada: {stored}")

        r = requests.post(f"{API}/auth/send-otp", json={"phone": phone})
        found = r.status_code == 200 or "soniya" in r.text.lower()
        check("tahrirdan keyin ham kira oladi", found, f"{r.status_code} {r.text[:110]}")

        head("Begona raqamni egallab bo'lmaydi")
        other_phone, _ = new_owner()
        r = requests.put(f"{API}/users/me", headers=hdr, json={"phone": f"+{other_phone}"})
        check("band raqam rad etildi", r.status_code == 400,
              f"{r.status_code} {r.text[:110]}")
        check("o'z raqami o'zgarmadi", db_phone(me["id"]) == phone, str(db_phone(me["id"])))
    finally:
        cleanup()

    print(f"\n{'=' * 66}\nITOG: {ok_count} o'tdi, {fail_count} yiqildi\n{'=' * 66}")
    return 1 if fail_count else 0


if __name__ == "__main__":
    sys.exit(main())
