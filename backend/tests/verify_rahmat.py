"""
Rahmat (Multicard) — to'liq tranzaksiya: kimdan kimga va nima bo'lganda.

Nimani tekshiradi:

  1. Loyihada BOSHQA to'lov tizimi qolmagan: Click va Payme kodi ham,
     manzillari ham yo'q. Aks holda "olib tashlandi" degan gap rost
     bo'lmasdi, va eski yo'l bilan pul kirishi mumkin bo'lardi.
  2. Summa so'm <-> tiyin BITTA joyda o'giriladi va nolni yo'qotmaydi.
  3. Imzo tekshiruvi: to'g'ri imzo o'tadi, buzilgan imzo O'TMAYDI.
     Callback manzili ochiq, ya'ni bu yagona himoya.
  4. To'liq yo'l: ariza -> chekaut havolasi -> callback -> balans ortdi.
  5. IDEMPOTENTLIK: takroriy callback pulni ikkinchi marta yozmaydi.
     Multicard callback'ni qaytaradi va hujjat buni talab qiladi.
  6. Vebhuk holatlari: 'progress' balansga tegmaydi, 'success' yozadi,
     'revert' esa yozilgan pulni QAYTARIB OLADI.
  7. Chet tranzaksiya: soxta summa bilan kelgan callback rad etiladi.
  8. Kartaga pul chiqarish (payouts) — sinov kartasiga haqiqiy o'tkazma,
     va uning natijasi egasining balansiga to'g'ri tushishi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_rahmat.py
"""
import os
import re
import sys
from decimal import Decimal

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import _topup
from _auth import token

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

API = "http://127.0.0.1:8000"

CLIENT_PHONE = "998901110002"
OWNER_PHONE = "998901110001"
ADMIN_PHONE = "998900000000"

TOPUP = 120_000

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
    print(f"\n{'=' * 66}\n{title}\n{'=' * 66}")


def money(value):
    return f"{float(value):,.0f}".replace(",", " ")


def balance_of(headers):
    data = requests.get(f"{API}/balance/me", headers=headers).json()
    return Decimal(str(data["balance"])), Decimal(str(data["frozen_balance"]))


# ------------------------------------------------------------------ 1

head("1. CLICK VA PAYME LOYIHADAN KETGAN")

APP_DIR = os.path.join(BACKEND_DIR, "app")

removed_files = [
    "services/click_service.py",
    "services/payme_service.py",
    "routes/payme.py",
]
for relative in removed_files:
    check(
        f"{relative} o'chirilgan",
        not os.path.exists(os.path.join(APP_DIR, relative)),
        "fayl hali joyida",
    )

# Kodda bu tizimlarning chaqiruvi qolmaganini tekshiramiz. Izohlarda
# ularning nomi UCHRAYDI (nega olib tashlangani yozilgan), shuning uchun
# izohlar hisobga olinmaydi — faqat haqiqiy kod satrlari.
suspicious = []
for root, _dirs, files in os.walk(APP_DIR):
    if "__pycache__" in root:
        continue
    for name in files:
        if not name.endswith(".py"):
            continue
        path = os.path.join(root, name)
        with open(path, encoding="utf-8") as handle:
            for number, line in enumerate(handle, 1):
                code = line.split("#", 1)[0]
                if re.search(r"\b(ClickService|PaymeService|click_service|payme_service)\b", code):
                    suspicious.append(f"{path}:{number}")

check("kodda ClickService/PaymeService chaqiruvi yo'q", not suspicious, "; ".join(suspicious))

from app.services import payment_providers

check(
    "to'lov usullari ro'yxatida faqat 'rahmat'",
    payment_providers.SELF_SERVICE_PAYMENT_METHODS == {"rahmat"},
    str(payment_providers.SELF_SERVICE_PAYMENT_METHODS),
)

# Manzil yo'qligini holat kodi bilan tekshiramiz. 405 ham "yo'q" degani:
# /payments/payme yo'li /payments/{payment_id} qolipiga tushib qoladi, va
# u POST'ni qabul qilmaydi. Muhimi — 200 qaytmasligi, ya'ni eski yo'l
# bilan pul kirmasligi.
for path in ("/balance/click/prepare", "/balance/click/complete", "/payments/payme"):
    response = requests.post(f"{API}{path}", json={})
    check(
        f"{path} manzili yo'q",
        response.status_code in (404, 405, 422),
        f"qaytdi {response.status_code}",
    )

# ------------------------------------------------------------------ 2

head("2. SUMMA: SO'M <-> TIYIN")

from app.services.rahmat_service import to_sum, to_tiyin

check("1 so'm = 100 tiyin", to_tiyin(1) == 100, str(to_tiyin(1)))
check("120 000 so'm = 12 000 000 tiyin", to_tiyin(120_000) == 12_000_000, str(to_tiyin(120_000)))
check("tiyinlar yo'qolmaydi", to_tiyin("12500.50") == 1_250_050, str(to_tiyin("12500.50")))
check("teskari o'girish", to_sum(1_250_050) == Decimal("12500.50"), str(to_sum(1_250_050)))
check(
    "o'girish qaytib kelganda o'zgarmaydi",
    to_sum(to_tiyin("99999.99")) == Decimal("99999.99"),
    str(to_sum(to_tiyin("99999.99"))),
)

# ------------------------------------------------------------------ 3

head("3. IMZO")

from app.core.config import settings
from app.services import rahmat_service

check("kalitlar sozlangan", settings.rahmat_configured,
      "backend/.env da RAHMAT_* va RAHMAT_CALLBACK_BASE_URL to'ldirilishi kerak")

if not settings.rahmat_configured:
    print("\nRahmat sozlanmagan — qolgan tekshiruvlar bajarilmaydi")
    print(f"\nИТОГ: {ok_count} пройдено, {fail_count} провалено")
    sys.exit(1)

good = _topup.callback_sign(settings.RAHMAT_STORE_ID, 42, 100_000)
check(
    "to'g'ri callback imzosi o'tadi",
    rahmat_service.verify_callback_sign(
        store_id=settings.RAHMAT_STORE_ID, invoice_id=42,
        amount_tiyin=100_000, sign=good,
    ),
)
check(
    "buzilgan callback imzosi o'tmaydi",
    not rahmat_service.verify_callback_sign(
        store_id=settings.RAHMAT_STORE_ID, invoice_id=42,
        amount_tiyin=100_000, sign="0" * 32,
    ),
)
check(
    "boshqa summa uchun imzo o'tmaydi",
    not rahmat_service.verify_callback_sign(
        store_id=settings.RAHMAT_STORE_ID, invoice_id=42,
        amount_tiyin=999_999, sign=good,
    ),
)

webhook_good = _topup.webhook_sign("uuid-1", 42, 100_000)
check(
    "to'g'ri vebhuk imzosi o'tadi",
    rahmat_service.verify_webhook_sign(
        uuid="uuid-1", invoice_id=42, amount_tiyin=100_000, sign=webhook_good
    ),
)
check(
    "buzilgan vebhuk imzosi o'tmaydi",
    not rahmat_service.verify_webhook_sign(
        uuid="uuid-1", invoice_id=42, amount_tiyin=100_000, sign="0" * 40
    ),
)

# ------------------------------------------------------------------ 4

head("4. TO'LIQ YO'L: ARIZA -> CHEKAUT -> CALLBACK -> BALANS")

client = token(CLIENT_PHONE, API)
start_balance, _ = balance_of(client)

methods = requests.get(f"{API}/balance/methods", headers=client).json()
check("ilovaga berilgan usul bittagina", len(methods) == 1, str(methods))
check("va u 'rahmat'", methods and methods[0]["code"] == "rahmat", str(methods))

started = _topup.start_topup(client, TOPUP, API)
check("tranzaksiya 'pending'", started["status"] == "pending", str(started["status"]))
check("chekaut havolasi bor", bool(started.get("payment_url")), str(started))
check(
    "havola Multicard sahifasiga ishora qiladi",
    "rhmt.uz" in (started.get("payment_url") or "")
    or "multicard" in (started.get("payment_url") or ""),
    str(started.get("payment_url")),
)

transaction_id = started["transaction_id"]

balance_now, _ = balance_of(client)
check("to'lovdan oldin balans o'zgarmadi", balance_now == start_balance,
      f"{money(start_balance)} -> {money(balance_now)}")

# Soxta summa: shlyuz nomidan kelgan bo'lsa ham, tranzaksiyadagi summaga
# mos kelmasa, hech narsa yozilmaydi.
wrong = _topup.send_callback(transaction_id, TOPUP * 5, API)
check("chet summa bilan callback rad etildi", wrong.get("success") is False, str(wrong))
balance_now, _ = balance_of(client)
check("chet summa balansga tegmadi", balance_now == start_balance, money(balance_now))

result = _topup.send_callback(transaction_id, TOPUP, API)
check("callback qabul qilindi", result.get("success") is True, str(result))

balance_now, _ = balance_of(client)
check(
    "balans aynan to'lov summasiga oshdi",
    balance_now == start_balance + Decimal(TOPUP),
    f"kutilgan {money(start_balance + TOPUP)}, olingan {money(balance_now)}",
)

# ------------------------------------------------------------------ 5

head("5. TAKRORIY CALLBACK PULNI IKKI MARTA YOZMAYDI")

repeat = _topup.send_callback(transaction_id, TOPUP, API)
check("takroriy callback ham qabul qilindi", repeat.get("success") is True, str(repeat))
balance_now, _ = balance_of(client)
check(
    "balans o'zgarmadi",
    balance_now == start_balance + Decimal(TOPUP),
    f"kutilgan {money(start_balance + TOPUP)}, olingan {money(balance_now)}",
)

# ------------------------------------------------------------------ 6

head("6. VEBHUK HOLATLARI")

# Yangi tranzaksiya: vebhuk yo'li bilan boshidan oxirigacha.
before, _ = balance_of(client)
second = _topup.start_topup(client, TOPUP, API)
second_id = second["transaction_id"]

detail = requests.get(f"{API}/balance/transactions/{second_id}", headers=client).json()
uuid = None
listed = requests.get(f"{API}/balance/transactions", headers=client).json()
for row in listed if isinstance(listed, list) else []:
    if row.get("id") == second_id:
        detail = row
        break

# uuid ochiq API'da qaytmaydi (u shlyuzning ichki raqami), shuning uchun
# bazadan o'qiymiz — test shu mashinada, baza yonida ishlaydi.
from sqlalchemy import text

from app.db.session import SessionLocal

db = SessionLocal()
try:
    uuid = db.execute(
        text("SELECT rahmat_uuid FROM balance_transactions WHERE id = :i"),
        {"i": second_id},
    ).scalar()
finally:
    db.close()

check("invoys uuid tranzaksiyaga yozildi", bool(uuid), str(uuid))

progress = _topup.send_webhook(uuid, second_id, TOPUP, "progress", API)
check("'progress' qabul qilindi", progress.get("success") is True, str(progress))
balance_now, _ = balance_of(client)
check("'progress' balansga tegmadi", balance_now == before, money(balance_now))

success = _topup.send_webhook(uuid, second_id, TOPUP, "success", API)
check("'success' qabul qilindi", success.get("success") is True, str(success))
balance_now, _ = balance_of(client)
check(
    "'success' pulni yozdi",
    balance_now == before + Decimal(TOPUP),
    f"kutilgan {money(before + TOPUP)}, olingan {money(balance_now)}",
)

revert = _topup.send_webhook(uuid, second_id, TOPUP, "revert", API)
check("'revert' qabul qilindi", revert.get("success") is True, str(revert))
balance_now, _ = balance_of(client)
check(
    "'revert' pulni qaytarib oldi",
    balance_now == before,
    f"kutilgan {money(before)}, olingan {money(balance_now)}",
)

unsigned = requests.post(f"{API}/balance/rahmat/webhook", json={
    "uuid": uuid, "invoice_id": str(second_id),
    "amount": to_tiyin(TOPUP), "status": "success", "sign": "0" * 40,
}).json()
check("imzosiz vebhuk rad etildi", unsigned.get("success") is False, str(unsigned))

# ------------------------------------------------------------------ 7

head("7. KARTAGA PUL CHIQARISH")

owner = token(OWNER_PHONE, API)
admin = token(ADMIN_PHONE, API)

# Sinov kartasi — hujjatdagi. Jangovar muhitda bu yerda haqiqiy karta
# turadi, shuning uchun test faqat sinov stendida ishlaydi.
TEST_CARD = "8600533364098829"
PAYOUT_SUM = 60_000

_topup.topup(owner, 300_000, API)
owner_before, owner_frozen_before = balance_of(owner)

created = requests.post(f"{API}/payouts/", headers=owner, json={
    "amount": PAYOUT_SUM,
    "card_number": TEST_CARD,
    "card_holder": "TEST OWNER",
}).json()
check("ariza yaratildi", bool(created.get("id")), str(created))

request_id = created.get("id")
owner_now, owner_frozen = balance_of(owner)
check(
    "summa muzlatildi",
    owner_frozen == owner_frozen_before + Decimal(PAYOUT_SUM),
    f"{money(owner_frozen_before)} -> {money(owner_frozen)}",
)
check("balans hali kamaymadi", owner_now == owner_before, money(owner_now))

paid = requests.post(f"{API}/payouts/{request_id}/paid", headers=admin, json={})
paid_data = paid.json() if paid.status_code == 200 else {}
check("o'tkazma bajarildi", paid.status_code == 200, f"{paid.status_code} {paid.text[:200]}")
check("ariza 'paid'", paid_data.get("status") == "paid", str(paid_data.get("status")))
check(
    "shlyuz holati 'success'",
    paid_data.get("rahmat_status") == "success",
    str(paid_data.get("rahmat_status")),
)
check("chek havolasi bor", bool(paid_data.get("rahmat_receipt_url")), str(paid_data))

owner_now, owner_frozen = balance_of(owner)
check(
    "balansdan to'liq summa yechildi",
    owner_now == owner_before - Decimal(PAYOUT_SUM),
    f"kutilgan {money(owner_before - PAYOUT_SUM)}, olingan {money(owner_now)}",
)
check(
    "muzlatish olib tashlandi",
    owner_frozen == owner_frozen_before,
    f"{money(owner_frozen_before)} -> {money(owner_frozen)}",
)
check(
    "kartaga komissiyasiz qism ketdi",
    float(paid_data.get("payout_amount", 0))
    == PAYOUT_SUM - float(paid_data.get("commission", 0)),
    str(paid_data),
)

# Ikkinchi marta to'lash mumkin emas: aks holda bir arizaga pul ikki
# marta ketardi.
again = requests.post(f"{API}/payouts/{request_id}/paid", headers=admin, json={})
check("to'langan arizani qayta o'tkazib bo'lmaydi", again.status_code == 400,
      f"qaytdi {again.status_code}")

# ------------------------------------------------------------------ 8

head("8. ICHKI MANZIL HIMOYASI")

no_secret = requests.post(f"{API}/payouts/internal/{request_id}/pay", json={})
check(
    "maxfiy so'zsiz ichki manzil ish bermaydi",
    no_secret.status_code in (403, 404),
    f"qaytdi {no_secret.status_code}",
)

wrong_secret = requests.post(
    f"{API}/payouts/internal/{request_id}/pay",
    json={},
    headers={"X-Admin-Secret": "noto'g'ri"},
)
check(
    "noto'g'ri maxfiy so'z rad etiladi",
    wrong_secret.status_code in (403, 404),
    f"qaytdi {wrong_secret.status_code}",
)

print(f"\n{'=' * 66}")
print(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
print("=" * 66)

sys.exit(1 if fail_count else 0)
