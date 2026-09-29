#!/usr/bin/env python3
"""
Xaritani ko'rish uchun mo'l-ko'l namoyish ma'lumoti: texnika Toshkentning
TURLI tumanlariga tarqatiladi, bir joyga to'planmaydi.

Nega alohida skript. `seed_demo.py` bor, lekin unda butun texnika shahar
markazidan ±6 km ichida, ya'ni xaritada bitta uyumga o'xshaydi. Bu yerda
har bir egaga o'z tumani biriktiriladi va texnikasi o'sha tumanda paydo
bo'ladi — xaritada nuqtalar butun shahar bo'ylab yoyilib turadi.

Ma'lumot QO'SHILADI, hech narsa o'chirilmaydi. Idempotent: telefon va
model bo'yicha tekshiriladi, qayta ishga tushirsa nusxa ko'paymaydi.

Ishga tushirish (backend/ dan):
    venv/bin/python scripts/seed_map_demo.py

PRODUCTION da ishlamaydi — atayin.
"""
import os
import random
import sys
from datetime import date, timedelta
from decimal import Decimal

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.config import settings          # noqa: E402
from app.core.security import hash_password    # noqa: E402
from app.db.session import SessionLocal        # noqa: E402
from app.models.balance import Balance         # noqa: E402
from app.models.equipment import Equipment     # noqa: E402
from app.models.order import Order             # noqa: E402
from app.models.user import User               # noqa: E402

# Toshkent tumanlari — HAQIQIY markaziy koordinatalari. Har bir ega shu
# tumanga o'tiradi, texnikasi ham shu yerda chiqadi. Shu tufayli xaritada
# nuqtalar butun shahar bo'ylab yoyiladi, bitta joyga to'planmaydi.
DISTRICTS = [
    ("Chilonzor tumani",       41.2755, 69.2033),
    ("Yunusobod tumani",       41.3647, 69.2897),
    ("Mirzo Ulug'bek tumani",  41.3253, 69.3348),
    ("Sergeli tumani",         41.2237, 69.2203),
    ("Yakkasaroy tumani",      41.2833, 69.2500),
    ("Shayxontohur tumani",    41.3253, 69.2264),
    ("Uchtepa tumani",         41.2900, 69.1700),
    ("Bektemir tumani",        41.2050, 69.3350),
    ("Mirobod tumani",         41.2900, 69.2900),
    ("Olmazor tumani",         41.3600, 69.2200),
]

# Har bir ega — bitta tumanga. (telefon, ism, tuman indeksi)
OWNERS = [
    ("998905000001", "Rustam Aliyev",       0),
    ("998905000002", "Jahongir Yusupov",    1),
    ("998905000003", "Otabek Sharipov",     2),
    ("998905000004", "Kamol Ergashev",      3),
    ("998905000005", "Doniyor Xolmatov",    4),
    ("998905000006", "Farrux Qodirov",      5),
    ("998905000007", "Sherzod Umarov",      6),
    ("998905000008", "Ulug'bek Nazarov",    7),
    ("998905000009", "Bekzod Islomov",      8),
    ("998905000010", "Aziz Tursunov",       9),
]

CLIENTS = [
    ("998906000001", "Nodir Abdullayev"),
    ("998906000002", "Sanjar Mahmudov"),
    ("998906000003", "Ravshan Ismoilov"),
    ("998906000004", "Timur Saidov"),
    ("998906000005", "Akmal Yodgorov"),
]

# (tur kodi, model, kunlik narx so'mda, ot kuchi)
MACHINES = [
    ("excavator",       "Caterpillar 320",     1_600_000, 162),
    ("excavator",       "Volvo EC220",         1_550_000, 172),
    ("mini_excavator",  "Bobcat E35",            650_000,  24),
    ("mini_excavator",  "Yanmar ViO35",          620_000,  25),
    ("backhoe_loader",  "JCB 4CX",             1_200_000, 109),
    ("bulldozer",       "Caterpillar D6",      1_900_000, 215),
    ("front_loader",    "Caterpillar 950",     1_150_000, 250),
    ("front_loader",    "LiuGong 856",         1_050_000, 220),
    ("truck_crane",     "Zoomlion QY30",       2_300_000, 247),
    ("truck_crane",     "Liebherr LTM1030",    2_600_000, 340),
    ("manipulator",     "Isuzu Forward",         920_000, 240),
    ("aerial_platform", "Genie Z-45",            780_000, 130),
    ("dump_truck",      "Shacman F3000",         880_000, 380),
    ("dump_truck",      "MAN TGS 40",            920_000, 400),
    ("concrete_mixer",  "Howo 8m3",              960_000, 336),
    ("concrete_pump",   "Sany 52m",            2_900_000, 350),
    ("grader",          "Caterpillar 140",     1_350_000, 180),
    ("roller",          "Hamm 3410",             720_000, 160),
    ("auger_drill",     "Bauer BG28",          1_700_000, 220),
    ("compressor",      "Kaeser M57",            320_000,  55),
]


def jitter(value, spread=0.012):
    """Tuman ichida kichik siljish — texnika bir nuqtaga ustma-ust tushmasin."""
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

    random.seed(20260929)
    db = SessionLocal()
    created = {"owners": 0, "clients": 0, "equipment": 0, "orders": 0}

    try:
        owners = []
        for phone, name, district_index in OWNERS:
            user, is_new = get_or_create_user(db, phone, name, "owner")
            owners.append((user, district_index))
            created["owners"] += int(is_new)

        clients = []
        for phone, name in CLIENTS:
            user, is_new = get_or_create_user(db, phone, name, "client")
            clients.append(user)
            created["clients"] += int(is_new)

        db.commit()

        # Texnika egalarga navbat bilan tarqatiladi. Har biri O'Z tumanida
        # paydo bo'ladi: koordinata o'sha tuman markazidan olinadi.
        equipment_list = []
        for index, (type_code, model, price, power) in enumerate(MACHINES):
            existing = db.query(Equipment).filter(Equipment.model == model).first()
            if existing:
                equipment_list.append(existing)
                continue

            owner, district_index = owners[index % len(owners)]
            district_name, lat, lon = DISTRICTS[district_index]

            eq = Equipment(
                owner_id=owner.id,
                type=type_code,
                model=model,
                year=random.randint(2016, 2024),
                power_hp=power,
                price_per_day=Decimal(price),
                price_per_hour=Decimal(price // 8),
                delivery_price_per_km=Decimal(random.choice([10_000, 12_000, 15_000])),
                address=f"Toshkent, {district_name}",
                latitude=Decimal(str(jitter(lat))),
                longitude=Decimal(str(jitter(lon))),
                status="available",
                available=True,
                description=f"{model} — ijaraga beriladi, operator bilan.",
            )
            db.add(eq)
            db.flush()
            equipment_list.append(eq)
            created["equipment"] += 1

        db.commit()

        # Bir nechta faol buyurtma: yetkazib berish nuqtasi BOSHQA tumanda —
        # xaritada texnikadan nuqtagacha punktir chiziladi, mashina qayerdan
        # qayerga ketishi ko'rinadi.
        today = date.today()
        plan = [
            ("confirmed", 1, 3),
            ("confirmed", 2, 4),
            ("pending", 5, 2),
            ("pending", 7, 5),
            ("confirmed", 0, 3),
            ("pending", 4, 2),
        ]

        for index, (status, offset, days) in enumerate(plan):
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

            # Yetkazish nuqtasi — boshqa tuman markazi, texnika turgan
            # tumandan farqli.
            drop = DISTRICTS[(index + 3) % len(DISTRICTS)]
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
                delivery_latitude=str(jitter(drop[1])),
                delivery_longitude=str(jitter(drop[2])),
                delivery_address=f"Toshkent, {drop[0]}",
            )
            db.add(order)
            created["orders"] += 1

        db.commit()

        print("qo'shildi:")
        print(f"  texnika egalari:  {created['owners']}")
        print(f"  mijozlar:         {created['clients']}")
        print(f"  texnika:          {created['equipment']}")
        print(f"  buyurtmalar:      {created['orders']}")

        total_eq = db.query(Equipment).filter(Equipment.deleted_at.is_(None)).count()
        total_owners = db.query(User).filter(User.role == "owner").count()
        print(f"\nendi bazada: {total_owners} ega, {total_eq} texnika")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
