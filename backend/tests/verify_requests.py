"""
Zayavkalar: mijoz chaqiradi -> egalar taklif beradi -> mijoz tanlaydi.

Asosiy tekshiriladigan narsa PUL. Zayavka va taklif pulni qimirlatmasligi,
va tanlangandan keyin summa taklifdagi stavka bo'yicha, komissiya bilan
birga, serverda hisoblanishi kerak. Mijoz yuborgan raqamlarga ishonilmaydi.

Ikkinchisi — ko'rinish: begona zayavka va raqobatchining narxi ochilmasin.

Test IDEMPOTENT — bazani tozalamasdan qayta ishga tushirsa bo'ladi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_requests.py
"""
import hashlib
import re
from datetime import datetime, timedelta
from decimal import Decimal

import requests

API = "http://127.0.0.1:8000"

OWNER_PHONE = "998901110001"
CLIENT_PHONE = "998901110002"
# Boshqa mijoz — begona zayavka ko'rinmasligini tekshirish uchun
OTHER_CLIENT_PHONE = "998901179425"

CLICK_SERVICE_ID = "111111"
CLICK_SECRET_KEY = "local_dev_click_secret"

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


def token(phone):
    r = requests.post(f"{API}/auth/send-otp", json={"phone": phone})
    code = re.search(r"(\d{4})\s*$", r.json()["message"]).group(1)
    r = requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": code})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def topup_via_click(hdr, amount, click_id):
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


def free_dates(days=1):
    start = datetime.now() + timedelta(days=800 + datetime.now().microsecond % 4000)
    return start.strftime("%Y-%m-%d"), (start + timedelta(days=days)).strftime("%Y-%m-%d")


def balance(hdr):
    b = requests.get(f"{API}/balance/me", headers=hdr).json()
    return Decimal(str(b["balance"])), Decimal(str(b["frozen_balance"]))


client = token(CLIENT_PHONE)
owner = token(OWNER_PHONE)
other = token(OTHER_CLIENT_PHONE)

topup_via_click(client, 10_000_000, 960000 + int(datetime.now().timestamp()) % 10000)

# Egasining texnikasi — turini shundan olamiz, aks holda taklif bermaydi
my_equipment = requests.get(
    f"{API}/equipment/", headers=owner, params={"owner_only": True, "limit": 50}
).json()
assert my_equipment, "egasining texnikasi yo'q, testni bajarib bo'lmaydi"
EQ = my_equipment[0]
EQ_TYPE, EQ_ID = EQ["type"], EQ["id"]

head("1. ЗАЯВКА СОЗДАЁТСЯ И НЕ ТРОГАЕТ ДЕНЬГИ")

bal_before, frozen_before = balance(client)
start, end = free_dates(2)

r = requests.post(f"{API}/requests/", headers=client, json={
    "equipment_type": EQ_TYPE,
    "start_date": start, "end_date": end,
    "delivery_latitude": 41.31, "delivery_longitude": 69.28,
    "delivery_address": "Toshkent, sinov manzili",
    "budget": 2_000_000,
    "comment": "test",
})
check("заявка создана", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
request_id = r.json()["id"] if r.status_code == 200 else None
check("статус open", r.status_code == 200 and r.json()["status"] == "open")

bal_after, frozen_after = balance(client)
check("баланс не изменился", bal_after == bal_before, f"{bal_before} -> {bal_after}")
check("заморозка не изменилась", frozen_after == frozen_before,
      f"{frozen_before} -> {frozen_after}")

head("2. ЧУЖУЮ ЗАЯВКУ НЕ ВИДНО В СВОЁМ СПИСКЕ")

mine = requests.get(f"{API}/requests/", headers=client).json()
theirs = requests.get(f"{API}/requests/", headers=other).json()
check("своя заявка в своём списке", any(x["id"] == request_id for x in mine))
check("чужой клиент её не видит", not any(x["id"] == request_id for x in theirs),
      f"нашлась у {OTHER_CLIENT_PHONE}")

head("3. ВЛАДЕЛЕЦ ВИДИТ ЗАЯВКУ В ЛЕНТЕ")

feed = requests.get(f"{API}/requests/feed", headers=owner).json()
check("заявка в ленте владельца", any(x["id"] == request_id for x in feed),
      f"в ленте {len(feed)} заявок")

r = requests.get(f"{API}/requests/feed", headers=client)
check("клиенту лента владельца закрыта", r.status_code == 403, f"{r.status_code}")

head("4. ПРЕДЛОЖЕНИЕ ВЛАДЕЛЬЦА")

OFFER_PRICE = 700_000
r = requests.post(f"{API}/requests/{request_id}/offers", headers=owner,
                  json={"equipment_id": EQ_ID, "price_per_day": OFFER_PRICE,
                        "comment": "тестовое предложение"})
check("предложение отправлено", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
offer_id = r.json()["id"] if r.status_code == 200 else None

r2 = requests.post(f"{API}/requests/{request_id}/offers", headers=owner,
                   json={"equipment_id": EQ_ID, "price_per_day": 500_000})
check("повторное предложение той же машиной отклонено", r2.status_code == 400,
      f"{r2.status_code}")

r3 = requests.post(f"{API}/requests/{request_id}/offers", headers=client,
                   json={"equipment_id": EQ_ID, "price_per_day": 1})
check("клиент не может предлагать сам себе", r3.status_code == 403, f"{r3.status_code}")

bal_now, frozen_now = balance(client)
check("предложение тоже не трогает деньги",
      (bal_now, frozen_now) == (bal_before, frozen_before),
      f"{bal_before}/{frozen_before} -> {bal_now}/{frozen_now}")

head("5. ЧУЖОЙ КЛИЕНТ НЕ ЛЕЗЕТ В ЗАЯВКУ")

r = requests.get(f"{API}/requests/{request_id}", headers=other)
check("посторонний клиент получает 403", r.status_code == 403, f"{r.status_code}")

r = requests.post(f"{API}/requests/{request_id}/offers/{offer_id}/accept", headers=other)
check("посторонний не может принять предложение", r.status_code in (403, 404),
      f"{r.status_code}")

head("6. ЦЕНУ СЧИТАЕТ СЕРВЕР ПО СТАВКЕ ИЗ ПРЕДЛОЖЕНИЯ")

detail = requests.get(f"{API}/requests/{request_id}", headers=client).json()
check("клиент видит своё предложение", len(detail["offers"]) == 1,
      f"предложений: {len(detail['offers'])}")

days = (datetime.strptime(end, "%Y-%m-%d") - datetime.strptime(start, "%Y-%m-%d")).days + 1
expected_subtotal = Decimal(OFFER_PRICE) * days
got_subtotal = Decimal(str(detail["offers"][0]["estimated_subtotal"]))
check("предварительная сумма = ставка × дни",
      got_subtotal == expected_subtotal, f"{got_subtotal} != {expected_subtotal}")

r = requests.post(f"{API}/requests/{request_id}/offers/{offer_id}/accept", headers=client)
check("предложение принято", r.status_code == 200, f"{r.status_code} {r.text[:200]}")

order_id = r.json()["order_id"] if r.status_code == 200 else None
order = requests.get(f"{API}/orders/{order_id}", headers=client).json()

check("заказ создан на техникe из предложения", order["equipment_id"] == EQ_ID,
      f"{order.get('equipment_id')} != {EQ_ID}")

commission = Decimal(str(order["commission"]))
total = Decimal(str(order["total_amount"]))
delivery = Decimal(str(order.get("delivery_fee") or 0))

check("комиссия = 10% от аренды по СТАВКЕ ПРЕДЛОЖЕНИЯ",
      commission == (expected_subtotal / 10).quantize(Decimal("1")),
      f"комиссия {commission}, ожидали {(expected_subtotal / 10).quantize(Decimal('1'))}")
check("итог = аренда + комиссия + доставка",
      total == expected_subtotal + commission + delivery,
      f"{total} != {expected_subtotal} + {commission} + {delivery}")

head("7. ДЕНЬГИ ЗАМОРОЖЕНЫ РОВНО НА СУММУ ЗАКАЗА")

bal_final, frozen_final = balance(client)
check("баланс не уменьшился (только заморозка)", bal_final == bal_before,
      f"{bal_before} -> {bal_final}")
check("заморожено ровно на сумму заказа", frozen_final - frozen_before == total,
      f"прирост заморозки {frozen_final - frozen_before}, сумма заказа {total}")

head("8. ЗАЯВКА ЗАКРЫЛАСЬ И ВТОРОЙ РАЗ НЕ ПРИНИМАЕТСЯ")

after = requests.get(f"{API}/requests/{request_id}", headers=client).json()
check("статус заявки assigned", after["status"] == "assigned", after["status"])
check("заявка помнит свой заказ", after["order_id"] == order_id,
      f"{after.get('order_id')} != {order_id}")
check("предложение отмечено принятым", after["offers"][0]["status"] == "accepted",
      after["offers"][0]["status"])

r = requests.post(f"{API}/requests/{request_id}/offers/{offer_id}/accept", headers=client)
check("повторное принятие отклонено", r.status_code == 400, f"{r.status_code}")

r = requests.post(f"{API}/requests/{request_id}/offers", headers=owner,
                  json={"equipment_id": EQ_ID, "price_per_day": 100})
check("в закрытую заявку предложение не уходит", r.status_code == 400, f"{r.status_code}")

head("9. РАДИУС ПОИСКА")

r = requests.put(f"{API}/requests/area", headers=owner,
                 json={"latitude": 41.31, "longitude": 69.28, "radius_km": 50})
check("радиус сохраняется", r.status_code == 200 and r.json()["radius_km"] == 50,
      f"{r.status_code} {r.text[:120]}")

r = requests.get(f"{API}/requests/area", headers=owner).json()
check("радиус читается обратно", r["radius_km"] == 50, str(r))

r = requests.put(f"{API}/requests/area", headers=owner,
                 json={"latitude": 41.31, "longitude": 69.28, "radius_km": 0})
check("нулевой радиус отклонён", r.status_code == 422, f"{r.status_code}")

r = requests.put(f"{API}/requests/area", headers=owner,
                 json={"latitude": 200, "longitude": 69.28, "radius_km": 50})
check("некорректная широта отклонена", r.status_code == 422, f"{r.status_code}")

# Далёкая заявка: ставим владельцу узкий радиус вокруг Ташкента,
# а заявку создаём в Нукусе — примерно 750 км.
requests.put(f"{API}/requests/area", headers=owner,
             json={"latitude": 41.31, "longitude": 69.28, "radius_km": 50})

start2, end2 = free_dates(1)
far = requests.post(f"{API}/requests/", headers=client, json={
    "equipment_type": EQ_TYPE, "start_date": start2, "end_date": end2,
    "delivery_latitude": 42.46, "delivery_longitude": 59.61,
    "delivery_address": "Nukus",
}).json()

feed = requests.get(f"{API}/requests/feed", headers=owner).json()
check("заявка за пределами радиуса в ленту не попала",
      not any(x["id"] == far["id"] for x in feed),
      f"радиус 50 км, а Нукус ~750 км")

requests.put(f"{API}/requests/area", headers=owner,
             json={"latitude": 41.31, "longitude": 69.28, "radius_km": 1000})
feed = requests.get(f"{API}/requests/feed", headers=owner).json()
check("с радиусом 1000 км она появляется",
      any(x["id"] == far["id"] for x in feed))

head("10. ОТМЕНА ЗАЯВКИ")

r = requests.post(f"{API}/requests/{far['id']}/cancel", headers=other)
check("чужую заявку отменить нельзя", r.status_code == 403, f"{r.status_code}")

r = requests.post(f"{API}/requests/{far['id']}/cancel", headers=client)
check("свою заявку клиент отменяет", r.status_code == 200, f"{r.status_code}")
check("статус стал cancelled", r.json()["status"] == "cancelled", r.json()["status"])

r = requests.post(f"{API}/requests/{far['id']}/cancel", headers=client)
check("повторная отмена отклонена", r.status_code == 400, f"{r.status_code}")

head("11. ВАЛИДАЦИЯ")

r = requests.post(f"{API}/requests/", headers=client, json={
    "equipment_type": "letayushchaya_tarelka",
    "start_date": start, "end_date": end,
    "delivery_latitude": 41.31, "delivery_longitude": 69.28,
})
check("несуществующий тип техники отклонён", r.status_code == 400, f"{r.status_code}")

s, e = free_dates(1)
r = requests.post(f"{API}/requests/", headers=client, json={
    "equipment_type": EQ_TYPE, "start_date": e, "end_date": s,
    "delivery_latitude": 41.31, "delivery_longitude": 69.28,
})
check("конец раньше начала отклонён", r.status_code == 400, f"{r.status_code}")

r = requests.post(f"{API}/requests/", headers=client, json={
    "equipment_type": EQ_TYPE, "start_date": s, "end_date": e,
    "delivery_latitude": 41.31, "delivery_longitude": 69.28,
    "budget": -100,
})
check("отрицательный бюджет отклонён", r.status_code == 422, f"{r.status_code}")

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
