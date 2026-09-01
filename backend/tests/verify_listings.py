"""
E'lonlar taxtasi.

Zayavkadan farqi: erkin matn, savdo yo'q, egasi oladi va mijoz tasdiqlaydi.

Ikki narsa alohida tekshiriladi:

  1. Telefon raqami begonaga ko'rinmaydi. Aks holda ro'yxatdan o'tib, hamma
     e'lonni ochib chiqish orqali raqamlar bazasini yig'ib olsa bo'lardi.
  2. Bitta e'lonni ikki ega ola olmaydi. Qator bloklanadi, ya'ni "kim
     birinchi bo'lsa — o'shaniki" haqiqatan ishlaydi.

Test IDEMPOTENT.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_listings.py
"""
import os
import sys

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import token  # noqa: E402

API = "http://127.0.0.1:8000"
CLIENT_PHONE = "998901110002"
OWNER_PHONE = "998901110001"
OTHER_CLIENT_PHONE = "998901179425"

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


client = token(CLIENT_PHONE)
owner = token(OWNER_PHONE)
other = token(OTHER_CLIENT_PHONE)


def create(**over):
    body = {
        "title": "Нужен эвакуатор",
        "description": "Вытащить технику с объекта",
        "budget": 700000,
        "address": "Тошкент, объект",
        "latitude": 41.3, "longitude": 69.25,
    }
    body.update(over)
    return requests.post(f"{API}/listings/", headers=client, json=body)


head("1. ОБЪЯВЛЕНИЕ СОЗДАЁТСЯ БЕЗ СПРАВОЧНИКА")

r = create()
check("объявление создано", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
listing = r.json()
lid = listing["id"]
check("статус open", listing["status"] == "open", listing["status"])
check("тип техники не обязателен", listing.get("equipment_type") is None)
check("деньги не тронуты — их тут нет", "frozen_amount" not in listing)

r = create(title="")
check("пустой заголовок отклонён", r.status_code == 422, f"{r.status_code}")

r = create(equipment_type="letayushchaya_tarelka")
check("несуществующий тип отклонён", r.status_code == 400, f"{r.status_code}")

r = create(budget=-5)
check("отрицательный бюджет отклонён", r.status_code == 422, f"{r.status_code}")

head("2. ТЕЛЕФОН НЕ ВИДЕН ПОСТОРОННИМ")

check("автор видит свой телефон", listing.get("contact_phone") is not None)

seen = requests.get(f"{API}/listings/{lid}", headers=other).json()
check("посторонний телефона не видит", seen.get("contact_phone") is None,
      str(seen.get("contact_phone")))

feed = requests.get(f"{API}/listings/feed", headers=owner).json()
mine_in_feed = [x for x in feed if x["id"] == lid]
check("объявление в ленте владельца", len(mine_in_feed) == 1)
check("в ленте телефона тоже нет",
      mine_in_feed and mine_in_feed[0].get("contact_phone") is None)

own_feed = requests.get(f"{API}/listings/feed", headers=client).json()
check("своё объявление в свою ленту не попадает",
      not any(x["id"] == lid for x in own_feed))

head("3. КТО ПЕРВЫЙ ВЗЯЛ — ТОГО И ЗАКАЗ")

r = requests.post(f"{API}/listings/{lid}/take", headers=client)
check("свой заказ взять нельзя", r.status_code in (400, 403), f"{r.status_code}")

r = requests.post(f"{API}/listings/{lid}/take", headers=owner)
check("владелец взял", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
check("статус taken", r.json()["status"] == "taken")
check("видно, кто взял", r.json().get("taker_name") is not None)

r = requests.post(f"{API}/listings/{lid}/take", headers=owner)
check("повторно взять нельзя", r.status_code == 400, f"{r.status_code}")

head("4. ПОДТВЕРЖДЕНИЕ ОТКРЫВАЕТ ТЕЛЕФОН")

before = requests.get(f"{API}/listings/{lid}", headers=owner).json()
check("до подтверждения исполнитель телефона не видит",
      before.get("contact_phone") is None, str(before.get("contact_phone")))

r = requests.post(f"{API}/listings/{lid}/confirm", headers=other)
check("посторонний подтвердить не может", r.status_code == 403, f"{r.status_code}")

r = requests.post(f"{API}/listings/{lid}/confirm", headers=client)
check("клиент подтвердил", r.status_code == 200, f"{r.status_code}")
check("статус confirmed", r.json()["status"] == "confirmed")

after = requests.get(f"{API}/listings/{lid}", headers=owner).json()
check("после подтверждения телефон открыт",
      after.get("contact_phone") is not None)
check("посторонний по-прежнему не видит",
      requests.get(f"{API}/listings/{lid}", headers=other).json().get("contact_phone") is None)

head("5. ЗАВЕРШЕНИЕ")

r = requests.post(f"{API}/listings/{lid}/finish", headers=other)
check("посторонний завершить не может", r.status_code == 403, f"{r.status_code}")

r = requests.post(f"{API}/listings/{lid}/finish", headers=owner)
check("исполнитель завершил", r.status_code == 200, f"{r.status_code}")
check("статус done", r.json()["status"] == "done")

head("6. ОТКАЗ ОТ ИСПОЛНИТЕЛЯ ВОЗВРАЩАЕТ В ЛЕНТУ")

lid2 = create(title="Нужны грузчики, 3 человека").json()["id"]
requests.post(f"{API}/listings/{lid2}/take", headers=owner)
r = requests.post(f"{API}/listings/{lid2}/reject", headers=client)
check("клиент отказал исполнителю", r.status_code == 200, f"{r.status_code}")
check("объявление снова открыто", r.json()["status"] == "open")
check("исполнитель снят", r.json().get("taken_by") is None)

feed = requests.get(f"{API}/listings/feed", headers=owner).json()
check("вернулось в ленту", any(x["id"] == lid2 for x in feed))

head("7. ОТМЕНА")

r = requests.post(f"{API}/listings/{lid2}/cancel", headers=other)
check("чужое отменить нельзя", r.status_code == 403, f"{r.status_code}")

r = requests.post(f"{API}/listings/{lid2}/cancel", headers=client)
check("своё отменяется", r.status_code == 200, f"{r.status_code}")
check("статус cancelled", r.json()["status"] == "cancelled")

feed = requests.get(f"{API}/listings/feed", headers=owner).json()
check("отменённое из ленты пропало", not any(x["id"] == lid2 for x in feed))

head("8. СЧЁТЧИК ПРОСМОТРОВ")

lid3 = create(title="Нужен автокран на день").json()["id"]
requests.get(f"{API}/listings/{lid3}", headers=owner)
requests.get(f"{API}/listings/{lid3}", headers=other)
views = requests.get(f"{API}/listings/{lid3}", headers=client).json()["views_count"]
check("чужие просмотры считаются", views >= 2, f"{views}")

before_own = views
requests.get(f"{API}/listings/{lid3}", headers=client)
after_own = requests.get(f"{API}/listings/{lid3}", headers=client).json()["views_count"]
check("свои просмотры не считаются", after_own == before_own,
      f"{before_own} -> {after_own}")

requests.post(f"{API}/listings/{lid3}/cancel", headers=client)

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
