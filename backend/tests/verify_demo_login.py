"""
Demo hisoblar: Google Play tekshiruvi uchun O'ZGARMAS kod.

Play Console formasi bitta "parol" so'raydi — har safar yangi kod u yerga
sig'maydi. Shuning uchun OTP_TEST_PHONES dagi raqamlar uchun kod
OTP_DEMO_CODE dan olinadi va o'zgarmaydi. Qayta so'rashda "60 soniya
kuting" ham chiqmaydi: tekshiruvchi tugmani bir necha marta bosishi mumkin.

HAQIQIY raqamlarga bu tegmasligi shu yerda qo'riqlanadi — aks holda
hammaning kodi bir xil bo'lib qolardi, ya'ni istalgan hisobga kirish
mumkin bo'lardi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_demo_login.py
"""
import os
import sys

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND)

API = "http://127.0.0.1:8000"
DEMO_PHONE = "998900000001"
DEMO_CODE = "1234"
REAL_PHONE = "998901119999"

ok = fail = 0


def check(label, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1
        print(f"  [OK]   {label}")
    else:
        fail += 1
        print(f"  [FAIL] {label}  {detail}")


def code_in_db(phone):
    from sqlalchemy import text
    from app.db.session import SessionLocal
    db = SessionLocal()
    try:
        return db.execute(
            text("SELECT otp_code FROM otp_verifications WHERE phone = :p "
                 "ORDER BY id DESC LIMIT 1"), {"p": phone}).scalar()
    finally:
        db.close()


def cleanup():
    from sqlalchemy import text
    from app.db.session import SessionLocal
    db = SessionLocal()
    try:
        db.execute(text("DELETE FROM otp_verifications WHERE phone = :p"), {"p": REAL_PHONE})
        db.commit()
    finally:
        db.close()


def main():
    print(f"\n{'=' * 66}\nDemo hisob: kod o'zgarmaydi\n{'=' * 66}")
    codes = []
    for _ in range(3):
        r = requests.post(f"{API}/auth/send-otp", json={"phone": DEMO_PHONE})
        check("qayta so'rashda 'kuting' chiqmadi", r.status_code == 200,
              f"{r.status_code} {r.text[:90]}")
        codes.append(code_in_db(DEMO_PHONE))

    check("kod uch marta ham bir xil", len(set(codes)) == 1, str(codes))
    check(f"kod aynan {DEMO_CODE}", codes[0] == DEMO_CODE, str(codes[0]))

    # Hisob bo'lmasa — yaratamiz: tekshiruv kirishni sinaydi, ro'yxatdan
    # o'tishni emas.
    r = requests.post(f"{API}/auth/verify-otp",
                      json={"phone": DEMO_PHONE, "otp_code": DEMO_CODE})
    if r.status_code == 200 and not r.json().get("access_token"):
        requests.post(f"{API}/auth/register", json={
            "full_name": "Google Play Review", "phone": DEMO_PHONE, "role": "client"})
        requests.post(f"{API}/auth/send-otp", json={"phone": DEMO_PHONE})
        r = requests.post(f"{API}/auth/verify-otp",
                          json={"phone": DEMO_PHONE, "otp_code": DEMO_CODE})

    check("o'zgarmas kod bilan kirish ishlaydi",
          r.status_code == 200 and r.json().get("access_token"),
          f"{r.status_code} {r.text[:90]}")

    print(f"\n{'=' * 66}\nHaqiqiy raqamga tegmaydi\n{'=' * 66}")
    try:
        requests.post(f"{API}/auth/send-otp", json={"phone": REAL_PHONE})
        real = code_in_db(REAL_PHONE)
        check("haqiqiy raqamning kodi demo kod EMAS",
              real is None or real != DEMO_CODE, str(real))
    finally:
        cleanup()

    print(f"\n{'=' * 66}\nITOG: {ok} o'tdi, {fail} yiqildi\n{'=' * 66}")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
