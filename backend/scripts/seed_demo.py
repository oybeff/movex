#!/usr/bin/env python3
"""
Namoyish uchun ma'lumot to'ldiradi: texnika egalari, mijozlar, turli
turdagi texnika Toshkent bo'ylab, buyurtmalar va xabarnomalar.

Bo'sh bazada ilovani ham, adminkani ham ko'rib bo'lmaydi — shuning uchun
shu skript. Ma'lumot QO'SHILADI, hech narsa o'chirilmaydi.

Ishga tushirish:
    venv/bin/python scripts/seed_demo.py

PRODUCTION da ishlamaydi — atayin.
"""
import os
import random
import sys
from datetime import date, timedelta
from decimal import Decimal

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.config import settings
from app.core.equipment_types import EQUIPMENT_TYPES
from app.core.security import hash_password
from app.db.session import SessionLocal
from app.models.balance import Balance
from app.models.equipment import Equipment
from app.models.notification import Notification
from app.models.order import Order
from app.models.user import User

# Toshkent markazi va atrofi
CENTER_LAT, CENTER_LON = 41.2995, 69.2401

OWNERS = [
    ("998901000001", "Alisher Karimov"),
    ("998901000002", "Bobur Toshmatov"),
    ("998901000003", "Sardor Yo'ldoshev"),
]

CLIENTS = [
    ("998902000001", "Jasur Rahimov"),
    ("998902000002", "Dilshod Nazarov"),
]

# (tur kodi, model, kunlik narx, kuch)
MACHINES = [
    ("excavator",       "Komatsu PC200",       1_500_000, 148),
    ("excavator",       "Hitachi ZX210",       1_400_000, 160),
    ("mini_excavator",  "Kubota U17",            600_000,  16),
    ("backhoe_loader",  "JCB 3CX",             1_100_000, 109),
    ("bulldozer",       "Shantui SD16",        1_800_000, 160),
    ("front_loader",    "SDLG LG936",          1_000_000, 125),
    ("truck_crane",     "XCMG QY25K",          2_200_000, 247),
    ("manipulator",     "Hyundai HD170",         900_000, 260),
    ("aerial_platform", "Socage T318",           750_000, 120),
    ("dump_truck",      "Howo ZZ3257",           850_000, 371),
    ("concrete_mixer",  "Shacman 9m3",           950_000, 336),
    ("concrete_pump",   "Putzmeister M36",     2_800_000, 300),
    ("grader",          "XCMG GR165",          1_300_000, 165),
    ("roller",          "Bomag BW211",           700_000, 155),
    ("auger_drill",     "Soilmec SR30",        1_600_000, 200),
    ("tow_truck",       "Isuzu NQR evakuator",   650_000, 155),
    ("compressor",      "Atlas Copco XAS 97",    300_000,  49),
]

ADDRESSES = [
    "Toshkent, Chilonzor tumani",
    "Toshkent, Yunusobod tumani",
    "Toshkent, Mirzo Ulug'bek tumani",
    "Toshkent, Sergeli tumani",
    "Toshkent viloyati, Zangiota",
]


def jitter(value, spread=0.06):
    return round(value + random.uniform(-spread, spread), 6)


def get_or_create_user(db, phone, full_name, role):
    user = db.query(User).filter(User.phone == phone).first()
    if user:
        return user, False

    user = User(
        full_name=full_name,
        phone=phone,
        password_hash=hash_password("demo-only-not-used"),
        role=role,
    )
    db.add(user)
    db.flush()
    db.add(Balance(user_id=user.id, balance=Decimal("0"), frozen_balance=Decimal("0")))
    return user, True


def main() -> int:
    if (settings.APP_ENV or "").lower() == "production":
        print("APP_ENV=production. Namoyish ma'lumotini prodga solmaymiz.")
        return 1

    random.seed(20260830)
    db = SessionLocal()
    created = {"users": 0, "equipment": 0, "orders": 0, "notifications": 0}

    try:
        owners = []
        for phone, name in OWNERS:
            user, is_new = get_or_create_user(db, phone, name, "owner")
            owners.append(user)
            created["users"] += int(is_new)

        clients = []
        for phone, name in CLIENTS:
            user, is_new = get_or_create_user(db, phone, name, "client")
            clients.append(user)
            created["users"] += int(is_new)

        db.commit()

        # Har bir turdan bitta texnika, egalari navbat bilan
        equipment_list = []
        for index, (type_code, model, price, power) in enumerate(MACHINES):
            existing = db.query(Equipment).filter(Equipment.model == model).first()
            if existing:
                equipment_list.append(existing)
                continue

            owner = owners[index % len(owners)]
            eq = Equipment(
                owner_id=owner.id,
                type=type_code,
                model=model,
                year=random.randint(2015, 2024),
                power_hp=power,
                price_per_day=Decimal(price),
                price_per_hour=Decimal(price // 8),
                delivery_price_per_km=Decimal(random.choice([10_000, 12_000, 15_000])),
                address=random.choice(ADDRESSES),
                latitude=Decimal(str(jitter(CENTER_LAT))),
                longitude=Decimal(str(jitter(CENTER_LON))),
                status="available",
                available=True,
                description=f"{model} — ijaraga beriladi, operator bilan.",
            )
            db.add(eq)
            db.flush()
            equipment_list.append(eq)
            created["equipment"] += 1

        db.commit()

        # Bir nechta buyurtma turli holatlarda. Pul harakati bu yerda
        # ATAYLAB yo'q: buyurtmalar ko'rinish uchun, balanslarga tegmaymiz.
        today = date.today()
        wanted = [
            ("completed", -20, 3),
            ("completed", -12, 2),
            ("confirmed", -1, 4),
            ("pending", 3, 2),
            ("pending", 9, 5),
            ("rejected", -6, 2),
            ("cancelled", -9, 1),
        ]

        for index, (status, offset, days) in enumerate(wanted):
            eq = equipment_list[index % len(equipment_list)]
            client = clients[index % len(clients)]
            start = today + timedelta(days=offset)
            end = start + timedelta(days=days - 1)

            already = (
                db.query(Order)
                .filter(Order.equipment_id == eq.id, Order.start_date == start)
                .first()
            )
            if already:
                continue

            subtotal = Decimal(str(eq.price_per_day)) * days
            commission = (subtotal * Decimal("0.1")).quantize(Decimal("1"))

            order = Order(
                user_id=client.id,
                equipment_id=eq.id,
                start_date=start,
                end_date=end,
                status=status,
                total_amount=subtotal + commission,
                commission=commission,
                frozen_amount=Decimal("0"),
                delivery_latitude=str(jitter(CENTER_LAT)),
                delivery_longitude=str(jitter(CENTER_LON)),
                delivery_address=random.choice(ADDRESSES),
            )
            db.add(order)
            db.flush()
            created["orders"] += 1

            db.add(
                Notification(
                    user_id=eq.owner_id,
                    type="order_created",
                    title=f"Yangi buyurtma: {eq.type} {eq.model}",
                    body=f"Buyurtma #{order.id}, {start} — {end}",
                    order_id=order.id,
                    equipment_type=eq.type,
                    is_read=status in ("completed", "rejected", "cancelled"),
                )
            )
            created["notifications"] += 1

        db.commit()

        print("Namoyish ma'lumoti qo'shildi:")
        print(f"  foydalanuvchi : {created['users']}")
        print(f"  texnika       : {created['equipment']}  ({len(EQUIPMENT_TYPES) - 1} turdan)")
        print(f"  buyurtma      : {created['orders']}")
        print(f"  xabarnoma     : {created['notifications']}")
        print()
        print("Kirish OTP orqali, kod test rejimida javobda qaytadi:")
        for phone, name in OWNERS[:1] + CLIENTS[:1]:
            print(f"  {phone}  —  {name}")
        return 0

    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
