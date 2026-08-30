#!/usr/bin/env python3
"""
Bazani birinchi marta tayyorlash.

Nima uchun kerak: migratsiyalar zanjiri boshidan to'liq sxemani qurmaydi —
ular allaqachon mavjud jadvallarni o'zgartirish uchun yozilgan (ilova
ishga tushganda create_all() chaqirilardi). Shuning uchun bo'sh bazada
`alembic upgrade head` xato beradi.

Bu skript sxemani modellardan quradi va Alembic ni "head" holatiga
belgilaydi, shundan keyin barcha yangi migratsiyalar odatdagidek ishlaydi.

MAVJUD bazada ishlatmang — u yerda faqat `alembic upgrade head` kerak.

Ishga tushirish:
    venv/bin/python scripts/init_db.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from alembic import command
from alembic.config import Config
from sqlalchemy import inspect

import app.models  # noqa: F401  — barcha modellarni Base ga ro'yxatdan o'tkazadi
from app.db.base import Base
from app.db.session import engine

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main() -> int:
    inspector = inspect(engine)
    existing = set(inspector.get_table_names())
    # alembic_version hisobga olinmaydi: u bo'sh bazada ham paydo bo'lishi mumkin
    existing.discard("alembic_version")

    if existing:
        print("Bazada allaqachon jadvallar bor:", ", ".join(sorted(existing)[:5]), "...")
        print("Bu skript faqat BO'SH baza uchun. Mavjud bazada:")
        print("    alembic upgrade head")
        return 1

    print("Sxema modellardan quriladi...")
    Base.metadata.create_all(bind=engine)
    print(f"  {len(Base.metadata.tables)} ta jadval yaratildi")

    print("Alembic 'head' holatiga belgilanadi...")
    alembic_cfg = Config(os.path.join(BACKEND_DIR, "alembic.ini"))
    alembic_cfg.set_main_option("script_location", os.path.join(BACKEND_DIR, "alembic"))
    command.stamp(alembic_cfg, "head")

    print("\nTayyor. Keyingi yangilanishlar uchun: alembic upgrade head")
    return 0


if __name__ == "__main__":
    sys.exit(main())
