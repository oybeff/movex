"""
Pul konturini tekshirish: narx serverda hisoblanadimi, hisob faqat tasdiqlangan
to'lovdan keyin to'ldiriladimi, buyurtma yakunlanganda pul mijozdan yechiladimi.

Test IDEMPOTENT: absolyut summalarga emas, o'zgarishlarga (delta) qaraydi,
shuning uchun bazani tozalamasdan qayta-qayta ishga tushirsa bo'ladi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_money.py
"""
import hashlib
import re
from datetime import datetime, timedelta

import requests

API = "http://127.0.0.1:8000"

# .env dagi mahalliy sinov kalitlari bilan bir xil bo'lishi kerak
CLICK_SERVICE_ID = "111111"
CLICK_SECRET_KEY = "local_dev_click_secret"

CLIENT_PHONE = "998901110002"
OWNER_PHONE = "998901110001"
EQUIPMENT_ID = 1
TOPUP = 5_000_000

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


def token(phone):
    r = requests.post(f"{API}/auth/send-otp", json={"phone": phone})
    code = re.search(r"(\d{4})\s*$", r.json()["message"]).group(1)
    r = requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": code})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def balance_of(hdr):
    b = requests.get(f"{API}/balance/me", headers=hdr).json()
    return float(b["balance"]), float(b["frozen_balance"])


def click_callback(path, click_trans_id, merchant_trans_id, amount, action, extra=None):
    """Click tomonidan yuboriladigan callback'ni imzosi bilan taqlid qilish."""
    sign_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    raw = (f"{click_trans_id}{CLICK_SERVICE_ID}{CLICK_SECRET_KEY}"
           f"{merchant_trans_id}{amount}{action}{sign_time}")
    payload = {
        "click_trans_id": click_trans_id,
        "service_id": CLICK_SERVICE_ID,
        "merchant_trans_id": merchant_trans_id,
        "amount": amount,
        "action": action,
        "error": 0,
        "error_note": "Success",
        "sign_time": sign_time,
        "sign_string": hashlib.md5(raw.encode()).hexdigest(),
    }
    if extra:
        payload.update(extra)
    return requests.post(f"{API}/balance/{path}", data=payload).json()


def free_dates(days=1):
    """Band bo'lmagan sanalar — testni qayta ishga tushirganda to'qnashmasligi uchun."""
    start = datetime.now() + timedelta(days=400 + datetime.now().microsecond % 2000)
    return start.strftime("%Y-%m-%d"), (start + timedelta(days=days)).strftime("%Y-%m-%d")


client = token(CLIENT_PHONE)
owner = token(OWNER_PHONE)

client_start, _ = balance_of(client)
owner_start, _ = balance_of(owner)
print(f"стартовые балансы — клиент {money(client_start)}, владелец {money(owner_start)}")

head("1. ПОПОЛНЕНИЕ ТРЕБУЕТ ПОДТВЕРЖДЁННОЙ ОПЛАТЫ")

# 'card' va 'cash' uchun to'lovni tasdiqlaydigan integratsiya yo'q, shuning
# uchun ular balansni to'ldira olmaydi. Click va Payme esa ruxsat etilgan.
for method in ("card", "cash"):
    r = requests.post(f"{API}/balance/topup", headers=client,
                      json={"amount": TOPUP, "payment_method": method})
    check(f"'{method}' без подтверждения оплаты отклонён", r.status_code == 400,
          f"вернулось {r.status_code}")

r = requests.post(f"{API}/balance/topup", headers=client,
                  json={"amount": TOPUP, "payment_method": "click"})
top = r.json()
check("заявка через Click создана", r.status_code == 200, r.text[:150])
check("транзакция в статусе pending", top.get("status") == "pending", str(top.get("status")))
check("ссылка на оплату сгенерирована", bool(top.get("payment_url")))

bal, _ = balance_of(client)
check("до подтверждения баланс не изменился", bal == client_start,
      f"было {money(client_start)}, стало {money(bal)}")

head("2. КОЛБЭК CLICK ЗАЧИСЛЯЕТ ДЕНЬГИ")

tx_id = top["transaction_id"]
amount = float(top["amount"])
click_id = 900000 + tx_id

prep = click_callback("click/prepare", click_id, tx_id, amount, 0)
check("prepare принят", prep.get("error") == 0, str(prep))

comp = click_callback("click/complete", click_id, tx_id, amount, 1,
                      extra={"merchant_prepare_id": prep.get("merchant_prepare_id", tx_id)})
check("complete принят", comp.get("error") == 0, str(comp))

bal, _ = balance_of(client)
check("баланс вырос ровно на сумму платежа", bal == client_start + TOPUP,
      f"ожидалось {money(client_start + TOPUP)}, получено {money(bal)}")

head("3. ЦЕНУ СЧИТАЕТ СЕРВЕР, А НЕ КЛИЕНТ")

eq = requests.get(f"{API}/equipment/{EQUIPMENT_ID}", headers=client).json()
day_price = float(eq["price_per_day"])
start_date, end_date = free_dates(days=1)   # двое суток: начало и конец включительно
print(f"  {eq['type']} {eq['model']}, {money(day_price)} сум/сутки, {start_date} — {end_date}")
print("  клиент шлёт заниженные цифры: total_amount=1000, commission=0")

order = requests.post(f"{API}/orders/", headers=client, json={
    "equipment_id": EQUIPMENT_ID,
    "start_date": start_date, "end_date": end_date,
    "total_amount": 1000, "commission": 0,
    "delivery_latitude": "41.31", "delivery_longitude": "69.28",
}).json()
check("заказ создан", "id" in order, str(order)[:200])

expected_subtotal = day_price * 2
expected_commission = round(expected_subtotal * 0.1)
total = float(order["total_amount"])
commission = float(order["commission"])
delivery = float(order.get("delivery_fee") or 0)
print(f"  сервер: аренда {money(expected_subtotal)} + комиссия {money(commission)} "
      f"+ доставка {money(delivery)} = {money(total)}")

check("присланная клиентом сумма проигнорирована", total != 1000, f"total={total}")
# Ulush endi MIJOZNING summasiga qo'shilmaydi: u qat'iy (5 000 so'm) va
# buyurtma yakunlanganda EGASINING pulidan ushlanadi. Mijoz faqat ijara va
# yetkazib berish uchun to'laydi.
check("комиссия посчитана сервером, а не прислана клиентом",
      commission > 0 and commission != 1, f"получено {commission}")
check("доставка посчитана по координатам", delivery > 0)
check("клиент платит только аренду и доставку, без комиссии",
      total == expected_subtotal + delivery,
      f"{total} != {expected_subtotal} + {delivery}")
check("комиссия НЕ добавлена к сумме клиента",
      total < expected_subtotal + commission + delivery or commission == 0,
      f"total={total}, commission={commission}")
check("заморожена именно серверная сумма", float(order["frozen_amount"]) == total)
check("комиссия не превышает сумму заказа", commission <= total,
      f"комиссия {commission} > заказ {total}")

head("4. ПОСЛЕ ЗАВЕРШЕНИЯ СДЕЛКИ ДЕНЬГИ СХОДЯТСЯ")

client_before, frozen_before = balance_of(client)
owner_before, _ = balance_of(owner)

requests.put(f"{API}/orders/{order['id']}", headers=owner, json={"status": "confirmed"})
r = requests.put(f"{API}/orders/{order['id']}", headers=owner, json={"status": "completed"})
check("заказ завершён", r.status_code == 200 and r.json().get("status") == "completed",
      r.text[:150])

client_after, client_frozen = balance_of(client)
owner_after, _ = balance_of(owner)

check("с клиента списана полная сумма заказа", client_after == client_before - total,
      f"ожидалось {money(client_before - total)}, получено {money(client_after)}")
# frozen_before уже включает заморозку этого заказа — после завершения
# она снимается, остальное (чужие незавершённые заказы) остаётся как было
check("заморозка по этому заказу снята", client_frozen == frozen_before - total,
      f"ожидалось {money(frozen_before - total)}, осталось {money(client_frozen)}")
check("владелец получил сумму за вычетом комиссии", owner_after == owner_before + total - commission,
      f"ожидалось {money(owner_before + total - commission)}, получено {money(owner_after)}")

# Sistema bo'yicha pul saqlanishi: kirim (topup) = balanslar o'sishi + komissiya
system_delta = (client_after - client_start) + (owner_after - owner_start) + commission
print(f"\n  внесено через Click:            {money(TOPUP):>12}")
print(f"  прирост балансов + комиссия:    {money(system_delta):>12}")
check("деньги не создаются и не исчезают", abs(system_delta - TOPUP) < 0.01,
      f"расхождение {money(system_delta - TOPUP)}")

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
