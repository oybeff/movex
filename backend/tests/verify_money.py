"""
Pul konturini tekshirish: narx serverda hisoblanadimi, hisob faqat tasdiqlangan
to'lovdan keyin to'ldiriladimi, buyurtma yakunlanganda pul mijozdan yechiladimi.

Test IDEMPOTENT: absolyut summalarga emas, o'zgarishlarga (delta) qaraydi,
shuning uchun bazani tozalamasdan qayta-qayta ishga tushirsa bo'ladi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_money.py
"""
import random
import re
from datetime import datetime, timedelta

import requests

import _topup

API = "http://127.0.0.1:8000"


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


def free_dates(days=1, equipment_id=None, headers=None):
    """
    Band bo'lmagan sanalar.

    Ilgari sana joriy vaqtdan tasodifiy siljish bilan olinardi. Testlar ko'p
    marta ishlagach bazada yuzlab buyurtma to'planadi va siljish oralig'i
    to'lib qoladi — "bu sanada texnika band" xatosi chiqadi. Bu mahsulot
    xatosi emas, test o'zini o'zi bloklaydi.

    Endi oraliq ancha keng va tasodifiy; band bo'lsa boshqa sana olinadi.
    """
    for _ in range(25):
        offset = random.randint(500, 30000)
        start = datetime.now() + timedelta(days=offset)
        s = start.strftime("%Y-%m-%d")
        e = (start + timedelta(days=days)).strftime("%Y-%m-%d")
        if equipment_id is None or headers is None:
            return s, e
        busy = requests.get(
            f"{API}/orders/", headers=headers, params={"limit": 100}
        ).json()
        clash = any(
            o.get("equipment_id") == equipment_id
            and o.get("status") in ("pending", "confirmed")
            and o.get("start_date", "") <= e
            and o.get("end_date", "") >= s
            for o in (busy if isinstance(busy, list) else [])
        )
        if not clash:
            return s, e
    return s, e


client = token(CLIENT_PHONE)
owner = token(OWNER_PHONE)

client_start, _ = balance_of(client)
owner_start, _ = balance_of(owner)
print(f"стартовые балансы — клиент {money(client_start)}, владелец {money(owner_start)}")

head("1. ПОПОЛНЕНИЕ ТРЕБУЕТ ПОДТВЕРЖДЁННОЙ ОПЛАТЫ")

# Подтверждения оплаты нет ни у 'card', ни у 'cash', ни у убранных
# 'click'/'payme' — балансу они недоступны. Единственный разрешённый
# способ — 'rahmat': по нему приходит подтверждение от шлюза.
for method in ("card", "cash", "click", "payme"):
    r = requests.post(f"{API}/balance/topup", headers=client,
                      json={"amount": TOPUP, "payment_method": method})
    check(f"'{method}' без подтверждения оплаты отклонён", r.status_code == 400,
          f"вернулось {r.status_code}")

top = _topup.start_topup(client, TOPUP, API)
check("заявка через Rahmat создана", bool(top.get("transaction_id")), str(top))
check("транзакция в статусе pending", top.get("status") == "pending", str(top.get("status")))
check("ссылка на оплату сгенерирована", bool(top.get("payment_url")))

bal, _ = balance_of(client)
check("до подтверждения баланс не изменился", bal == client_start,
      f"было {money(client_start)}, стало {money(bal)}")

head("2. КОЛБЭК RAHMAT ЗАЧИСЛЯЕТ ДЕНЬГИ")

tx_id = top["transaction_id"]
amount = float(top["amount"])

# Колбэк без подписи не должен зачислять ничего: этот адрес открытый,
# и без проверки подписи любой пополнил бы себе баланс запросом.
unsigned = requests.post(f"{API}/balance/rahmat/callback", json={
    "store_id": 6, "invoice_id": str(tx_id),
    "amount": _topup.to_tiyin(amount), "sign": "0" * 32,
}).json()
check("колбэк с неверной подписью отклонён", unsigned.get("success") is False,
      str(unsigned))

bal, _ = balance_of(client)
check("после неверной подписи баланс не изменился", bal == client_start,
      f"стало {money(bal)}")

cb = _topup.send_callback(tx_id, amount, API)
check("колбэк принят", cb.get("success") is True, str(cb))

bal, _ = balance_of(client)
check("баланс вырос ровно на сумму платежа", bal == client_start + TOPUP,
      f"ожидалось {money(client_start + TOPUP)}, получено {money(bal)}")

# Multicard повторяет колбэк после таймаута или HTTP 500 — документация
# прямо требует идемпотентности. Повтор не должен зачислить второй раз.
repeat = _topup.send_callback(tx_id, amount, API)
check("повторный колбэк принят", repeat.get("success") is True, str(repeat))

bal, _ = balance_of(client)
check("повтор колбэка НЕ зачислил деньги второй раз", bal == client_start + TOPUP,
      f"ожидалось {money(client_start + TOPUP)}, получено {money(bal)}")

# Сумма из колбэка сверяется с транзакцией: иначе на заявку 5 000 000
# можно было бы записать любую сумму.
wrong = _topup.send_callback(tx_id, amount * 3, API)
check("колбэк с чужой суммой отклонён", wrong.get("success") is False, str(wrong))

bal, _ = balance_of(client)
check("чужая сумма баланс не тронула", bal == client_start + TOPUP,
      f"получено {money(bal)}")

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
print(f"\n  внесено через Rahmat:           {money(TOPUP):>12}")
print(f"  прирост балансов + комиссия:    {money(system_delta):>12}")
check("деньги не создаются и не исчезают", abs(system_delta - TOPUP) < 0.01,
      f"расхождение {money(system_delta - TOPUP)}")

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
