"""
Проверка починок денежного контура MoveX GO.
Прогоняет настоящий путь оплаты Click (prepare + complete с подписью)
и заново пробует все три эксплойта, которые раньше срабатывали.
"""
import hashlib
import re
from datetime import datetime

import requests

API = "http://127.0.0.1:8000"
SERVICE_ID = "111111"
SECRET_KEY = "local_dev_click_secret"

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


def click_sign(click_trans_id, merchant_trans_id, amount, action, sign_time):
    raw = f"{click_trans_id}{SERVICE_ID}{SECRET_KEY}{merchant_trans_id}{amount}{action}{sign_time}"
    return hashlib.md5(raw.encode()).hexdigest()


def click_callback(path, click_trans_id, merchant_trans_id, amount, action, extra=None):
    sign_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    payload = {
        "click_trans_id": click_trans_id,
        "service_id": SERVICE_ID,
        "merchant_trans_id": merchant_trans_id,
        "amount": amount,
        "action": action,
        "error": 0,
        "error_note": "Success",
        "sign_time": sign_time,
        "sign_string": click_sign(click_trans_id, merchant_trans_id, amount, action, sign_time),
    }
    if extra:
        payload.update(extra)
    return requests.post(f"{API}/balance/{path}", data=payload).json()


client = token("998901110002")
owner = token("998901110001")

head("1. ПОПОЛНЕНИЕ ТЕПЕРЬ ТРЕБУЕТ ПОДТВЕРЖДЁННОЙ ОПЛАТЫ")

r = requests.post(f"{API}/balance/topup", headers=client,
                  json={"amount": 5000000, "payment_method": "payme"})
check("способ без подтверждения оплаты отклонён", r.status_code == 400,
      f"вернулось {r.status_code}")
if r.status_code == 400:
    print(f"         сервер: {r.json()['detail']}")

r = requests.post(f"{API}/balance/topup", headers=client,
                  json={"amount": 5000000, "payment_method": "click"})
top = r.json()
check("заявка на пополнение через Click создана", r.status_code == 200, r.text[:150])
check("транзакция в статусе pending, деньги НЕ зачислены",
      top.get("status") == "pending", f"статус {top.get('status')}")
check("ссылка на оплату сгенерирована", bool(top.get("payment_url")))

bal, _ = balance_of(client)
check("баланс до оплаты остался нулевым", bal == 0, f"баланс {bal}")

head("2. КОЛБЭК CLICK ЗАЧИСЛЯЕТ ДЕНЬГИ")

tx_id = top["transaction_id"]
amount = float(top["amount"])

prep = click_callback("click/prepare", 900001, tx_id, amount, 0)
check("prepare принят", prep.get("error") == 0, str(prep))

comp = click_callback("click/complete", 900001, tx_id, amount, 1,
                      extra={"merchant_prepare_id": prep.get("merchant_prepare_id", tx_id)})
check("complete принят", comp.get("error") == 0, str(comp))

bal, _ = balance_of(client)
check("после подтверждения баланс пополнен", bal == 5000000, f"баланс {money(bal)}")

head("3. ЦЕНУ СЧИТАЕТ СЕРВЕР, А НЕ КЛИЕНТ")

eq = requests.get(f"{API}/equipment/1", headers=client).json()
day_price = float(eq["price_per_day"])
print(f"  техника: {eq['type']} {eq['model']}, {money(day_price)} сум/сутки")
print("  клиент отправляет заведомо заниженные цифры: total_amount=1000, commission=0")

order = requests.post(f"{API}/orders/", headers=client, json={
    "equipment_id": 1,
    "start_date": "2026-09-01", "end_date": "2026-09-02",
    "total_amount": 1000, "commission": 0,
    "delivery_latitude": "41.31", "delivery_longitude": "69.28",
}).json()

expected_subtotal = day_price * 2          # двое суток, включительно
expected_commission = round(expected_subtotal * 0.1)
print(f"  сервер посчитал: сумма {money(order['total_amount'])}, "
      f"комиссия {money(order['commission'])}, доставка {money(order.get('delivery_fee') or 0)}")

check("присланная клиентом сумма проигнорирована", float(order["total_amount"]) != 1000,
      f"total_amount={order['total_amount']}")
check("комиссия посчитана сервером", float(order["commission"]) == expected_commission,
      f"ожидалось {expected_commission}, получено {order['commission']}")
check("доставка посчитана по координатам", float(order.get("delivery_fee") or 0) > 0)
check("заморожена именно серверная сумма",
      float(order["frozen_amount"]) == float(order["total_amount"]))

head("4. ДЕНЬГИ СХОДЯТСЯ ПОСЛЕ ЗАВЕРШЕНИЯ СДЕЛКИ")

total = float(order["total_amount"])
commission = float(order["commission"])

requests.put(f"{API}/orders/{order['id']}", headers=owner, json={"status": "confirmed"})
r = requests.put(f"{API}/orders/{order['id']}", headers=owner, json={"status": "completed"})
check("заказ завершён", r.status_code == 200 and r.json().get("status") == "completed", r.text[:150])

cl_bal, cl_frozen = balance_of(client)
ow_bal, _ = balance_of(owner)

print(f"  клиент:   баланс {money(cl_bal):>12}, заморожено {money(cl_frozen):>10}")
print(f"  владелец: баланс {money(ow_bal):>12}")

check("с клиента списана полная сумма заказа", cl_bal == 5000000 - total,
      f"ожидалось {money(5000000 - total)}, получено {money(cl_bal)}")
check("заморозка снята", cl_frozen == 0)
check("владелец получил сумму за вычетом комиссии", ow_bal == total - commission,
      f"ожидалось {money(total - commission)}, получено {money(ow_bal)}")

внесено = 5000000
в_системе = cl_bal + ow_bal + commission
print(f"\n  внесено живыми деньгами:      {money(внесено):>12}")
print(f"  на балансах + резерв платформы:{money(в_системе):>12}")
check("баланс системы сходится — деньги не создаются из воздуха",
      abs(в_системе - внесено) < 0.01,
      f"расхождение {money(в_системе - внесено)}")

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
