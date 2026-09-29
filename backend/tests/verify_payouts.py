"""
Pul yechish arizalarini tekshirish.

Asosiy talab: pul ikki marta so'ralib olinmasin va karta raqami ochiq
API'da hech qachon to'liq qaytmasin.

Test IDEMPOTENT — bazani tozalamasdan qayta ishga tushirsa bo'ladi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_payouts.py
"""
import os
import sys
import re
from datetime import datetime

import requests

from _topup import topup as _rahmat_topup

API = "http://127.0.0.1:8000"

OWNER_PHONE = "998901110001"
ADMIN_PHONE = "998900000000"
CLIENT_PHONE = "998901110002"

# Multicard sinov kartasi (hujjatdan). Bu MUHIM: pul endi haqiqatan
# shlyuz orqali ketadi, va o'ylab topilgan raqam ERROR_CARD_NOT_FOUND
# beradi. Jangovar muhitda testni bu ko'rinishda ishga tushirmaydi —
# u faqat sinov stendi uchun.
CARD = "8600533364098829"

ok_count = 0
fail_count = 0


def money(x):
    return f"{float(x):,.0f}".replace(",", " ")


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


# Kirish _auth.py da: admin kodi javobda kelmaydi va bazadan o'qiladi.
# Sababi o'sha faylda yozilgan.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import token  # noqa: E402


def balance_of(hdr):
    b = requests.get(f"{API}/balance/me", headers=hdr).json()
    return float(b["balance"]), float(b["frozen_balance"])


def topup_via_gateway(hdr, amount):
    """
    Hisob to'ldirish — Rahmat (Multicard) orqali.

    Mantiq _topup.py da: ilgari bu funksiya har bir testda o'z nusxasi
    bilan turardi va to'lov tizimi almashganda oltita joyni tuzatish
    kerak bo'ldi.
    """
    return _rahmat_topup(hdr, amount, API)


owner = token(OWNER_PHONE)
admin = token(ADMIN_PHONE)
client = token(CLIENT_PHONE)

# Egasida yetarli pul bo'lishi uchun hisobini to'ldiramiz
topup_via_gateway(owner, 1_000_000)
start_balance, start_frozen = balance_of(owner)
print(f"баланс владельца: {money(start_balance)}, заморожено {money(start_frozen)}")

head("1. ПРОВЕРКИ ПРИ СОЗДАНИИ ЗАЯВКИ")

r = requests.post(f"{API}/payouts/", headers=owner,
                  json={"amount": 10_000, "card_number": CARD})
check("сумма ниже минимума отклонена", r.status_code == 400, f"{r.status_code} {r.text[:120]}")

r = requests.post(f"{API}/payouts/", headers=owner,
                  json={"amount": 999_000_000, "card_number": CARD})
check("сумма больше доступной отклонена", r.status_code == 400, f"{r.status_code} {r.text[:120]}")

r = requests.post(f"{API}/payouts/", headers=owner,
                  json={"amount": 100_000, "card_number": "123"})
check("короткий номер карты отклонён", r.status_code == 422, f"{r.status_code}")

r = requests.post(f"{API}/payouts/", headers=client,
                  json={"amount": 100_000, "card_number": CARD})
check("клиент не может запросить вывод", r.status_code == 403, f"{r.status_code}")

head("2. ЗАЯВКА СОЗДАНА — ДЕНЬГИ ЗАМОРОЖЕНЫ")

AMOUNT = 200_000
r = requests.post(f"{API}/payouts/", headers=owner,
                  json={"amount": AMOUNT, "card_number": CARD, "card_holder": "ALISHER"})
check("заявка создана", r.status_code == 200, f"{r.status_code} {r.text[:200]}")
req = r.json()
req_id = req["id"]

check("статус pending", req["status"] == "pending", str(req.get("status")))
check("номер карты замаскирован", req["card_masked"] == f"•••• {CARD[-4:]}",
      str(req.get("card_masked")))
check("полный номер карты НЕ возвращается", CARD not in r.text, "номер утёк в ответе")

bal, frozen = balance_of(owner)
check("баланс не изменился", bal == start_balance, f"{money(bal)} vs {money(start_balance)}")
check("сумма заморожена", frozen == start_frozen + AMOUNT,
      f"ожидалось {money(start_frozen + AMOUNT)}, получено {money(frozen)}")

head("3. ПОВТОРНАЯ ЗАЯВКА НЕ БЕРЁТ ТЕ ЖЕ ДЕНЬГИ")

available = bal - frozen
r = requests.post(f"{API}/payouts/", headers=owner,
                  json={"amount": available + 1000, "card_number": CARD})
check("нельзя запросить больше остатка с учётом заморозки", r.status_code == 400,
      f"{r.status_code} {r.text[:120]}")

head("4. АДМИН ПОДТВЕРЖДАЕТ ВЫПЛАТУ")

r = requests.get(f"{API}/payouts/all?status=pending", headers=owner)
check("владелец не видит чужие заявки", r.status_code == 403, f"{r.status_code}")

r = requests.get(f"{API}/payouts/all?status=pending", headers=admin)
check("админ видит список заявок", r.status_code == 200, f"{r.status_code}")
check("наша заявка в списке", any(x["id"] == req_id for x in r.json()))
check("в списке админа карта тоже замаскирована", CARD not in r.text)

r = requests.post(f"{API}/payouts/{req_id}/paid", headers=owner, json={})
check("владелец не может подтвердить выплату сам", r.status_code == 403, f"{r.status_code}")

r = requests.post(f"{API}/payouts/{req_id}/paid", headers=admin,
                  json={"admin_comment": "переведено"})
check("админ подтвердил выплату", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
check("статус paid", r.json().get("status") == "paid", str(r.json().get("status")))

bal2, frozen2 = balance_of(owner)
check("баланс уменьшился на сумму выплаты", bal2 == bal - AMOUNT,
      f"ожидалось {money(bal - AMOUNT)}, получено {money(bal2)}")
check("заморозка снята", frozen2 == start_frozen,
      f"ожидалось {money(start_frozen)}, получено {money(frozen2)}")

txs = requests.get(f"{API}/balance/transactions", headers=owner).json()
check("создана транзакция типа withdrawal",
      any(t["type"] == "withdrawal" and float(t["amount"]) == AMOUNT for t in txs))

r = requests.post(f"{API}/payouts/{req_id}/paid", headers=admin, json={})
check("повторное подтверждение отклонено", r.status_code == 400, f"{r.status_code}")

head("5. АДМИН ОТКЛОНЯЕТ ЗАЯВКУ — ДЕНЬГИ ОСТАЮТСЯ")

bal3, frozen3 = balance_of(owner)
r = requests.post(f"{API}/payouts/", headers=owner,
                  json={"amount": AMOUNT, "card_number": CARD})
check("вторая заявка создана", r.status_code == 200, r.text[:150])
req2_id = r.json()["id"]

r = requests.post(f"{API}/payouts/{req2_id}/reject", headers=admin,
                  json={"admin_comment": "неверная карта"})
check("админ отклонил", r.status_code == 200 and r.json()["status"] == "rejected", r.text[:150])

bal4, frozen4 = balance_of(owner)
check("баланс не изменился после отказа", bal4 == bal3, f"{money(bal4)} vs {money(bal3)}")
check("заморозка снята после отказа", frozen4 == frozen3,
      f"ожидалось {money(frozen3)}, получено {money(frozen4)}")

head("6. КОМИССИЯ ЗА ВЫВОД — ПЛАТИТ ВЛАДЕЛЕЦ")


def set_payout_setting(key, value):
    """Настройка меняется админским API — тем же путём, что и из панели."""
    return requests.put(f"{API}/settings/app-settings/{key}", headers=admin,
                        json={"value": value})


def payout_settings():
    return requests.get(f"{API}/payouts/settings", headers=owner).json()


# Исходные значения запоминаем и возвращаем в конце: тест идемпотентный,
# после него стенд должен работать как прежде.
saved = payout_settings()

r = requests.get(f"{API}/payouts/settings", headers=owner)
check("условия вывода отдаются владельцу", r.status_code == 200, f"{r.status_code}")
conditions = r.json()
check("в условиях есть режим, фикс, процент и минимум",
      all(k in conditions for k in ("mode", "fixed", "percent", "min_amount")),
      str(conditions))

# --- режим "фикс" -------------------------------------------------------
set_payout_setting("payout_commission_mode", "fixed")
set_payout_setting("payout_commission_fixed", "5000")

bal5, frozen5 = balance_of(owner)
r = requests.post(f"{API}/payouts/", headers=owner,
                  json={"amount": AMOUNT, "card_number": CARD})
check("заявка при фиксированной комиссии создана", r.status_code == 200, r.text[:150])
fixed_req = r.json()

check("комиссия = 5 000", float(fixed_req["commission"]) == 5000,
      str(fixed_req.get("commission")))
check("на карту = сумма минус комиссия",
      float(fixed_req["payout_amount"]) == AMOUNT - 5000,
      f"ожидалось {money(AMOUNT - 5000)}, получено {money(fixed_req['payout_amount'])}")

bal6, frozen6 = balance_of(owner)
check("заморожена ПОЛНАЯ сумма заявки, а не сумма к перечислению",
      frozen6 == frozen5 + AMOUNT,
      f"ожидалось {money(frozen5 + AMOUNT)}, получено {money(frozen6)}")

r = requests.post(f"{API}/payouts/{fixed_req['id']}/paid", headers=admin, json={})
check("выплата подтверждена", r.status_code == 200, r.text[:150])

bal7, _ = balance_of(owner)
check("с баланса списана ПОЛНАЯ сумма, комиссия осталась платформе",
      bal7 == bal6 - AMOUNT,
      f"ожидалось {money(bal6 - AMOUNT)}, получено {money(bal7)}")

txs = requests.get(f"{API}/balance/transactions", headers=owner).json()
withdrawal = next((t for t in txs if t["type"] == "withdrawal"), None)
check("в описании транзакции видно и сумму на карту, и комиссию",
      withdrawal is not None and "195 000" in (withdrawal.get("description") or "")
      and "5 000" in (withdrawal.get("description") or ""),
      str(withdrawal.get("description") if withdrawal else None))

# --- режим "процент" ----------------------------------------------------
set_payout_setting("payout_commission_mode", "percent")
set_payout_setting("payout_commission_percent", "10")
check("режим переключился на процент", payout_settings()["mode"] == "percent",
      str(payout_settings()))

r = requests.post(f"{API}/payouts/", headers=owner,
                  json={"amount": AMOUNT, "card_number": CARD})
check("заявка при процентной комиссии создана", r.status_code == 200, r.text[:150])
percent_req = r.json()
check("комиссия = 10% от суммы", float(percent_req["commission"]) == AMOUNT * 0.10,
      f"ожидалось {money(AMOUNT * 0.10)}, получено {money(percent_req['commission'])}")
check("на карту = 90% суммы", float(percent_req["payout_amount"]) == AMOUNT * 0.90,
      str(percent_req.get("payout_amount")))

requests.post(f"{API}/payouts/{percent_req['id']}/reject", headers=admin, json={})

# --- комиссия не может съесть всю сумму ---------------------------------
set_payout_setting("payout_commission_mode", "fixed")
set_payout_setting("payout_commission_fixed", "500000")

_, frozen_before = balance_of(owner)
r = requests.post(f"{API}/payouts/", headers=owner,
                  json={"amount": 100_000, "card_number": CARD})
check("заявка отклонена, если комиссия не меньше суммы", r.status_code == 400,
      f"{r.status_code} {r.text[:150]}")

_, frozen_after = balance_of(owner)
check("отклонённая заявка ничего не заморозила", frozen_after == frozen_before,
      f"было {money(frozen_before)}, стало {money(frozen_after)}")

# --- старые заявки не пересчитываются ------------------------------------
r = requests.get(f"{API}/payouts/", headers=owner)
old = next((x for x in r.json() if x["id"] == fixed_req["id"]), None)
check("старая заявка сохранила свою комиссию после смены настроек",
      old is not None and float(old["commission"]) == 5000,
      str(old.get("commission") if old else None))

# --- возвращаем как было -------------------------------------------------
set_payout_setting("payout_commission_mode", saved["mode"])
set_payout_setting("payout_commission_fixed", str(int(saved["fixed"])))
set_payout_setting("payout_commission_percent", str(int(saved["percent"])))
restored = payout_settings()
check("настройки возвращены к исходным",
      restored["mode"] == saved["mode"] and restored["fixed"] == saved["fixed"],
      f"{restored} vs {saved}")

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
