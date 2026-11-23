"""
«Yuk tashish» — перевозка груза клиента из А в Б (24.11.2026).

Что сторожит:
  - цена считается сервером по режиму машины из админки: km (подача +
    км × цена) и hour (часы × цена часа, не меньше минимума);
  - подсказка машины по тоннам — самая малая, что увезёт;
  - у машин с выбором кузова без tentli/tentsiz заказ не создать; груз
    тяжелее машины — 400; машина без цены — 400;
  - заказ видят водители с той же машиной и тем же кузовом, в радиусе от А;
  - гонка двух водителей: один 200, второй 409;
  - деньги Go wallet: заморожено при создании, при «Yakunlash» клиента —
    списано, водителю минус комиссия; наличные: комиссия водителя
    заморожена при принятии (нет денег — 402) и списана при завершении;
  - отмена клиентом до погрузки снимает обе заморозки; после погрузки —
    нельзя; отказ водителя до погрузки — заказ снова в поиске.

    API=http://127.0.0.1:8010 venv/Scripts/python tests/verify_freight.py
"""
import os
import sys
import threading
import time
from decimal import Decimal

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _auth import otp_code  # noqa: E402

API = os.environ.get("API", "http://127.0.0.1:8000")
ok_count = fail_count = 0
created_ids, created_phones = [], []


def check(label, cond, detail=""):
    global ok_count, fail_count
    if cond:
        ok_count += 1
        print(f"  [OK]   {label}")
    else:
        fail_count += 1
        print(f"  [FAIL] {label}  {detail}")


def head(t):
    print(f"\n=== {t} ===")


def sql(q, **p):
    from sqlalchemy import text

    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        r = db.execute(text(q), p)
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
    body = requests.post(f"{API}/auth/register", json={"full_name": name, "phone": phone, "role": role}).json()
    created_ids.append(body["user_id"])
    created_phones.append(phone)
    time.sleep(0.01)
    return body["user_id"], {"Authorization": f"Bearer {body['access_token']}"}


def money(uid):
    row = sql("SELECT balance, frozen_balance FROM balances WHERE user_id=:u", u=uid)
    return (Decimal(str(row[0][0])), Decimal(str(row[0][1]))) if row else (Decimal(0), Decimal(0))


def set_money(uid, b):
    if sql("SELECT 1 FROM balances WHERE user_id=:u", u=uid):
        sql("UPDATE balances SET balance=:b, frozen_balance=0, bonus_balance=0 WHERE user_id=:u", b=b, u=uid)
    else:
        sql("INSERT INTO balances (user_id, balance, frozen_balance, bonus_balance) VALUES (:u,:b,0,0)", u=uid, b=b)


D = lambda x: Decimal(str(x))  # noqa: E731
A = {"from_latitude": 41.30, "from_longitude": 69.24, "to_latitude": 41.35, "to_longitude": 69.30,
     "from_address": "Chorsu", "to_address": "Yunusobod"}

saved = sql("SELECT code, base_fee, price_per_km, price_mode, price_per_hour, min_hours, has_body_choice "
            "FROM delivery_vehicles WHERE code IN ('gazel','kamaz')")
saved_comm = sql("SELECT key, value FROM app_settings WHERE key IN ('commission_mode','commission_fixed')")
sql("UPDATE app_settings SET value = to_jsonb('fixed'::text) WHERE key='commission_mode'")
sql("UPDATE app_settings SET value = to_jsonb('5000'::text) WHERE key='commission_fixed'")
sql("UPDATE delivery_vehicles SET base_fee=30000, price_per_km=4000, price_mode='km', has_body_choice=true WHERE code='gazel'")
sql("UPDATE delivery_vehicles SET price_mode='hour', price_per_hour=200000, min_hours=2, has_body_choice=false WHERE code='kamaz'")

try:
    client_id, client = register("client", "Sinov yuk mijoz")
    d1_id, d1 = register("owner", "Sinov yuk A")
    d2_id, d2 = register("owner", "Sinov yuk B")
    d3_id, d3 = register("owner", "Sinov tentsiz")
    for h, body in ((d1, "tent"), (d2, "tent"), (d3, "open")):
        r = requests.put(f"{API}/drivers/delivery/profile", headers=h,
                         json={"vehicle_code": "gazel", "body_type": body, "categories": []})
        assert r.status_code == 200, r.text
        requests.post(f"{API}/drivers/delivery/heartbeat", headers=h,
                      json={"online": True, "latitude": 41.29, "longitude": 69.23})

    head("1. ЦЕНА И ПОДСКАЗКА")
    q = requests.get(f"{API}/freight/quote", headers=client, params={
        "from_lat": 41.30, "from_lon": 69.24, "to_lat": 41.35, "to_lon": 69.30, "tonnes": 1.8}).json()
    km = D(q["distance_km"])
    g = next(v for v in q["vehicles"] if v["code"] == "gazel")
    k = next(v for v in q["vehicles"] if v["code"] == "kamaz")
    check("1,8 т — подсказан Gazel (2 т)", q["suggested"] == "gazel", str(q["suggested"]))
    check("Gazel по км: подача + км × цена", abs(D(g["price"]) - (30000 + km * 4000)) <= 1, f"{g['price']} km={km}")
    check("KamAZ по часам: минимум 2 ч × 200 000", D(k["price"]) == 400000 and k["hours"] == 2, str(k))
    q3 = requests.get(f"{API}/freight/quote", headers=client, params={
        "from_lat": 41.30, "from_lon": 69.24, "to_lat": 41.35, "to_lon": 69.30, "hours": 3}).json()
    check("3 часа — 600 000", D(next(v for v in q3["vehicles"] if v["code"] == "kamaz")["price"]) == 600000)
    check("у Gazel есть выбор кузова", g["has_body_choice"] is True)

    head("2. ПРОВЕРКИ ПРИ СОЗДАНИИ")
    set_money(client_id, 1_000_000)
    r = requests.post(f"{API}/freight/orders", headers=client, json={**A, "vehicle_code": "gazel"})
    check("без кузова у Gazel — 400", r.status_code == 400, f"{r.status_code}")
    r = requests.post(f"{API}/freight/orders", headers=client,
                      json={**A, "vehicle_code": "gazel", "body_type": "tent", "cargo_tonnes": 5})
    check("5 т в Gazel — 400", r.status_code == 400, f"{r.status_code}")
    r = requests.post(f"{API}/freight/orders", headers=client,
                      json={**A, "vehicle_code": "gazel", "body_type": "tent", "cargo_tonnes": 1.5,
                            "price": 1, "cargo_note": "Mebel"})
    check("заказ создан", r.status_code == 200, f"{r.status_code} {r.text[:200]}")
    o = r.json()
    oid = o["id"]
    check("цена из сервера, а не из тела", abs(D(o["price"]) - (30000 + km * 4000)) <= 1, str(o["price"]))
    b, f = money(client_id)
    check("цена заморожена на Go wallet", f == D(o["price"]), f"{f}")

    head("3. ВХОДЯЩИЕ И ГОНКА")
    inc3 = requests.get(f"{API}/drivers/freight/incoming", headers=d3).json()
    check("водитель с тентсиз не видит заказ «tentli»", not any(x["id"] == oid for x in inc3))
    inc1 = requests.get(f"{API}/drivers/freight/incoming", headers=d1).json()
    card = next((x for x in inc1 if x["id"] == oid), None)
    check("водитель с тентли видит", card is not None)
    if card:
        check("в карточке А, Б и «вам поступит»", card["from_address"] == "Chorsu" and card["to_address"] == "Yunusobod"
              and D(card["you_receive"]) == D(card["driver_fee"]) - 5000, str(card)[:200])
    res = {}

    def grab(n, h):
        res[n] = requests.post(f"{API}/drivers/freight/orders/{oid}/accept", headers=h).status_code

    t1 = threading.Thread(target=grab, args=("d1", d1))
    t2 = threading.Thread(target=grab, args=("d2", d2))
    t1.start(); t2.start(); t1.join(); t2.join()
    check("один принял, второй 409", sorted(res.values()) == [200, 409], str(res))
    w_id, w = (d1_id, d1) if res.get("d1") == 200 else (d2_id, d2)

    r = requests.post(f"{API}/drivers/freight/orders/{oid}/cancel", headers=w)
    check("отказ до погрузки — снова поиск", r.status_code == 200 and r.json()["status"] == "searching", r.text[:120])
    r = requests.post(f"{API}/drivers/freight/orders/{oid}/accept", headers=d1)
    check("d1 принял", r.status_code == 200, r.text[:150])
    orders = requests.get(f"{API}/freight/orders", headers=client).json()
    mine = next(x for x in orders if x["id"] == oid)
    check("клиент видит водителя и телефон", mine["driver_id"] == d1_id and mine.get("driver_phone"))

    head("4. ШАГИ И ДЕНЬГИ (Go wallet)")
    r = requests.post(f"{API}/freight/orders/{oid}/finish", headers=client)
    check("завершить до погрузки нельзя", r.status_code == 400, f"{r.status_code}")
    r = requests.post(f"{API}/drivers/freight/orders/{oid}/arrived", headers=d1)
    check("«yetib keldim» до погрузки — 400", r.status_code == 400)
    check("«Yuk ortildi»", requests.post(f"{API}/drivers/freight/orders/{oid}/loaded", headers=d1).json()["status"] == "loaded")
    r = requests.post(f"{API}/freight/orders/{oid}/cancel", headers=client)
    check("после погрузки клиент не отменит", r.status_code == 400, f"{r.status_code}")
    check("«Yetib keldim»", requests.post(f"{API}/drivers/freight/orders/{oid}/arrived", headers=d1).json()["status"] == "arrived")
    b0, _ = money(client_id)
    w0, _ = money(d1_id)
    r = requests.post(f"{API}/freight/orders/{oid}/finish", headers=client)
    check("клиент завершил", r.status_code == 200 and r.json()["status"] == "done", r.text[:150])
    b1, f1 = money(client_id)
    w1, _ = money(d1_id)
    price = D(o["price"])
    check("с клиента списана цена", b0 - b1 == price, f"{b0 - b1} vs {price}")
    check("заморозки нет", f1 == 0, str(f1))
    check("водителю цена − 5 000", w1 - w0 == price - 5000, f"{w1 - w0}")

    head("5. НАЛИЧНЫЕ")
    set_money(d1_id, 0)
    set_money(d2_id, 50_000)
    r = requests.post(f"{API}/freight/orders", headers=client,
                      json={**A, "vehicle_code": "gazel", "body_type": "tent", "payment_method": "cash"})
    oid2 = r.json()["id"]
    b, f = money(client_id)
    check("наличные — на Go wallet ничего не заморожено", f == 0, str(f))
    r = requests.post(f"{API}/drivers/freight/orders/{oid2}/accept", headers=d1)
    check("без денег на комиссию — 402", r.status_code == 402, f"{r.status_code}")
    r = requests.post(f"{API}/drivers/freight/orders/{oid2}/accept", headers=d2)
    check("с деньгами — принял", r.status_code == 200, r.text[:150])
    _, wf = money(d2_id)
    check("комиссия заморожена у водителя", wf == 5000, str(wf))
    r = requests.post(f"{API}/freight/orders/{oid2}/cancel", headers=client)
    check("клиент отменил до погрузки", r.status_code == 200 and r.json()["status"] == "cancelled")
    _, wf = money(d2_id)
    check("заморозка водителя снята", wf == 0, str(wf))

    r = requests.post(f"{API}/freight/orders", headers=client,
                      json={**A, "vehicle_code": "gazel", "body_type": "tent", "payment_method": "cash"})
    oid3 = r.json()["id"]
    requests.post(f"{API}/drivers/freight/orders/{oid3}/accept", headers=d2)
    requests.post(f"{API}/drivers/freight/orders/{oid3}/loaded", headers=d2)
    b0, _ = money(client_id)
    w0, _ = money(d2_id)
    r = requests.post(f"{API}/freight/orders/{oid3}/finish", headers=client)
    check("завершено (наличные)", r.status_code == 200, r.text[:120])
    b1, _ = money(client_id)
    w1, wf1 = money(d2_id)
    check("с клиента ничего не списано", b1 == b0, f"{b0} -> {b1}")
    check("с водителя — комиссия", w0 - w1 == 5000 and wf1 == 0, f"{w0 - w1} frozen={wf1}")
finally:
    for c, base, km, mode, ph, mh, bc in (saved or []):
        sql("UPDATE delivery_vehicles SET base_fee=:b, price_per_km=:k, price_mode=:m, price_per_hour=:ph, "
            "min_hours=:mh, has_body_choice=:bc WHERE code=:c", b=base, k=km, m=mode, ph=ph, mh=mh, bc=bc, c=c)
    for key, v in (saved_comm or []):
        sql("UPDATE app_settings SET value = CAST(:v AS jsonb) WHERE key=:k", v=__import__("json").dumps(v), k=key)
    if created_ids:
        sql("DELETE FROM freight_orders WHERE client_id = ANY(:i) OR driver_id = ANY(:i)", i=created_ids)
        sql("DELETE FROM users WHERE id = ANY(:i)", i=created_ids)
        sql("DELETE FROM otp_verifications WHERE phone = ANY(:p)", p=created_phones)

print(f"\nИтого: {ok_count} OK, {fail_count} FAIL")
sys.exit(1 if fail_count else 0)
