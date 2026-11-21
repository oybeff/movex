"""
Тарифный заказ «как такси» и оплата наличными (12.11.2026).

Проверяется:
- котировка: цена часа × часы (+ навесное), меньше минимума — подтягивается
  на экране и отклоняется при создании; чужое навесное — 400;
- создание: сумму считает СЕРВЕР, budget из тела игнорируется; совпадает
  с котировкой; оплата с баланса замораживает сумму;
- наличные: у клиента НИЧЕГО не замораживается; наличные без тарифа — 400;
- владелец видит в карточке payment_method=cash;
- взять наличный заказ без денег на комиссию — 402; с деньгами — комиссия
  замораживается у владельца, заказ без эскроу (frozen_amount=0);
- завершение наличного: комиссия списана с владельца, запись в budget,
  баланс клиента не тронут;
- ОТМЕНА наличного: только снятие заморозки владельца. Раньше ветка
  «frozen_amount == 0» считалась «старым заказом» и перевела бы полную
  сумму с владельца клиенту — это проверяется отдельно;
- заказ с баланса по тарифу завершается как обычный (эскроу);
- залог за наличные (21.11.2026, cash_deposit_amount): замораживается у
  клиента при создании, не хватает — 400; переживает принятие заказа и
  возвращается при завершении, отмене заказа и отмене заявки; 0 — без залога.
  Остальные разделы идут с залогом 0, как было до него.
"""
import os
import sys
import time
from datetime import date, timedelta
from decimal import Decimal

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import otp_code  # noqa: E402

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND)

from sqlalchemy import text  # noqa: E402

from app.db.session import SessionLocal  # noqa: E402
from app.services import pricing_service  # noqa: E402

API = os.environ.get("API", "http://127.0.0.1:8000")
ok_count = fail_count = 0
created_ids, created_phones = [], []
TYPE = "grader"   # свой тип, чтобы не мешать другим наборам
OTHER = "roller"


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


def sql(q, **p):
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


def register(role):
    phone = f"9989{int(time.time() * 1000) % 100000000:08d}"[:12]
    requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": otp_code(phone)})
    r = requests.post(f"{API}/auth/register",
                      json={"full_name": f"Sinov Tarif {role}", "phone": phone, "role": role})
    body = r.json()
    created_ids.append(body["user_id"])
    created_phones.append(phone)
    time.sleep(0.01)
    sql("UPDATE users SET search_latitude=NULL, search_longitude=NULL WHERE id=:u", u=body["user_id"])
    return body["user_id"], {"Authorization": f"Bearer {body['access_token']}"}


def money(uid):
    row = sql("SELECT balance, frozen_balance FROM balances WHERE user_id=:u", u=uid)
    return (Decimal(str(row[0][0])), Decimal(str(row[0][1]))) if row else (Decimal(0), Decimal(0))


def set_money(uid, balance, frozen=0):
    if sql("SELECT 1 FROM balances WHERE user_id=:u", u=uid):
        sql("UPDATE balances SET balance=:b, frozen_balance=:f, bonus_balance=0 WHERE user_id=:u",
            b=balance, f=frozen, u=uid)
    else:
        sql("INSERT INTO balances (user_id, balance, frozen_balance, bonus_balance) "
            "VALUES (:u, :b, :f, 0)", b=balance, f=frozen, u=uid)


def add_equipment(hdr, etype=TYPE):
    r = requests.post(f"{API}/equipment/", headers=hdr, json={
        "type": etype, "model": "Sinov tarif", "price_per_day": "500000",
        "latitude": "41.30", "longitude": "69.25", "status": "available", "available": True,
    })
    return r.json()["id"]


def order_req(hdr, tier="econom", hours=4, payment="balance", **extra):
    start = date.today() + timedelta(days=1)
    body = {
        "equipment_type": TYPE, "start_date": str(start), "end_date": str(start),
        "delivery_latitude": 41.31, "delivery_longitude": 69.24,
        "delivery_address": "Sergeli qurilish maydoni",
        "origin_latitude": 41.29, "origin_longitude": 69.21, "origin_address": "Chilonzor 9-kv",
        "mode": "quick", "start_time": "08:00:00",
        "tariff": tier, "hours": hours, "payment_method": payment,
        # Подложенная сумма: сервер обязан её проигнорировать
        "budget": 1000,
    }
    body.update(extra)
    return requests.post(f"{API}/requests/", headers=hdr, json=body)


def commission_for(price):
    db = SessionLocal()
    try:
        return pricing_service.calculate_commission(db, Decimal(price), Decimal(price))
    finally:
        db.close()


def main():
    sql("DELETE FROM tariffs WHERE equipment_type IN (:a, :b)", a=TYPE, b=OTHER)
    sql("DELETE FROM equipment_attachments WHERE equipment_type IN (:a, :b)", a=TYPE, b=OTHER)
    sql("INSERT INTO tariffs (equipment_type, tier, price_per_hour, min_hours) VALUES "
        "(:t,'econom',400000,4),(:t,'fast',460000,4),(:t,'day',320000,4)", t=TYPE)
    att = sql("INSERT INTO equipment_attachments (equipment_type, name_uz, name_ru, price_per_hour) "
              "VALUES (:t,'Gidromolot','Гидромолот',150000) RETURNING id", t=TYPE)[0][0]
    other_att = sql("INSERT INTO equipment_attachments (equipment_type, name_uz, name_ru, price_per_hour) "
                    "VALUES (:t,'Ripper','Риппер',80000) RETURNING id", t=OTHER)[0][0]

    client_id, client = register("client")
    owner_id, owner = register("owner")
    add_equipment(owner)

    head("1. Котировка")
    r = requests.get(f"{API}/requests/tariffs", headers=client, params={"equipment_type": TYPE})
    q = r.json()
    check("три тарифа в порядке econom, fast, day",
          [x["tier"] for x in q] == ["econom", "fast", "day"], q)
    check("без часов — минимум (4 ч), econom = 1 600 000",
          Decimal(str(q[0]["total"])) == Decimal("1600000") and q[0]["hours"] == 4, q[0])
    q = requests.get(f"{API}/requests/tariffs", headers=client,
                     params={"equipment_type": TYPE, "hours": 2}).json()
    check("меньше минимума на экране — подтянуто к 4", q[0]["hours"] == 4, q[0])
    q = requests.get(f"{API}/requests/tariffs", headers=client,
                     params={"equipment_type": TYPE, "hours": 6, "attachment_id": att}).json()
    check("6 ч + гидромолот: (400 000 + 150 000) × 6 = 3 300 000",
          Decimal(str(q[0]["total"])) == Decimal("3300000"), q[0])
    r = requests.get(f"{API}/requests/tariffs", headers=client,
                     params={"equipment_type": TYPE, "attachment_id": other_att})
    check("навесное другого типа — 400", r.status_code == 400, r.text)
    types = requests.get(f"{API}/requests/tariffs/types", headers=client).json()
    check("тип с тарифами есть в /tariffs/types", TYPE in types, types)
    names = requests.get(f"{API}/requests/attachments", headers=client,
                         params={"equipment_type": TYPE}).json()
    check("навесное отдаётся с названием", names and names[0]["name"] == "Gidromolot", names)

    head("2. Создание с баланса: сумму считает сервер")
    set_money(client_id, 0)
    r = order_req(client)
    check("не хватает денег — 400", r.status_code == 400, r.text)
    set_money(client_id, 5000000)
    r = order_req(client, hours=2)
    check("меньше минимума при создании — 400", r.status_code == 400, r.text)
    r = order_req(client, hours=6, attachment_id=att)
    body = r.json()
    check("создан", r.status_code == 200, r.text)
    check("budget = 3 300 000, подложенные 1000 проигнорированы",
          Decimal(str(body.get("budget"))) == Decimal("3300000"), body)
    check("заморожено ровно 3 300 000", money(client_id)[1] == Decimal("3300000"), money(client_id))
    check("поля тарифа сохранены",
          body.get("tariff") == "econom" and body.get("hours") == 6
          and Decimal(str(body.get("attachment_price"))) == Decimal("150000")
          and body.get("origin_address") == "Chilonzor 9-kv", body)
    balance_rid = body["id"]

    head("3. Наличные")
    set_money(client_id, 0)
    r = order_req(client, tier="fast", payment="cash")
    cash = r.json()
    check("наличный заказ создан при нулевом балансе", r.status_code == 200, r.text)
    check("у клиента ничего не заморожено", money(client_id) == (Decimal(0), Decimal(0)), money(client_id))
    r = requests.post(f"{API}/requests/", headers=client, json={
        "equipment_type": TYPE, "start_date": str(date.today() + timedelta(days=1)),
        "end_date": str(date.today() + timedelta(days=1)),
        "delivery_latitude": 41.31, "delivery_longitude": 69.24,
        "mode": "quick", "budget": 500000, "start_time": "08:00:00", "payment_method": "cash",
    })
    check("наличные без тарифа — 400", r.status_code == 400, r.text)

    cards = requests.get(f"{API}/requests/quick/incoming", headers=owner).json()
    card = next((c for c in cards if c["id"] == cash["id"]), None)
    check("владелец видит наличный заказ с пометкой cash",
          card is not None and card["payment_method"] == "cash", card)

    price = Decimal("1840000")   # fast 460 000 × 4
    commission = commission_for(price)
    set_money(owner_id, 0)
    r = requests.post(f"{API}/requests/{cash['id']}/quick-accept", headers=owner)
    check("без денег на комиссию взять нельзя — 402",
          commission == 0 or r.status_code == 402, f"{r.status_code} {r.text}")
    set_money(owner_id, 100000)
    r = requests.post(f"{API}/requests/{cash['id']}/quick-accept", headers=owner)
    check("с деньгами на комиссию — взял", r.status_code == 200, r.text)
    order_id = r.json()["order_id"]
    row = sql("SELECT payment_method, frozen_amount, owner_frozen, total_amount, tariff, hours "
              "FROM orders WHERE id=:o", o=order_id)[0]
    check("заказ cash, эскроу 0, у владельца заморожена комиссия",
          row[0] == "cash" and Decimal(str(row[1])) == 0 and Decimal(str(row[2])) == commission,
          row)
    check("сумма заказа 1 840 000, тариф fast, 4 ч",
          Decimal(str(row[3])) == price and row[4] == "fast" and row[5] == 4, row)
    check("у владельца заморожено = комиссия", money(owner_id) == (Decimal("100000"), commission),
          money(owner_id))

    r = requests.put(f"{API}/orders/{order_id}", headers=client, json={"status": "completed"})
    check("клиент завершил наличный заказ", r.status_code == 200, r.text)
    check("с владельца списана комиссия, заморозки нет",
          money(owner_id) == (Decimal("100000") - commission, Decimal(0)), money(owner_id))
    check("баланс клиента не тронут", money(client_id) == (Decimal(0), Decimal(0)), money(client_id))
    reserve = sql("SELECT amount FROM budget_reserves WHERE order_id=:o", o=order_id)
    check("комиссия записана в budget",
          commission == 0 or (reserve and Decimal(str(reserve[0][0])) == commission), reserve)
    tx = sql("SELECT amount, type FROM balance_transactions WHERE order_id=:o AND user_id=:u",
             o=order_id, u=owner_id)
    check("у владельца транзакция-списание на комиссию",
          commission == 0 or (tx and Decimal(str(tx[0][0])) == commission and tx[0][1] == "payment"), tx)

    head("4. Отмена наличного: деньги владельца НЕ уходят клиенту")
    r = order_req(client, tier="day", payment="cash")
    cash2 = r.json()
    set_money(owner_id, 2000000)
    r = requests.post(f"{API}/requests/{cash2['id']}/quick-accept", headers=owner)
    order2 = r.json()["order_id"]
    r = requests.put(f"{API}/orders/{order2}", headers=client, json={"status": "cancelled"})
    check("клиент отменил", r.status_code == 200, r.text)
    check("баланс владельца цел, заморозка снята",
          money(owner_id) == (Decimal("2000000"), Decimal(0)), money(owner_id))
    check("клиенту ничего не пришло", money(client_id) == (Decimal(0), Decimal(0)), money(client_id))

    head("5. Тарифный заказ с баланса — эскроу как раньше")
    set_money(owner_id, 0)
    r = requests.post(f"{API}/requests/{balance_rid}/quick-accept", headers=owner)
    check("взял заказ с баланса без денег у себя (комиссию не замораживаем)",
          r.status_code == 200, r.text)
    order3 = r.json().get("order_id")
    set_money(client_id, 5000000, 3300000)
    r = requests.put(f"{API}/orders/{order3}", headers=client, json={"status": "completed"})
    c3 = commission_for(Decimal("3300000"))
    check("завершён", r.status_code == 200, r.text)
    check("клиент заплатил 3 300 000", money(client_id) == (Decimal("1700000"), Decimal(0)),
          money(client_id))
    check("владелец получил сумму минус комиссия",
          money(owner_id)[0] == Decimal("3300000") - c3, money(owner_id))


def flow_section():
    head("6. Ход заказа: Ketdik → Boshlash → Yakunlash, продление, исполнитель")
    client_id, client = register("client")
    owner_id, owner = register("owner")
    other_id, other = register("owner")
    eq = add_equipment(owner)
    sql("UPDATE equipment SET plate_number='01 A 777 BA' WHERE id=:e", e=eq)
    set_money(client_id, 5000000)
    set_money(owner_id, 100000)
    r = order_req(client, hours=4)   # econom 400 000 × 4 = 1 600 000, с баланса
    rid = r.json()["id"]
    oid = requests.post(f"{API}/requests/{rid}/quick-accept", headers=owner).json()["order_id"]

    ex = requests.get(f"{API}/orders/{oid}/executor", headers=client).json()
    check("исполнитель: госномер и модель", ex.get("plate_number") == "01 A 777 BA"
          and ex.get("equipment_model") == "Sinov tarif", ex)
    check("исполнитель: есть ETA в минутах", isinstance(ex.get("eta_minutes"), int), ex)
    r = requests.get(f"{API}/orders/{oid}/executor", headers=other)
    check("чужой не видит исполнителя — 403", r.status_code == 403, r.status_code)

    r = requests.post(f"{API}/orders/{oid}/finish", headers=owner)
    check("закончить до начала нельзя — 409", r.status_code == 409, r.text)
    r = requests.post(f"{API}/orders/{oid}/depart", headers=client)
    check("клиент не может нажать «Ketdik» — 403", r.status_code == 403, r.text)
    r = requests.post(f"{API}/orders/{oid}/depart", headers=owner)
    check("владелец: Ketdik", r.status_code == 200 and r.json().get("departed_at"), r.text)
    r = requests.post(f"{API}/orders/{oid}/start", headers=owner)
    check("владелец: Boshlash", r.status_code == 200 and r.json().get("started_at"), r.text)

    r = requests.post(f"{API}/orders/{oid}/extend", headers=owner, json={"hours": 2})
    check("продлевает только клиент — 403", r.status_code == 403, r.text)
    r = requests.post(f"{API}/orders/{oid}/delay", headers=client, json={"minutes": 15})
    check("об опоздании сообщает только владелец — 403", r.status_code == 403, r.text)
    r = requests.post(f"{API}/orders/{oid}/delay", headers=owner,
                      json={"minutes": 15, "reason": "tirbandlik"})
    check("опоздание после начала работы — 409", r.status_code == 409, r.text)

    r = requests.post(f"{API}/orders/{oid}/extend", headers=client, json={"hours": 2})
    body = r.json()
    check("запрос продления: деньги и часы не тронуты",
          r.status_code == 200 and body.get("hours") == 4 and body.get("extend_requested_hours") == 2
          and money(client_id)[1] == Decimal("1600000"), r.text)
    r = requests.post(f"{API}/orders/{oid}/extend/approve", headers=client)
    check("согласовать продление клиент не может — 403", r.status_code == 403, r.text)
    r = requests.post(f"{API}/orders/{oid}/extend/approve", headers=owner)
    body = r.json()
    check("владелец согласился — +2 ч", r.status_code == 200 and body.get("hours") == 6
          and body.get("extend_requested_hours") is None, r.text)
    check("сумма 1 600 000 → 2 400 000 (цена часа заказа)",
          Decimal(str(body.get("total_amount"))) == Decimal("2400000"), body)
    check("доплата заморожена у клиента", money(client_id)[1] == Decimal("2400000"), money(client_id))
    set_money(client_id, 2400000, 2400000)
    requests.post(f"{API}/orders/{oid}/extend", headers=client, json={"hours": 1})
    r = requests.post(f"{API}/orders/{oid}/extend/approve", headers=owner)
    check("не хватает денег на продление — 400, заказ не изменился",
          r.status_code == 400 and requests.get(f"{API}/orders/{oid}", headers=client).json()["hours"] == 6,
          r.text)

    r = requests.post(f"{API}/orders/{oid}/finish", headers=owner)
    check("владелец: Yakunlash", r.status_code == 200 and r.json().get("finished_at"), r.text)
    check("после Yakunlash деньги ещё не ушли", money(client_id) == (Decimal("2400000"), Decimal("2400000")),
          money(client_id))
    r = requests.post(f"{API}/orders/{oid}/extend", headers=client, json={"hours": 1})
    check("после окончания продлить нельзя — 409", r.status_code == 409, r.text)
    r = requests.put(f"{API}/orders/{oid}", headers=client, json={"status": "completed"})
    c = commission_for(Decimal("2400000"))
    check("клиент подтвердил — списано 2 400 000", r.status_code == 200
          and money(client_id) == (Decimal(0), Decimal(0)), money(client_id))
    check("владелец получил 2 400 000 минус комиссия",
          money(owner_id)[0] == Decimal("100000") + Decimal("2400000") - c, money(owner_id))

    head("7. Продление наличного заказа")
    set_money(owner_id, 100000)
    r = order_req(client, hours=4, payment="cash")
    oid2 = requests.post(f"{API}/requests/{r.json()['id']}/quick-accept", headers=owner).json()["order_id"]
    frozen_before = money(owner_id)[1]
    requests.post(f"{API}/orders/{oid2}/extend", headers=client, json={"hours": 2})
    r = requests.post(f"{API}/orders/{oid2}/extend/approve", headers=owner)
    body = r.json()
    check("наличный продлён, у клиента ничего не заморожено",
          r.status_code == 200 and money(client_id) == (Decimal(0), Decimal(0)), r.text)
    expected_delta = commission_for(Decimal("2400000")) - commission_for(Decimal("1600000"))
    check("у владельца заморожена разница комиссии (0 при фиксированной)",
          money(owner_id)[1] - frozen_before == expected_delta, (money(owner_id), expected_delta))
    requests.put(f"{API}/orders/{oid2}", headers=client, json={"status": "cancelled"})
    check("отмена: заморозка владельца снята", money(owner_id) == (Decimal("100000"), Decimal(0)),
          money(owner_id))
    check("отменил клиент — cancelled_by=client",
          requests.get(f"{API}/orders/{oid2}", headers=client).json().get("cancelled_by") == "client")

    head("8. Отмена владельцем, опоздание, жалоба, автоподтверждение")
    set_money(owner_id, 100000)
    def cash_order():
        rq = order_req(client, hours=4, payment="cash")
        return requests.post(f"{API}/requests/{rq.json()['id']}/quick-accept",
                             headers=owner).json()["order_id"]
    oid3 = cash_order()
    r = requests.post(f"{API}/orders/{oid3}/delay", headers=owner,
                      json={"minutes": 15, "reason": "tirbandlik"})
    check("владелец сообщил об опоздании на 15 мин", r.status_code == 200
          and r.json().get("delay_minutes") == 15 and r.json().get("delay_reason") == "tirbandlik", r.text)
    requests.put(f"{API}/orders/{oid3}", headers=owner, json={"status": "cancelled"})
    check("отменил владелец — cancelled_by=owner (клиенту B1)",
          requests.get(f"{API}/orders/{oid3}", headers=client).json().get("cancelled_by") == "owner")

    oid4 = cash_order()
    requests.post(f"{API}/orders/{oid4}/start", headers=owner)
    requests.post(f"{API}/orders/{oid4}/finish", headers=owner)
    r = requests.post(f"{API}/orders/{oid4}/problem", headers=client,
                      json={"reason": "wrong_equipment", "photos": ["https://evil/x.png"]})
    check("чужой адрес фото в жалобе — 400", r.status_code == 400, r.text)
    r = requests.post(f"{API}/orders/{oid4}/problem", headers=owner, json={"reason": "other"})
    check("жалуется только клиент — 403", r.status_code == 403, r.text)
    up = requests.post(f"{API}/orders/problem-photo", headers=client,
                       files={"file": ("a.png", b"\x89PNG fake", "image/png")})
    check("фото жалобы загружено", up.status_code == 200 and up.json()["url"].startswith("/static/problems/"),
          up.text)
    r = requests.post(f"{API}/orders/{oid4}/problem", headers=client,
                      json={"reason": "wrong_equipment", "comment": "boshqa ekskavator",
                            "photos": [up.json()["url"]]})
    check("жалоба принята", r.status_code == 200, r.text)
    sql("UPDATE orders SET finished_at = now() - interval '11 minutes' WHERE id = :i", i=oid4)
    check("с жалобой не подтверждается сам",
          requests.get(f"{API}/orders/{oid4}", headers=client).json()["status"] == "confirmed")

    oid5 = cash_order()
    requests.post(f"{API}/orders/{oid5}/start", headers=owner)
    requests.post(f"{API}/orders/{oid5}/finish", headers=owner)
    check("сразу после Yakunlash ещё confirmed",
          requests.get(f"{API}/orders/{oid5}", headers=client).json()["status"] == "confirmed")
    sql("UPDATE orders SET finished_at = now() - interval '11 minutes' WHERE id = :i", i=oid5)
    check("через 10 минут подтвердился сам",
          requests.get(f"{API}/orders/{oid5}", headers=client).json()["status"] == "completed")

    head("10. Зона обслуживания (E3) и надбавка (E4)")
    r = order_req(client, hours=4, payment="cash", delivery_latitude=39.65, delivery_longitude=66.97)
    check("Самарканд вне зоны — 400", r.status_code == 400, r.text)
    r = order_req(client, hours=4, payment="cash", surge_percent=10)
    check("+10%: 1 600 000 → 1 760 000", r.status_code == 200
          and Decimal(str(r.json().get("budget"))) == Decimal("1760000"), r.text)
    requests.post(f"{API}/requests/{r.json()['id']}/cancel", headers=client)
    r = order_req(client, hours=4, payment="cash", surge_percent=90)
    check("надбавка больше 30% — 422", r.status_code == 422, r.status_code)
    st = requests.get(f"{API}/settings/app-status").json()
    check("app-status без входа: версия, техработы, зона",
          "min_version" in st and "maintenance" in st and st["service_area"]["min_lat"] < 41.31, st)

    head("9. Buyurtmalarim (client-cards)")
    order_req(client, hours=4, payment="cash")
    r = requests.get(f"{API}/orders/client-cards", headers=client)
    cards = r.json() if r.status_code == 200 else []
    by_id = {c["order_id"]: c for c in cards if c["kind"] == "order"}
    check("список отвечает", r.status_code == 200, r.text[:300])
    check("ищущая заявка — stage=searching", any(c["stage"] == "searching" for c in cards), cards[:1])
    check("завершённый — completed", by_id.get(oid5, {}).get("stage") == "completed", by_id.get(oid5))
    check("отменённый владельцем — cancelled", by_id.get(oid3, {}).get("stage") == "cancelled")
    check("ждёт подтверждения (жалоба) — awaiting_confirm",
          by_id.get(oid4, {}).get("stage") == "awaiting_confirm", by_id.get(oid4))
    check("в карточке госномер и адрес", by_id.get(oid5, {}).get("plate_number") == "01 A 777 BA"
          and by_id.get(oid5, {}).get("to_address"), by_id.get(oid5))
    other_cards = requests.get(f"{API}/orders/client-cards", headers=owner).json()
    check("владелец не видит чужих карточек клиента",
          not any(c.get("order_id") == oid5 for c in other_cards))

    head("11. Разбор жалобы из админки")
    from app.core.config import settings as _st
    secret = {"X-Admin-Secret": _st.ADMIN_INTERNAL_SECRET}
    pid = sql("SELECT id FROM order_problems WHERE order_id = :o", o=oid4)[0][0]
    r = requests.post(f"{API}/orders/internal/problems/{pid}/resolve", json={"action": "cancel"})
    check("без секрета — отказ", r.status_code in (401, 403, 404), r.status_code)
    r = requests.post(f"{API}/orders/internal/problems/{pid}/resolve", headers=secret, json={"action": "refund"})
    check("неизвестное действие — 422", r.status_code == 422, r.status_code)
    frozen_before = money(owner_id)[1]
    r = requests.post(f"{API}/orders/internal/problems/{pid}/resolve", headers=secret, json={"action": "cancel"})
    check("отмена по жалобе: заказ cancelled", r.status_code == 200 and r.json()["order_status"] == "cancelled", r.text)
    od = requests.get(f"{API}/orders/{oid4}", headers=client).json()
    check("кто отменил — admin", od.get("cancelled_by") == "admin", od.get("cancelled_by"))
    check("заморозка комиссии у владельца снята", money(owner_id)[1] < frozen_before, (frozen_before, money(owner_id)))
    r = requests.post(f"{API}/orders/internal/problems/{pid}/resolve", headers=secret, json={"action": "close"})
    check("повторный разбор — 409", r.status_code == 409, r.status_code)

    oid6 = cash_order()
    requests.post(f"{API}/orders/{oid6}/start", headers=owner)
    requests.post(f"{API}/orders/{oid6}/finish", headers=owner)
    requests.post(f"{API}/orders/{oid6}/problem", headers=client, json={"reason": "poor_quality"})
    pid6 = sql("SELECT id FROM order_problems WHERE order_id = :o", o=oid6)[0][0]
    bal_before = money(owner_id)[0]
    r = requests.post(f"{API}/orders/internal/problems/{pid6}/resolve", headers=secret, json={"action": "complete"})
    check("принято по жалобе: заказ completed", r.status_code == 200 and r.json()["order_status"] == "completed", r.text)
    check("с владельца списана комиссия наличного заказа", money(owner_id)[0] < bal_before, (bal_before, money(owner_id)))


DEPOSIT_KEY = "cash_deposit_amount"
_saved_deposit = []


def set_deposit(value):
    if value is None:
        sql("DELETE FROM app_settings WHERE key=:k", k=DEPOSIT_KEY)
    elif sql("SELECT 1 FROM app_settings WHERE key=:k", k=DEPOSIT_KEY):
        sql("UPDATE app_settings SET value=to_jsonb(CAST(:v AS text)) WHERE key=:k", k=DEPOSIT_KEY, v=str(value))
    else:
        sql("INSERT INTO app_settings (key, value) VALUES (:k, to_jsonb(CAST(:v AS text)))",
            k=DEPOSIT_KEY, v=str(value))


def deposit_section():
    head("Залог за наличные")
    set_deposit(None)
    client_id, client = register("client")
    owner_id, owner = register("owner")
    add_equipment(owner)
    r = requests.get(f"{API}/requests/cash-deposit", headers=client)
    check("по умолчанию залог 50 000", r.status_code == 200 and r.json()["amount"] == 50000, r.text)
    set_deposit(70000)
    r = requests.get(f"{API}/requests/cash-deposit", headers=client)
    check("сумма из настройки: 70 000", r.json()["amount"] == 70000, r.text)

    set_money(client_id, 60000)
    r = order_req(client, payment="cash")
    check("на балансе меньше залога — 400", r.status_code == 400, r.text)
    check("в тексте сумма без «.0»", "60 000" in r.text and ".0" not in r.text, r.text)

    set_money(client_id, 100000)
    r = order_req(client, payment="cash")
    check("наличный заказ создан", r.status_code == 200, r.text)
    rid = r.json()["id"]
    check("у клиента заморожен залог 70 000", money(client_id) == (Decimal("100000"), Decimal("70000")),
          money(client_id))
    r = requests.post(f"{API}/requests/{rid}/cancel", headers=client, json={})
    check("отмена заявки до принятия", r.status_code == 200, r.text)
    check("залог вернулся после отмены заявки", money(client_id) == (Decimal("100000"), Decimal(0)),
          money(client_id))

    r = order_req(client, payment="cash")
    rid = r.json()["id"]
    set_money(owner_id, 1000000)
    r = requests.post(f"{API}/requests/{rid}/quick-accept", headers=owner)
    check("владелец взял", r.status_code == 200, r.text)
    oid = r.json()["order_id"]
    check("после принятия залог всё ещё заморожен", money(client_id)[1] == Decimal("70000"), money(client_id))
    row = sql("SELECT frozen_amount FROM orders WHERE id=:o", o=oid)[0]
    check("у заказа эскроу 0 (CHECK наличных)", Decimal(str(row[0])) == 0, row)
    r = requests.put(f"{API}/orders/{oid}", headers=client, json={"status": "completed"})
    check("заказ завершён", r.status_code == 200, r.text)
    check("залог вернулся, баланс клиента цел", money(client_id) == (Decimal("100000"), Decimal(0)),
          money(client_id))
    r = requests.put(f"{API}/orders/{oid}", headers=client, json={"status": "completed"})
    check("повторное завершение не трогает деньги", money(client_id) == (Decimal("100000"), Decimal(0)),
          money(client_id))

    r = order_req(client, payment="cash")
    rid = r.json()["id"]
    r = requests.post(f"{API}/requests/{rid}/quick-accept", headers=owner)
    oid = r.json()["order_id"]
    r = requests.put(f"{API}/orders/{oid}", headers=owner, json={"status": "cancelled"})
    check("владелец отменил заказ", r.status_code == 200, r.text)
    check("залог вернулся после отмены заказа", money(client_id) == (Decimal("100000"), Decimal(0)),
          money(client_id))

    set_deposit(0)
    set_money(client_id, 0)
    r = order_req(client, payment="cash")
    check("залог 0 — наличный заказ при пустом балансе", r.status_code == 200, r.text)
    check("и ничего не заморожено", money(client_id) == (Decimal(0), Decimal(0)), money(client_id))


def driver_section():
    head("Водитель: причина отказа и «Yetib keldim»")
    set_deposit(0)
    client_id, client = register("client")
    owner_id, owner = register("owner")
    add_equipment(owner)
    set_money(owner_id, 1000000)
    rid = order_req(client, payment="cash").json()["id"]
    r = requests.post(f"{API}/requests/{rid}/quick-decline", headers=owner, json={"reason": "low_price"})
    check("отказ с причиной принят", r.status_code == 200, r.text)
    row = sql("SELECT reason FROM quick_request_declines WHERE request_id=:r AND owner_id=:o", r=rid, o=owner_id)
    check("причина сохранена", row and row[0][0] == "low_price", row)
    rid2 = order_req(client, payment="cash").json()["id"]
    r = requests.post(f"{API}/requests/{rid2}/quick-decline", headers=owner, json={"reason": "взлом"})
    row = sql("SELECT reason FROM quick_request_declines WHERE request_id=:r", r=rid2)
    check("неизвестная причина не сохраняется, отказ проходит", r.status_code == 200 and row[0][0] is None, row)
    r = requests.post(f"{API}/requests/{rid2}/quick-decline", headers=owner)
    check("отказ без тела по-прежнему работает", r.status_code == 200, r.text)

    rid3 = order_req(client, payment="cash").json()["id"]
    oid = requests.post(f"{API}/requests/{rid3}/quick-accept", headers=owner).json()["order_id"]
    r = requests.post(f"{API}/orders/{oid}/arrive", headers=client)
    check("«Yetib keldim» клиенту нельзя", r.status_code in (403, 404), r.text)
    r = requests.post(f"{API}/orders/{oid}/arrive", headers=owner)
    body = r.json()
    check("«Yetib keldim»: arrived_at и departed_at заполнены",
          r.status_code == 200 and body.get("arrived_at") and body.get("departed_at"), body)


def cleanup():
    db = SessionLocal()
    try:
        db.execute(text("DELETE FROM orders WHERE user_id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM otp_verifications WHERE phone = ANY(:ps)"), {"ps": created_phones})
        db.execute(text("DELETE FROM tariffs WHERE equipment_type IN (:a, :b)"), {"a": TYPE, "b": OTHER})
        db.execute(text("DELETE FROM equipment_attachments WHERE equipment_type IN (:a, :b)"),
                   {"a": TYPE, "b": OTHER})
        db.commit()
    finally:
        db.close()


if __name__ == "__main__":
    row = sql("SELECT value #>> '{}' FROM app_settings WHERE key=:k", k=DEPOSIT_KEY)
    _saved_deposit.append(row[0][0] if row else None)
    try:
        set_deposit(0)   # прежние разделы писались до залога
        main()
        flow_section()
        deposit_section()
        driver_section()
    finally:
        set_deposit(_saved_deposit[0])
        cleanup()
    print(f"\nITOG: {ok_count} o'tdi, {fail_count} yiqildi")
    sys.exit(1 if fail_count else 0)
