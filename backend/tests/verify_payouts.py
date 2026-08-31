"""
Pul yechish arizalarini tekshirish.

Asosiy talab: pul ikki marta so'ralib olinmasin va karta raqami ochiq
API'da hech qachon to'liq qaytmasin.

Test IDEMPOTENT — bazani tozalamasdan qayta ishga tushirsa bo'ladi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_payouts.py
"""
import hashlib
import os
import sys
import re
from datetime import datetime

import requests

API = "http://127.0.0.1:8000"

OWNER_PHONE = "998901110001"
ADMIN_PHONE = "998900000000"
CLIENT_PHONE = "998901110002"

CARD = "8600123412341234"
CLICK_SERVICE_ID = "111111"
CLICK_SECRET_KEY = "local_dev_click_secret"

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


def topup_via_click(hdr, amount, click_id):
    """Egasining hisobini to'ldirish — to'liq Click yo'li bilan."""
    tx = requests.post(f"{API}/balance/topup", headers=hdr,
                       json={"amount": amount, "payment_method": "click"}).json()
    tx_id, amt = tx["transaction_id"], float(tx["amount"])

    def cb(path, action, extra=None):
        st = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        raw = f"{click_id}{CLICK_SERVICE_ID}{CLICK_SECRET_KEY}{tx_id}{amt}{action}{st}"
        body = {"click_trans_id": click_id, "service_id": CLICK_SERVICE_ID,
                "merchant_trans_id": tx_id, "amount": amt, "action": action,
                "error": 0, "error_note": "Success", "sign_time": st,
                "sign_string": hashlib.md5(raw.encode()).hexdigest()}
        if extra:
            body.update(extra)
        return requests.post(f"{API}/balance/{path}", data=body).json()

    prep = cb("click/prepare", 0)
    cb("click/complete", 1, {"merchant_prepare_id": prep.get("merchant_prepare_id", tx_id)})


owner = token(OWNER_PHONE)
admin = token(ADMIN_PHONE)
client = token(CLIENT_PHONE)

# Egasida yetarli pul bo'lishi uchun hisobini to'ldiramiz
topup_via_click(owner, 1_000_000, 950000 + int(datetime.now().timestamp()) % 10000)
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
check("номер карты замаскирован", req["card_masked"] == "•••• 1234", str(req.get("card_masked")))
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

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
