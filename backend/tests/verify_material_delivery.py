"""
Доставка стройматериалов водителем «как такси» (23.11.2026).

Что сторожит:
  - профиль водителя: машина из списка админки, категории с минимумом;
  - заказ видят водители ТОЛЬКО после подтверждения продавцом, с той же
    машиной, нужной категорией, минимумом не больше количества, в радиусе;
  - кто первый принял — тот и везёт, второму 409 (гонка двух водителей);
  - своя цена водителя ниже админской — водитель получает её, а не больше;
  - ДЕНЬГИ, Go wallet: с клиента списаны товар + цена водителя, продавцу
    товар минус комиссия, водителю доставка минус комиссия, заморозки нет;
  - ДЕНЬГИ, наличные: на Go wallet заморожен только товар, комиссия
    водителя заморожена на ЕГО балансе при принятии (нет денег — 402) и
    списана при завершении;
  - отказ водителя до погрузки возвращает заказ в поиск и снимает его
    заморозку; после «Tovarni oldim» клиент отменить не может;
  - отмена клиентом снимает заморозку и у клиента, и у водителя.

Пользователи создаются тестом и удаляются в конце.

    API=http://127.0.0.1:8010 venv/Scripts/python tests/verify_material_delivery.py
"""
import os
import sys
import threading
import time
from decimal import Decimal

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _auth import otp_code, token  # noqa: E402

API = os.environ.get("API", "http://127.0.0.1:8000")
ADMIN_PHONE = "998900000000"

ok_count = 0
fail_count = 0
created_ids, created_phones = [], []


def check(label, condition, detail=""):
    global ok_count, fail_count
    if condition:
        ok_count += 1
        print(f"  [OK]   {label}")
    else:
        fail_count += 1
        print(f"  [FAIL] {label}  {detail}")


def head(t):
    print(f"\n=== {t} ===")


def sql(query, **params):
    from sqlalchemy import text

    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        r = db.execute(text(query), params)
        db.commit()
        try:
            return r.fetchall()
        except Exception:
            return None
    finally:
        db.close()


def register(role, name):
    phone = f"9989{int(time.time() * 1000) % 100000000:08d}"[:12]
    requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": otp_code(phone)})
    r = requests.post(f"{API}/auth/register", json={"full_name": name, "phone": phone, "role": role})
    body = r.json()
    created_ids.append(body["user_id"])
    created_phones.append(phone)
    time.sleep(0.01)
    return body["user_id"], {"Authorization": f"Bearer {body['access_token']}"}


def money(uid):
    row = sql("SELECT balance, frozen_balance FROM balances WHERE user_id=:u", u=uid)
    return (Decimal(str(row[0][0])), Decimal(str(row[0][1]))) if row else (Decimal(0), Decimal(0))


def set_money(uid, balance, frozen=0):
    if sql("SELECT 1 FROM balances WHERE user_id=:u", u=uid):
        sql("UPDATE balances SET balance=:b, frozen_balance=:f, bonus_balance=0 WHERE user_id=:u",
            b=balance, f=frozen, u=uid)
    else:
        sql("INSERT INTO balances (user_id, balance, frozen_balance, bonus_balance) VALUES (:u, :b, :f, 0)",
            b=balance, f=frozen, u=uid)


def D(x):
    return Decimal(str(x))


admin = token(ADMIN_PHONE, API)
saved_commission = sql("SELECT key, value FROM app_settings WHERE key IN "
                       "('commission_mode','commission_fixed','commission_percent')")
sql("UPDATE app_settings SET value = to_jsonb('fixed'::text) WHERE key = 'commission_mode'")
sql("UPDATE app_settings SET value = to_jsonb('5000'::text) WHERE key = 'commission_fixed'")
gazel = sql("SELECT base_fee, price_per_km FROM delivery_vehicles WHERE code='gazel'")[0]
sql("UPDATE delivery_vehicles SET base_fee = 20000, price_per_km = 3000 WHERE code = 'gazel'")

try:
    head("1. ПРОФИЛЬ ВОДИТЕЛЯ")
    seller_id, seller = register("owner", "Sinov sotuvchi")
    buyer_id, buyer = register("client", "Sinov xaridor")
    d1_id, d1 = register("owner", "Sinov haydovchi A")
    d2_id, d2 = register("owner", "Sinov haydovchi B")
    d3_id, d3 = register("owner", "Sinov Labo")
    d4_id, d4 = register("owner", "Sinov katta minimum")

    cats = requests.get(f"{API}/drivers/delivery/categories", headers=d1).json()
    check("10 категорий из ТЗ", len(cats) == 10 and {c["code"] for c in cats} >= {"foam_block", "sand"},
          str([c["code"] for c in cats]))
    r = requests.get(f"{API}/drivers/delivery/profile", headers=d1).json()
    check("без профиля — не зарегистрирован", r["registered"] is False)

    r = requests.put(f"{API}/drivers/delivery/profile", headers=d1, json={
        "vehicle_code": "gazel", "plate": "01a123bc",
        "categories": [{"code": "fired_brick", "min_quantity": 300}, {"code": "sand", "min_quantity": 1}]})
    check("профиль сохранён", r.status_code == 200 and r.json()["vehicle"]["code"] == "gazel",
          f"{r.status_code} {r.text[:150]}")
    check("номер приведён к верхнему регистру", r.json().get("plate") == "01A123BC")
    r = requests.put(f"{API}/drivers/delivery/profile", headers=d2, json={
        "vehicle_code": "gazel", "price_per_km": 1000, "base_fee": 10000,
        "categories": [{"code": "fired_brick", "min_quantity": 100}]})
    check("второй водитель (своя цена ниже)", r.status_code == 200, r.text[:150])
    requests.put(f"{API}/drivers/delivery/profile", headers=d3, json={
        "vehicle_code": "labo", "categories": [{"code": "fired_brick", "min_quantity": 50}]})
    requests.put(f"{API}/drivers/delivery/profile", headers=d4, json={
        "vehicle_code": "gazel", "categories": [{"code": "fired_brick", "min_quantity": 5000}]})

    r = requests.put(f"{API}/drivers/delivery/profile", headers=d1, json={
        "vehicle_code": "tank", "categories": [{"code": "sand", "min_quantity": 1}]})
    check("несуществующая машина — 400", r.status_code == 400, f"{r.status_code}")
    r = requests.put(f"{API}/drivers/delivery/profile", headers=d1, json={
        "vehicle_code": "gazel", "categories": []})
    check("без категорий — 400", r.status_code == 400, f"{r.status_code}")
    r = requests.put(f"{API}/drivers/delivery/profile", headers=buyer, json={
        "vehicle_code": "gazel", "categories": [{"code": "sand", "min_quantity": 1}]})
    check("клиент водителем не становится — 403", r.status_code == 403, f"{r.status_code}")
    # вернуть профиль d1 (последний валидный PUT уже сохранён — проверим)
    check("профиль d1 не испорчен неудачными попытками",
          requests.get(f"{API}/drivers/delivery/profile", headers=d1).json()["vehicle_code"] == "gazel")

    for h, lat in ((d1, 41.30), (d2, 41.31), (d3, 41.30), (d4, 41.30)):
        requests.post(f"{API}/drivers/delivery/heartbeat", headers=h,
                      json={"online": True, "latitude": lat, "longitude": 69.24})

    head("2. ЗАКАЗ ВИДЕН ПРАВИЛЬНЫМ ВОДИТЕЛЯМ")
    r = requests.post(f"{API}/materials/products", headers=seller, json={
        "material_type": "brick", "title": "G'isht (test dostavki)", "price_per_unit": 1000,
        "min_quantity": 100, "available_quantity": 100000, "address": "Sergeli ombori",
        "latitude": 41.30, "longitude": 69.25})
    pid = r.json()["id"]
    requests.post(f"{API}/materials/products/{pid}/moderate", headers=admin, json={"approve": True})

    set_money(buyer_id, 2_000_000)
    set_money(d1_id, 100_000)
    set_money(d2_id, 0)
    set_money(seller_id, 0)

    r = requests.post(f"{API}/materials/orders", headers=buyer, json={"product_id": pid, "quantity": 500})
    check("без точки доставки — 400", r.status_code == 400, f"{r.status_code}")

    r = requests.post(f"{API}/materials/orders", headers=buyer, json={
        "product_id": pid, "quantity": 500, "delivery_address": "Chilonzor",
        "delivery_latitude": 41.35, "delivery_longitude": 69.30})
    check("заказ создан (Go wallet)", r.status_code == 200, f"{r.status_code} {r.text[:200]}")
    o = r.json()
    oid = o["id"]
    check("машину выбрал сервер — Gazel (1 750 кг)", o["vehicle_code"] == "gazel", o["vehicle_code"])
    check("доставка по цене админки", D(o["delivery_fee"]) > 0, str(o["delivery_fee"]))
    check("комиссия продавца — только с товара (5 000)", D(o["commission"]) == 5000, str(o["commission"]))
    check("ждёт продавца", o["delivery_status"] == "waiting_seller", str(o["delivery_status"]))
    b, f = money(buyer_id)
    check("заморожены товар + доставка", f == D(o["goods_amount"]) + D(o["delivery_fee"]), f"{f}")

    inc = requests.get(f"{API}/drivers/delivery/incoming", headers=d1).json()
    check("до подтверждения продавцом водители заказ НЕ видят", not any(x["id"] == oid for x in inc))

    requests.post(f"{API}/materials/orders/{oid}/confirm", headers=seller)
    inc1 = requests.get(f"{API}/drivers/delivery/incoming", headers=d1).json()
    card = next((x for x in inc1 if x["id"] == oid), None)
    check("после подтверждения — Gazel видит", card is not None, str([x["id"] for x in inc1]))
    if card:
        check("в карточке склад и адрес клиента", card["pickup_address"] == "Sergeli ombori"
              and card["delivery_address"] == "Chilonzor", str(card)[:200])
        check("«вам поступит» = доставка − комиссия",
              D(card["you_receive"]) == D(card["driver_fee"]) - D(card["commission"]), str(card)[:200])
    inc3 = requests.get(f"{API}/drivers/delivery/incoming", headers=d3).json()
    check("Labo (другая машина) не видит", not any(x["id"] == oid for x in inc3))
    inc4 = requests.get(f"{API}/drivers/delivery/incoming", headers=d4).json()
    check("водитель с минимумом 5 000 не видит заказ на 500", not any(x["id"] == oid for x in inc4))
    check("продавец не видит свой заказ как водитель",
          requests.get(f"{API}/drivers/delivery/incoming", headers=seller).json() == [])

    requests.post(f"{API}/drivers/delivery/heartbeat", headers=d2,
                  json={"online": True, "latitude": 40.10, "longitude": 65.30})  # Navoiy
    inc2 = requests.get(f"{API}/drivers/delivery/incoming", headers=d2).json()
    check("водитель за 30 км от склада не видит", not any(x["id"] == oid for x in inc2))
    requests.post(f"{API}/drivers/delivery/heartbeat", headers=d2,
                  json={"online": True, "latitude": 41.31, "longitude": 69.24})
    requests.post(f"{API}/drivers/delivery/heartbeat", headers=d1, json={"online": False})
    check("офлайн — входящих нет", requests.get(f"{API}/drivers/delivery/incoming", headers=d1).json() == [])
    requests.post(f"{API}/drivers/delivery/heartbeat", headers=d1,
                  json={"online": True, "latitude": 41.30, "longitude": 69.24})

    head("3. ГОНКА: КТО ПЕРВЫЙ ПРИНЯЛ")
    results = {}

    def grab(name, h):
        results[name] = requests.post(f"{API}/drivers/delivery/orders/{oid}/accept", headers=h).status_code

    t1 = threading.Thread(target=grab, args=("d1", d1))
    t2 = threading.Thread(target=grab, args=("d2", d2))
    t1.start(); t2.start(); t1.join(); t2.join()
    codes = sorted(results.values())
    check("один принял, второй получил 409", codes == [200, 409], str(results))
    winner = "d1" if results.get("d1") == 200 else "d2"
    w_id, w_h = (d1_id, d1) if winner == "d1" else (d2_id, d2)
    l_h = d2 if winner == "d1" else d1

    o = requests.get(f"{API}/materials/orders", headers=buyer).json()
    o = next(x for x in o if x["id"] == oid)
    check("клиент видит водителя и его телефон", o["driver_id"] == w_id and o["driver_phone"], str(o)[:200])
    if winner == "d2":
        check("своя цена водителя ниже — получает свою", D(o["driver_fee"]) < D(o["delivery_fee"]),
              f"{o['driver_fee']} vs {o['delivery_fee']}")
    else:
        check("без своей цены — цена админки", D(o["driver_fee"]) == D(o["delivery_fee"]), str(o["driver_fee"]))
    r = requests.post(f"{API}/drivers/delivery/orders/{oid}/picked-up", headers=l_h)
    check("чужой водитель шаги не нажимает — 403", r.status_code == 403, f"{r.status_code}")

    head("4. ОТКАЗ ВОДИТЕЛЯ ДО ПОГРУЗКИ")
    r = requests.post(f"{API}/drivers/delivery/orders/{oid}/cancel", headers=w_h)
    check("отказ принят, заказ снова в поиске",
          r.status_code == 200 and r.json()["delivery_status"] == "searching" and r.json()["driver_id"] is None,
          f"{r.status_code} {r.text[:150]}")
    r = requests.post(f"{API}/drivers/delivery/orders/{oid}/accept", headers=d1)
    check("d1 принял заново", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
    o = r.json()
    fee = D(o["driver_fee"])
    dcom = D(o["driver_commission"])

    head("5. ПУТЬ И ДЕНЬГИ (Go wallet)")
    r = requests.post(f"{API}/drivers/delivery/orders/{oid}/arrived", headers=d1)
    check("«Yetib keldim» раньше «Tovarni oldim» — 400", r.status_code == 400, f"{r.status_code}")
    r = requests.post(f"{API}/materials/orders/{oid}/deliver", headers=buyer)
    check("клиент не может закрыть, пока товар не забран", r.status_code == 400, f"{r.status_code}")
    r = requests.post(f"{API}/drivers/delivery/orders/{oid}/picked-up", headers=d1)
    check("«Tovarni oldim»", r.status_code == 200 and r.json()["delivery_status"] == "picked_up", r.text[:150])
    r = requests.post(f"{API}/materials/orders/{oid}/cancel", headers=buyer)
    check("после погрузки клиент отменить не может", r.status_code == 400, f"{r.status_code}")
    r = requests.post(f"{API}/drivers/delivery/orders/{oid}/cancel", headers=d1)
    check("и водитель отказаться не может", r.status_code == 400, f"{r.status_code}")
    r = requests.post(f"{API}/drivers/delivery/orders/{oid}/arrived", headers=d1)
    check("«Yetib keldim»", r.status_code == 200 and r.json()["delivery_status"] == "arrived", r.text[:150])

    b0, f0 = money(buyer_id)
    s0, _ = money(seller_id)
    w0, wf0 = money(d1_id)
    goods = D(o["goods_amount"])
    r = requests.post(f"{API}/materials/orders/{oid}/deliver", headers=buyer)
    check("клиент нажал «Yetkazildi»", r.status_code == 200 and r.json()["delivery_status"] == "done",
          f"{r.status_code} {r.text[:150]}")
    b1, f1 = money(buyer_id)
    s1, _ = money(seller_id)
    w1, _ = money(d1_id)
    check("с клиента списаны товар + цена водителя", b0 - b1 == goods + fee, f"{b0 - b1} vs {goods + fee}")
    check("заморозка клиента снята целиком", f1 == 0, str(f1))
    check("продавцу товар минус 5 000", s1 - s0 == goods - 5000, str(s1 - s0))
    check("водителю доставка минус комиссия", w1 - w0 == fee - dcom, f"{w1 - w0} vs {fee - dcom}")

    head("6. НАЛИЧНЫЕ ЗА ДОСТАВКУ")
    set_money(buyer_id, 600_000)
    r = requests.post(f"{API}/materials/orders", headers=buyer, json={
        "product_id": pid, "quantity": 500, "delivery_payment": "cash",
        "delivery_latitude": 41.35, "delivery_longitude": 69.30})
    check("заказ с наличной доставкой", r.status_code == 200 and r.json()["delivery_payment"] == "cash",
          f"{r.status_code} {r.text[:150]}")
    o2 = r.json()
    oid2 = o2["id"]
    b, f = money(buyer_id)
    check("на Go wallet заморожен только товар", f == D(o2["goods_amount"]), str(f))
    requests.post(f"{API}/materials/orders/{oid2}/confirm", headers=seller)

    set_money(d2_id, 0)
    r = requests.post(f"{API}/drivers/delivery/orders/{oid2}/accept", headers=d2)
    check("водитель без денег на комиссию — 402", r.status_code == 402, f"{r.status_code} {r.text[:120]}")
    set_money(d1_id, 50_000)
    r = requests.post(f"{API}/drivers/delivery/orders/{oid2}/accept", headers=d1)
    check("водитель с балансом принял", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
    o2 = r.json()
    dcom2 = D(o2["driver_commission"])
    w, wf = money(d1_id)
    check("комиссия заморожена на балансе водителя", wf == dcom2, f"{wf} vs {dcom2}")

    r = requests.post(f"{API}/materials/orders/{oid2}/cancel", headers=buyer)
    check("клиент отменил до погрузки", r.status_code == 200, f"{r.status_code}")
    w, wf = money(d1_id)
    b, f = money(buyer_id)
    check("заморозка водителя снята", wf == 0, str(wf))
    check("заморозка клиента снята", f == 0, str(f))

    r = requests.post(f"{API}/materials/orders", headers=buyer, json={
        "product_id": pid, "quantity": 500, "delivery_payment": "cash",
        "delivery_latitude": 41.35, "delivery_longitude": 69.30})
    oid3 = r.json()["id"]
    requests.post(f"{API}/materials/orders/{oid3}/confirm", headers=seller)
    o3 = requests.post(f"{API}/drivers/delivery/orders/{oid3}/accept", headers=d1).json()
    requests.post(f"{API}/drivers/delivery/orders/{oid3}/picked-up", headers=d1)
    b0, f0 = money(buyer_id)
    w0, wf0 = money(d1_id)
    r = requests.post(f"{API}/materials/orders/{oid3}/deliver", headers=buyer)
    check("доставлено (наличные)", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
    b1, f1 = money(buyer_id)
    w1, wf1 = money(d1_id)
    check("с клиента списан ТОЛЬКО товар", b0 - b1 == D(o3["goods_amount"]), f"{b0 - b1}")
    check("с водителя списана комиссия", w0 - w1 == D(o3["driver_commission"]), f"{w0 - w1}")
    check("заморозка водителя снята", wf1 == 0, str(wf1))

    head("7. ЗАКАЗЫ ВОДИТЕЛЯ")
    mine = requests.get(f"{API}/drivers/delivery/orders", headers=d1).json()
    check("водитель видит свои доставки", {oid, oid3} <= {x["id"] for x in mine}, str([x["id"] for x in mine]))
    check("и телефоны клиента и продавца", all(x.get("buyer_phone") and x.get("seller_phone") for x in mine
                                                if x["id"] in (oid, oid3)))
finally:
    sql("UPDATE delivery_vehicles SET base_fee=:b, price_per_km=:k WHERE code='gazel'", b=gazel[0], k=gazel[1])
    for k, v in (saved_commission or []):
        sql("UPDATE app_settings SET value = CAST(:v AS jsonb) WHERE key = :k",
            v=__import__("json").dumps(v), k=k)
    if created_ids:
        sql("DELETE FROM material_orders WHERE buyer_id = ANY(:ids) OR seller_id = ANY(:ids)", ids=created_ids)
        sql("DELETE FROM material_products WHERE owner_id = ANY(:ids)", ids=created_ids)
        sql("DELETE FROM users WHERE id = ANY(:ids)", ids=created_ids)
        sql("DELETE FROM otp_verifications WHERE phone = ANY(:ps)", ps=created_phones)

print(f"\nИтого: {ok_count} OK, {fail_count} FAIL")
sys.exit(1 if fail_count else 0)
