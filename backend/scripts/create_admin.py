#!/usr/bin/env python3
"""
Administrator yaratadi yoki mavjud odamni administratorga aylantiradi.

Nega alohida skript kerak. Toza bazada administrator YO'Q, ya'ni PHP
panelga umuman kirib bo'lmaydi. Eski hujjatlarda buning o'rniga qo'lda
SQL INSERT taklif qilingan, parol xeshi esa tayyor holda ko'chirib
qo'yilgan — bunday xesh boshqa paroldan bo'lib chiqadi va nima uchun
kirish ishlamayotgani ko'rinmaydi.

    venv/bin/python scripts/create_admin.py
    venv/bin/python scripts/create_admin.py --phone 998901234567 --name "Bosh admin"

Parol faqat so'raladi, argument sifatida OLINMAYDI: buyruq tarixida
(~/.bash_history) va `ps` ro'yxatida ochiq qolib ketardi.
"""
import argparse
import getpass
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.security import hash_password  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402
from app.models.user import User  # noqa: E402

#: Bazada raqam faqat raqamlardan iborat: 998901234567.
#: auth.py da ham aynan shunday tozalanadi — mos bo'lishi shart,
#: aks holda odam kirolmaydi: panel `WHERE phone = ?` bo'yicha qidiradi.
def clean_phone(raw: str) -> str:
    digits = re.sub(r"\D", "", raw or "")
    if len(digits) == 9:            # 901234567 → 998901234567
        digits = "998" + digits
    return digits


def ask_password() -> str:
    while True:
        first = getpass.getpass("Parol (ko'rinmaydi): ")
        if len(first) < 8:
            print("  Kamida 8 belgi bo'lsin.")
            continue
        second = getpass.getpass("Parolni takrorlang: ")
        if first != second:
            print("  Parollar mos kelmadi, qaytadan.")
            continue
        return first


def main() -> int:
    parser = argparse.ArgumentParser(description="MoveX GO administratori")
    parser.add_argument("--phone", help="998901234567 yoki 901234567")
    parser.add_argument("--name", help="To'liq ismi")
    args = parser.parse_args()

    phone = clean_phone(args.phone or input("Telefon raqam: "))
    if len(phone) != 12 or not phone.startswith("998"):
        print(f"Raqam noto'g'ri: {phone!r}. Kutilgani — 998901234567.", file=sys.stderr)
        return 1

    db = SessionLocal()
    try:
        user = db.query(User).filter(User.phone == phone).first()

        if user is not None:
            print(f"Bunday raqam bor: {user.full_name} (roli: {user.role}, id: {user.id})")
            answer = input("Administrator qilib, parolni yangilaymizmi? [ha/yo'q]: ").strip().lower()
            if answer not in ("ha", "h", "yes", "y", "да", "д"):
                print("Bekor qilindi.")
                return 1
            user.role = "admin"
            # Bloklangan yoki muzlatilgan administrator kira olmaydi —
            # panelga kirish uchun ataylab tozalaymiz
            user.is_blocked = False
            user.is_frozen = False
            user.password_hash = hash_password(ask_password())
            db.commit()
            print(f"\nTayyor. {user.full_name} endi administrator.")
        else:
            name = args.name or input("To'liq ismi: ").strip()
            if not name:
                print("Ism bo'sh bo'lmasin.", file=sys.stderr)
                return 1
            password = ask_password()
            user = User(
                full_name=name,
                phone=phone,
                password_hash=hash_password(password),
                role="admin",
                is_blocked=False,
                is_frozen=False,
            )
            db.add(user)
            db.commit()
            print(f"\nTayyor. Administrator yaratildi, id: {user.id}")

        print(f"Panelga kirish:  login {phone}  (aynan shunday, + belgisiz)")
        return 0
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        print(f"Xato: {exc}", file=sys.stderr)
        return 1
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
