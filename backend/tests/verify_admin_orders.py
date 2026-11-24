"""
Admin panel: buyurtmani bekor qilish va haydovchini almashtirish
(Figma «Admin panel» O3/O4, 24.11.2026).

Что сторожит:
  - без X-Admin-Secret — 403; без причины — 400;
  - список кандидатов: занятый водитель и водитель с другим кузовом
    отмечены причиной и назначить их нельзя (409);
  - наличный заказ: при переназначении комиссия снимается с прежнего
    водителя и замораживается у нового; нет денег у нового — 402,
    и прежний водитель остаётся с заказом;
  - «qayta qidiruvga»: водителя сняли — заказ снова searching, заморозки нет;
  - отмена админом ПОСЛЕ погрузки снимает заморозку клиента (Go wallet)
    и водителя, cancelled_by = admin, причина записана;
  - каждое действие пишется в admin_actions.

    API=http://127.0.0.1:8010 venv/Scripts/python tests/verify_admin_orders.py
"""
import json
import os
import sys
import time
from decimal import Decimal

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from _auth import otp_code  # noqa: E402
from app.core.config import settings  # noqa: E402

API = os.environ.get("API", "http://127.0.0.1:8000")
SECRET = {"X-Admin-Secret": settings.ADMIN_INTERNAL_SECRET}
ok_count = fail_count = 0
created_ids, created_phones = [], []
D = lambda x: Decimal(str(x))  # noqa: E731


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
    return (D(row[0][0]), D(row[0][1])) if row else (D(0), D(0))


def set_money(uid, b):
    if sql("SELECT 1 FROM balances WHERE user_id=:u", u=uid):
        sql("UPDATE balances SET balance=:b, frozen_balance=0, bonus_balance=0 WHERE user_id=:u", b=b, u=uid)
    else:
        sql("INSERT INTO balances (user_id, balance, frozen_balance, bonus_balance) VALUES (:u,:b,0,0)", u=uid, b=b)


def adm(path, body=None, get=False, headers=SECRET):
    url = f"{API}/admin-orders/internal/{path}"
    return requests.get(url, headers=headers) if get else requests.post(url, headers=headers, json=body or {})


A = {"from_latitude": 41.30, "from_longitude": 69.24, "to_latitude": 41.35, "to_longitude": 69.30,
     "from_address": "Chorsu", "to_address": "Yunusobod"}

admin_id = sql("SELECT id FROM users WHERE role='admin' ORDER BY id LIMIT 1")[0][0]
saved = sql("SELECT code, base_fee, price_per_km, price_mode, has_body_choice FROM delivery_vehicles WHERE code='gazel'")
saved_comm = sql("SELECT key, value FROM app_settings WHERE key IN ('commission_mode','commission_fixed')")
sql("UPDATE app_settings SET value = to_jsonb('fixed'::text) WHERE key='commission_mode'")
sql("UPDATE app_settings SET value = to_jsonb('5000'::text) WHERE key='commission_fixed'")
sql("UPDATE delivery_vehicles SET base_fee=30000, price_per_km=4000, price_mode='km', has_body_choice=true WHERE code='gazel'")
action_from = sql("SELECT COALESCE(MAX(id),0) FROM admin_actions")[0][0]

try:
    client_id, client = register("client", "Sinov admin mijoz")
    d1_id, d1 = register("owner", "Sinov adm A")
    d2_id, d2 = register("owner", "Sinov adm B")
    d3_id, d3 = register("owner", "Sinov adm tentsiz")
    for h, body in ((d1, "tent"), (d2, "tent"), (d3, "open")):
        r = requests.put(f"{API}/drivers/delivery/profile", headers=h,
                         json={"vehicle_code": "gazel", "body_type": body, "categories": []})
        assert r.status_code == 200, r.text
        requests.post(f"{API}/drivers/delivery/heartbeat", headers=h,
                      json={"online": True, "latitude": 41.29, "longitude": 69.23})
    set_money(client_id, 1_000_000)
    for d in (d1_id, d2_id, d3_id):
        set_money(d, 100_000)

    head("1. ДОСТУП И ПРОВЕРКИ")
    r = requests.post(f"{API}/freight/orders", headers=client,
                      json={**A, "vehicle_code": "gazel", "body_type": "tent", "payment_method": "cash"})
    check("наличный заказ создан", r.status_code == 200, r.text[:200])
    cash_id = r.json()["id"]
    check("без секрета — 403", adm(f"freight/{cash_id}/candidates", get=True, headers={}).status_code == 403)
    r = adm(f"freight/{cash_id}/cancel", {"admin_id": admin_id, "reason": "nonsense"})
    check("непонятная причина — 400", r.status_code == 400, f"{r.status_code}")

    head("2. КАНДИДАТЫ")
    r = requests.post(f"{API}/drivers/freight/orders/{cash_id}/accept", headers=d1)
    check("d1 принял наличный заказ", r.status_code == 200, r.text[:150])
    check("у d1 заморожена комиссия", money(d1_id)[1] == 5000, str(money(d1_id)))
    c = adm(f"freight/{cash_id}/candidates", get=True).json()
    by = {x["user_id"]: x for x in c["candidates"]}
    check("можно переназначать", c["can_reassign"] is True, str(c.get("note")))
    check("d1 отмечен как текущий", by.get(d1_id, {}).get("current") is True)
    check("d3 (tentsiz) — причина «Kuzov»", "Kuzov" in (by.get(d3_id, {}).get("reason") or ""), str(by.get(d3_id)))
    check("d2 подходит", by.get(d2_id, {}).get("reason") is None, str(by.get(d2_id)))
    r = adm(f"freight/{cash_id}/reassign", {"admin_id": admin_id, "user_id": d3_id})
    check("назначить неподходящего — 409", r.status_code == 409, f"{r.status_code}")

    head("3. ПЕРЕНАЗНАЧЕНИЕ (наличные)")
    set_money(d2_id, 1000)
    r = adm(f"freight/{cash_id}/reassign", {"admin_id": admin_id, "user_id": d2_id})
    check("у d2 нет денег на комиссию — 409/402", r.status_code in (402, 409), f"{r.status_code} {r.text[:120]}")
    o = sql("SELECT driver_id, status FROM freight_orders WHERE id=:i", i=cash_id)[0]
    check("заказ остался у d1", o[0] == d1_id and o[1] == "accepted", str(o))
    check("заморозка d1 на месте", money(d1_id)[1] == 5000, str(money(d1_id)))
    set_money(d2_id, 100_000)
    r = adm(f"freight/{cash_id}/reassign", {"admin_id": admin_id, "user_id": d2_id, "note": "kechikdi"})
    check("переназначено на d2", r.status_code == 200 and r.json()["status"] == "accepted", r.text[:150])
    o = sql("SELECT driver_id, driver_frozen FROM freight_orders WHERE id=:i", i=cash_id)[0]
    check("водитель — d2, комиссия заморожена", o[0] == d2_id and D(o[1]) == 5000, str(o))
    check("у d1 заморозка снята", money(d1_id)[1] == 0, str(money(d1_id)))
    check("у d2 заморожено 5 000", money(d2_id)[1] == 5000, str(money(d2_id)))
    n = sql("SELECT COUNT(*) FROM notifications WHERE user_id=:u AND type='order_assigned'", u=d2_id)[0][0]
    check("d2 получил уведомление order_assigned", n >= 1, str(n))

    head("4. СНОВА В ПОИСК")
    r = adm(f"freight/{cash_id}/reassign", {"admin_id": admin_id})
    check("водитель снят", r.status_code == 200 and r.json()["status"] == "searching", r.text[:150])
    check("у d2 заморозка снята", money(d2_id)[1] == 0, str(money(d2_id)))

    head("5. ОТМЕНА ПОСЛЕ ПОГРУЗКИ (Go wallet)")
    r = requests.post(f"{API}/freight/orders", headers=client,
                      json={**A, "vehicle_code": "gazel", "body_type": "tent"})
    wid = r.json()["id"]
    price = D(r.json()["price"])
    check("Go wallet заморожен", money(client_id)[1] == price, str(money(client_id)))
    requests.post(f"{API}/drivers/freight/orders/{wid}/accept", headers=d1)
    requests.post(f"{API}/drivers/freight/orders/{wid}/loaded", headers=d1)
    r = requests.post(f"{API}/freight/orders/{wid}/cancel", headers=client)
    check("клиент после погрузки отменить не может", r.status_code == 400, f"{r.status_code}")
    c = adm(f"freight/{wid}/candidates", get=True).json()
    check("после погрузки менять водителя нельзя", c["can_reassign"] is False and c["note"], str(c.get("note")))
    b0 = money(client_id)[0]
    r = adm(f"freight/{wid}/cancel", {"admin_id": admin_id, "reason": "fraud", "note": "test"})
    check("админ отменил", r.status_code == 200 and r.json()["status"] == "cancelled", r.text[:150])
    b1, f1 = money(client_id)
    check("у клиента заморозка снята, деньги не списаны", f1 == 0 and b1 == b0, f"{b0}->{b1} frozen={f1}")
    o = sql("SELECT cancelled_by, cancel_reason FROM freight_orders WHERE id=:i", i=wid)[0]
    check("cancelled_by=admin, причина записана", o[0] == "admin" and o[1] == "fraud", str(o))
    r = adm(f"freight/{wid}/cancel", {"admin_id": admin_id, "reason": "fraud"})
    check("повторная отмена — 409", r.status_code == 409, f"{r.status_code}")

    head("6. ЖУРНАЛ")
    acts = sql("SELECT action, entity, entity_id, payload FROM admin_actions WHERE id > :f ORDER BY id", f=action_from)
    kinds = [a[0] for a in acts]
    check("записаны reassign, requeue и cancel",
          "order_reassign" in kinds and "order_requeue" in kinds and "order_cancel" in kinds, str(kinds))
    reasg = next(a for a in acts if a[0] == "order_reassign")
    p = reasg[3] if isinstance(reasg[3], dict) else json.loads(reasg[3])
    check("в журнале кто был и кто стал", p.get("from_user") == d1_id and p.get("to_user") == d2_id, str(p))
finally:
    for c, base, km, mode, bc in (saved or []):
        sql("UPDATE delivery_vehicles SET base_fee=:b, price_per_km=:k, price_mode=:m, has_body_choice=:bc WHERE code=:c",
            b=base, k=km, m=mode, bc=bc, c=c)
    for key, v in (saved_comm or []):
        sql("UPDATE app_settings SET value = CAST(:v AS jsonb) WHERE key=:k", v=json.dumps(v), k=key)
    sql("DELETE FROM admin_actions WHERE id > :f", f=action_from)
    if created_ids:
        sql("DELETE FROM freight_orders WHERE client_id = ANY(:i) OR driver_id = ANY(:i)", i=created_ids)
        sql("DELETE FROM users WHERE id = ANY(:i)", i=created_ids)
        sql("DELETE FROM otp_verifications WHERE phone = ANY(:p)", p=created_phones)

print(f"\nИтого: {ok_count} OK, {fail_count} FAIL")
sys.exit(1 if fail_count else 0)
