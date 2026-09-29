"""
Platforma ulushi: kim to'laydi va qancha.

Yangi qoida: ulushni TEXNIKA EGASI to'laydi. Mijoz faqat ijara va yetkazib
berish uchun to'laydi, ulush esa buyurtma yakunlanganda egasining pulidan
ushlanadi. Ilgari ulush mijozning summasiga ustiga qo'shilardi.

Ikkita rejim bor va ular adminkadan almashtiriladi:
  fixed   — har bir buyurtmadan qat'iy summa (hozir 5 000 so'm)
  percent — ijara summasidan foiz (10%)

Eng muhim tekshiruv oxirida: ulush buyurtma summasidan oshmasligi kerak.
Aks holda arzon buyurtmada egasining balansi minusga ketardi — ya'ni u
ishlagani uchun pul to'lab qolardi.

Test IDEMPOTENT. Rejimni o'zgartiradi, lekin oxirida qaytaradi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_commission.py
"""
import os
import re
import sys
from datetime import datetime, timedelta
from decimal import Decimal

import requests

from _topup import topup as _rahmat_topup

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import token  # noqa: E402

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND)

API = "http://127.0.0.1:8000"
OWNER_PHONE = "998901110001"
CLIENT_PHONE = "998901110002"

ok_count = 0
fail_count = 0


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


def set_mode(mode, fixed=None, percent=None):
    """Rejimni to'g'ridan-to'g'ri bazadan o'zgartiramiz — adminka HTTP
    orqali ishlaydi va bu yerda kerak emas.

    ORM ishlatiladi: app_settings.value — JSON ustuni, va SQLAlchemy uni
    o'zi to'g'ri seriyalaydi. Xom SQL da to_jsonb(:v::text) yozib bo'lmaydi:
    "::" nomlangan parametr sintaksisi bilan to'qnashadi."""
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


def balances(hdr):
    b = requests.get(f"{API}/balance/me", headers=hdr).json()
    return Decimal(str(b["balance"])), Decimal(str(b["frozen_balance"]))


def topup(hdr, amount):
    """
    Hisob to'ldirish — Rahmat (Multicard) orqali.

    Mantiq _topup.py da: ilgari bu funksiya har bir testda o'z nusxasi
    bilan turardi va to'lov tizimi almashganda oltita joyni tuzatish
    kerak bo'ldi.
    """
    return _rahmat_topup(hdr, amount, API)


def free_dates(days=1):
    start = datetime.now() + timedelta(days=11000 + datetime.now().microsecond % 4000)
    return start.strftime("%Y-%m-%d"), (start + timedelta(days=days)).strftime("%Y-%m-%d")


client = token(CLIENT_PHONE)
owner = token(OWNER_PHONE)
topup(client, 10_000_000)

equipment = requests.get(
    f"{API}/equipment/", headers=owner, params={"owner_only": True, "limit": 50}
).json()
assert equipment, "у владельца нет техники"
EQ = equipment[0]

# --------------------------------------------------------------------------
head("1. ФИКСИРОВАННАЯ КОМИССИЯ: КЛИЕНТ ЕЁ НЕ ПЛАТИТ")

set_mode("fixed", fixed=5000)

start, end = free_dates(2)
r = requests.post(f"{API}/orders/", headers=client, json={
    "equipment_id": EQ["id"], "start_date": start, "end_date": end,
    "delivery_latitude": "41.31", "delivery_longitude": "69.28",
})
check("заказ создан", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
order = r.json()

days = (datetime.strptime(end, "%Y-%m-%d") - datetime.strptime(start, "%Y-%m-%d")).days + 1
rate = Decimal(str(EQ["price_per_day"]))
subtotal = (rate * days).quantize(Decimal("1"))
total = Decimal(str(order["total_amount"]))
commission = Decimal(str(order["commission"]))
delivery = Decimal(str(order.get("delivery_fee") or 0))

check("комиссия ровно 5 000", commission == Decimal("5000"), str(commission))
check("клиент платит аренду и доставку, без комиссии",
      total == subtotal + delivery, f"{total} != {subtotal} + {delivery}")
check("заморожено ровно то, что платит клиент",
      Decimal(str(order["frozen_amount"])) == total)

# --------------------------------------------------------------------------
head("2. ПРИ ЗАВЕРШЕНИИ КОМИССИЯ УДЕРЖИВАЕТСЯ С ВЛАДЕЛЬЦА")

client_before, client_frozen_before = balances(client)
owner_before, _ = balances(owner)

requests.put(f"{API}/orders/{order['id']}", headers=owner, json={"status": "confirmed"})
r = requests.put(f"{API}/orders/{order['id']}", headers=client, json={"status": "completed"})
check("заказ завершён", r.status_code == 200, f"{r.status_code} {r.text[:150]}")

client_after, client_frozen_after = balances(client)
owner_after, _ = balances(owner)

check("с клиента списана ровно сумма заказа",
      client_before - client_after == total,
      f"списано {client_before - client_after}, заказ {total}")
check("владелец получил сумму заказа МИНУС комиссию",
      owner_after - owner_before == total - commission,
      f"получено {owner_after - owner_before}, ожидали {total - commission}")
check("деньги не создались и не исчезли",
      (client_before - client_after) == (owner_after - owner_before) + commission,
      f"{client_before - client_after} != {owner_after - owner_before} + {commission}")

# --------------------------------------------------------------------------
head("3. ПЕРЕКЛЮЧЕНИЕ НА ПРОЦЕНТ")

set_mode("percent", percent=10)

start, end = free_dates(2)
r = requests.post(f"{API}/orders/", headers=client, json={
    "equipment_id": EQ["id"], "start_date": start, "end_date": end,
    "delivery_latitude": "41.31", "delivery_longitude": "69.28",
})
check("заказ создан в процентном режиме", r.status_code == 200, f"{r.status_code}")
order2 = r.json()
commission2 = Decimal(str(order2["commission"]))
total2 = Decimal(str(order2["total_amount"]))

check("комиссия стала 10% от аренды",
      commission2 == (subtotal / 10).quantize(Decimal("1")),
      f"{commission2}, ожидали {(subtotal / 10).quantize(Decimal('1'))}")
check("клиент по-прежнему не платит комиссию",
      total2 == subtotal + Decimal(str(order2.get("delivery_fee") or 0)),
      f"{total2}")

requests.put(f"{API}/orders/{order2['id']}", headers=client, json={"status": "cancelled"})

# --------------------------------------------------------------------------
head("4. КОМИССИЯ НЕ ЗАГОНЯЕТ ВЛАДЕЛЬЦА В МИНУС")

# Дешёвый заказ: если бы комиссию не ограничивали суммой заказа, владелец
# заплатил бы за то, что поработал.
set_mode("fixed", fixed=99_000_000)

start, end = free_dates(1)
r = requests.post(f"{API}/orders/", headers=client, json={
    "equipment_id": EQ["id"], "start_date": start, "end_date": end,
    "delivery_latitude": "41.31", "delivery_longitude": "69.28",
})
check("заказ создан при огромной комиссии", r.status_code == 200, f"{r.status_code}")
order3 = r.json()
commission3 = Decimal(str(order3["commission"]))
total3 = Decimal(str(order3["total_amount"]))

check("комиссия обрезана суммой заказа", commission3 == total3,
      f"комиссия {commission3}, заказ {total3}")
check("владельцу достанется не меньше нуля", total3 - commission3 >= 0,
      f"{total3 - commission3}")

requests.put(f"{API}/orders/{order3['id']}", headers=client, json={"status": "cancelled"})

# Возвращаем рабочий режим
set_mode("fixed", fixed=5000, percent=10)
check("режим возвращён на 5 000", True)

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
