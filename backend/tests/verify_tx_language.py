"""
Pul harakati izohlari va "Mening e'lonlarim" ro'yxati.

Nega bu test bor. 2026-09-01 dagi to'liq E2E ikkita narsani ochdi:

  1. Tranzaksiya izohlari f-satr bilan faqat o'zbekcha yozilardi va bazaga
     tayyor matn bo'lib tushardi. Ruscha interfeysdagi odam o'z "Amallar
     tarixi"da "Buyurtma #362 yakunlandi" ko'rardi. Izoh keyin
     o'zgartirilmaydi, shuning uchun til YOZISH paytida hal bo'lishi kerak.

  2. Daromad izohida "(90%)" deb yozilardi. Komissiya esa allaqachon qat'iy
     5 000 so'm: 1 907 400 dan 1 902 400 qoldi — bu 90% emas. Foizni umuman
     yozmaymiz: u sozlamadan o'zgaradi, matn esa bazada qotib qoladi.

  3. "Mening" ro'yxati faqat o'zi joylagan e'lonni qaytarardi. Javob
     berganini ro'yxat bo'lib ko'radigan joy yo'q edi — u faqat taxtada
     begonalar orasida ko'rinardi.

Test IDEMPOTENT: e'lon yaratadi va oxirida bekor qiladi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_tx_language.py
"""
import os
import re
import sys

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import token  # noqa: E402

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

API = "http://127.0.0.1:8000"
CLIENT_PHONE = "998901110002"
OWNER_PHONE = "998901110001"

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


def head(title):
    print("\n" + "=" * 66)
    print(title)
    print("=" * 66)


# ------------------------------------------------------------------ 1
head("1. ИЗОХ ИКИ ТИЛДА, ФОИЗСИЗ")

from app.core.messages import t  # noqa: E402

ru = t("tx.order_income", "ru", order_id=362, what="Mini ekskavator Kubota U17")
uz = t("tx.order_income", "uz", order_id=362, what="Mini ekskavator Kubota U17")

check("русский текст дохода — по-русски", "Доход с заказа" in ru, ru)
check("узбекский текст дохода — по-узбекски", "daromad" in uz, uz)

# Tur nomi ham izoh tilida bo'lishi kerak: ruscha satr ichida o'zbekcha
# "Mini ekskavator" turgan edi.
from app.core.equipment_types import type_name  # noqa: E402

check("тип техники в русском описании — по-русски",
      type_name("mini_excavator", "ru") == "Мини-экскаватор",
      type_name("mini_excavator", "ru"))
check("тип техники в узбекском описании — по-узбекски",
      type_name("mini_excavator", "uz") == "Mini ekskavator",
      type_name("mini_excavator", "uz"))
check("процента в доходе нет ни в одном языке",
      "%" not in ru and "%" not in uz, f"{ru} | {uz}")

ru_topup = t("tx.topup", "ru", method="click")
check("пополнение по-русски", "Пополнение" in ru_topup, ru_topup)

# Til noma'lum bo'lsa — sukut bo'yicha o'zbekcha, kalitning o'zi emas
fallback = t("tx.order_completed", None, order_id=1, what="X")
check("без языка возвращается текст, а не ключ",
      not fallback.startswith("tx."), fallback)


# ------------------------------------------------------------------ 2
head("2. КОДДА ЯШИРИН F-САТР ҚОЛМАДИ")

MONEY_SERVICES = [
    "app/services/order_service.py",
    "app/services/balance_service.py",
    "app/services/payout_service.py",
]
leftovers = []
percent = []
for rel in MONEY_SERVICES:
    path = os.path.join(BACKEND_DIR, rel)
    with open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            if re.search(r"description\s*=\s*f[\"']", line):
                leftovers.append(f"{rel}:{number}")
            if "90%" in line:
                percent.append(f"{rel}:{number}")

check("описание транзакции нигде не собирается f-строкой",
      not leftovers, ", ".join(leftovers))
check("упоминания '90%' в денежных сервисах нет",
      not percent, ", ".join(percent))

# Adminkadagi tur nomlari ro'yxati bazadagi turlarni TO'LIQ qoplashi kerak.
# Aks holda admin xom kodni ko'radi — "withdrawal" aynan shunday inglizcha
# bo'lib turardi, qolgan to'rttasi o'zbekcha bo'lgani holda.
from sqlalchemy import text  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402

session = SessionLocal()
try:
    db_types = {row[0] for row in session.execute(
        text("SELECT DISTINCT type FROM balance_transactions"))}
finally:
    session.close()

balance_php = os.path.join(BACKEND_DIR, "..", "admin", "balance.php")
with open(balance_php, encoding="utf-8") as handle:
    labels = set(re.findall(r"'(\w+)'\s*=>\s*'[^']*'", handle.read()))

missing_labels = sorted(db_types - labels)
check("у каждого типа транзакции есть подпись в админке",
      not missing_labels,
      f"без подписи: {missing_labels}")


# ------------------------------------------------------------------ 3
head("3. «МЕНИНГ» — ЖОЙЛАГАНИ ҲАМ, ЖАВОБ БЕРГАНИ ҲАМ")

client = token(CLIENT_PHONE)
owner = token(OWNER_PHONE)

created = requests.post(
    f"{API}/listings/",
    headers=client,
    json={"title": "verify_tx_language: tekshiruv e'loni",
          "description": "avtomatik test, o'zi bekor qilinadi"},
    timeout=15,
)
check("объявление создано", created.status_code in (200, 201), created.text[:160])
listing_id = created.json().get("id") if created.status_code in (200, 201) else None

if listing_id:
    taken = requests.post(f"{API}/listings/{listing_id}/take", headers=owner, timeout=15)
    check("исполнитель взял объявление", taken.status_code == 200, taken.text[:160])

    mine = requests.get(f"{API}/listings/mine", headers=owner, timeout=15).json()
    check("взятое объявление есть в «Мои» у исполнителя",
          any(item["id"] == listing_id for item in mine),
          f"вернулось {len(mine)} шт.")

    feed = requests.get(f"{API}/listings/feed", headers=owner, timeout=15).json()
    check("взятого объявления НЕТ на доске — иначе оно двоится",
          all(item["id"] != listing_id for item in feed),
          f"вернулось {len(feed)} шт.")

    mine_author = requests.get(f"{API}/listings/mine", headers=client, timeout=15).json()
    check("у автора оно тоже в «Мои»",
          any(item["id"] == listing_id for item in mine_author),
          f"вернулось {len(mine_author)} шт.")

    # tozalash — test idempotent bo'lishi kerak
    requests.post(f"{API}/listings/{listing_id}/cancel", headers=client, timeout=15)


head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
