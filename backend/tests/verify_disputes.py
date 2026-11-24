"""
Nizolar, «Yordam» chati, sharhlar moderatsiyasi (Figma «Admin panel» 07, 24.11.2026).

Что сторожит:
  - открыть спор может клиент и исполнитель, чужой — 403; причины по ролям;
    повторное открытие возвращает тот же спор;
  - видимость: внутренняя заметка админа не видна никому из сторон,
    сообщение «только клиенту» не видно исполнителю; первый ответ ставит SLA;
  - qisman (перевозка, Go wallet): клиент платит цену − R, водитель получает
    цену − R − комиссия, заморозка снята полностью;
  - qisman (техника, Go wallet) — через обычное завершение заказа;
  - mijoz foydasiga — заказ отменён, деньги не списаны;
  - naqd: qisman запрещён (409), «yopish» — деньги не двигаются;
  - решённый спор повторно не решается;
  - чат поддержки: сообщение пользователя, ответ админа, счётчик непрочитанных;
  - скрытый отзыв не входит в рейтинг и не отдаётся в /reviews.

    API=http://127.0.0.1:8010 venv/Scripts/python tests/verify_disputes.py
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


def set_money(uid, b, frozen=0):
    if sql("SELECT 1 FROM balances WHERE user_id=:u", u=uid):
        sql("UPDATE balances SET balance=:b, frozen_balance=:f, bonus_balance=0 WHERE user_id=:u", b=b, f=frozen, u=uid)
    else:
        sql("INSERT INTO balances (user_id, balance, frozen_balance, bonus_balance) VALUES (:u,:b,:f,0)", u=uid, b=b, f=frozen)


def adm(path, body=None, get=False):
    url = f"{API}/admin-orders/internal/{path}"
    return requests.get(url, headers=SECRET) if get else requests.post(url, headers=SECRET, json=body or {})


A = {"from_latitude": 41.30, "from_longitude": 69.24, "to_latitude": 41.35, "to_longitude": 69.30,
     "from_address": "Chorsu", "to_address": "Yunusobod"}
admin_id = sql("SELECT id FROM users WHERE role='admin' ORDER BY id LIMIT 1")[0][0]
saved = sql("SELECT code, base_fee, price_per_km, price_mode, has_body_choice FROM delivery_vehicles WHERE code='gazel'")
saved_comm = sql("SELECT key, value FROM app_settings WHERE key IN ('commission_mode','commission_fixed')")
sql("UPDATE app_settings SET value = to_jsonb('fixed'::text) WHERE key='commission_mode'")
sql("UPDATE app_settings SET value = to_jsonb('5000'::text) WHERE key='commission_fixed'")
sql("UPDATE delivery_vehicles SET base_fee=30000, price_per_km=4000, price_mode='km', has_body_choice=true WHERE code='gazel'")
eq_order_id = None
review_id = None
owner_saved = None

try:
    client_id, client = register("client", "Sinov nizo mijoz")
    d1_id, d1 = register("owner", "Sinov nizo haydovchi")
    other_id, other = register("client", "Begona")
    r = requests.put(f"{API}/drivers/delivery/profile", headers=d1,
                     json={"vehicle_code": "gazel", "body_type": "tent", "categories": []})
    assert r.status_code == 200, r.text
    requests.post(f"{API}/drivers/delivery/heartbeat", headers=d1, json={"online": True, "latitude": 41.29, "longitude": 69.23})
    set_money(client_id, 1_000_000)
    set_money(d1_id, 100_000)

    head("1. ОТКРЫТИЕ СПОРА (перевозка, Go wallet)")
    r = requests.post(f"{API}/freight/orders", headers=client, json={**A, "vehicle_code": "gazel", "body_type": "tent"})
    fid = r.json()["id"]
    price = D(r.json()["price"])
    requests.post(f"{API}/drivers/freight/orders/{fid}/accept", headers=d1)
    requests.post(f"{API}/drivers/freight/orders/{fid}/loaded", headers=d1)
    r = requests.post(f"{API}/disputes", headers=other, json={"kind": "freight", "order_id": fid, "reason": "damaged"})
    check("чужой — 403", r.status_code == 403, f"{r.status_code}")
    r = requests.post(f"{API}/disputes", headers=client, json={"kind": "freight", "order_id": fid, "reason": "client_no_pay"})
    check("клиент не может выбрать причину исполнителя — 400", r.status_code == 400, f"{r.status_code}")
    r = requests.post(f"{API}/disputes", headers=client,
                      json={"kind": "freight", "order_id": fid, "reason": "damaged", "comment": "Yuk shikastlangan"})
    check("клиент открыл спор", r.status_code == 200 and r.json()["status"] == "open", r.text[:200])
    pid = r.json()["id"]
    r2 = requests.post(f"{API}/disputes", headers=client, json={"kind": "freight", "order_id": fid, "reason": "damaged"})
    check("повторно — тот же спор", r2.json().get("id") == pid)
    check("водитель видит спор в /disputes/mine",
          any(x["id"] == pid for x in requests.get(f"{API}/disputes/mine", headers=d1).json()))

    head("2. ПЕРЕПИСКА И ВИДИМОСТЬ")
    requests.post(f"{API}/disputes/{pid}/messages", headers=d1, json={"text": "Yuk butun edi"})
    adm(f"disputes/{pid}/message", {"admin_id": admin_id, "text": "GPS tekshirildi", "visibility": "internal"})
    sla = sql("SELECT first_response_at FROM order_problems WHERE id=:i", i=pid)[0][0]
    check("внутренняя заметка не ставит первый ответ", sla is None, str(sla))
    adm(f"disputes/{pid}/message", {"admin_id": admin_id, "text": "Faqat mijozga", "visibility": "client"})
    adm(f"disputes/{pid}/message", {"admin_id": admin_id, "text": "Ikkalasiga", "visibility": "all"})
    cv = [m["text"] for m in requests.get(f"{API}/disputes/{pid}", headers=client).json()["messages"]]
    dv = [m["text"] for m in requests.get(f"{API}/disputes/{pid}", headers=d1).json()["messages"]]
    check("клиент видит своё, водителя и «Faqat mijozga»", "Yuk butun edi" in cv and "Faqat mijozga" in cv and "Ikkalasiga" in cv, str(cv))
    check("водитель не видит «Faqat mijozga»", "Faqat mijozga" not in dv and "Ikkalasiga" in dv, str(dv))
    check("внутреннюю заметку не видит никто", "GPS tekshirildi" not in cv + dv)
    p = sql("SELECT first_response_at, assigned_admin_id FROM order_problems WHERE id=:i", i=pid)[0]
    check("первый ответ и ответственный записаны", p[0] is not None and p[1] == admin_id, str(p))
    n = sql("SELECT COUNT(*) FROM notifications WHERE user_id=:u AND type='dispute_message'", u=d1_id)[0][0]
    check("водитель получил уведомление dispute_message", n >= 1, str(n))

    head("3. QISMAN — перевозка")
    o = adm(f"disputes/{pid}/options", get=True).json()
    check("qisman доступен (Go wallet, груз в машине)", o["options"]["partial"] is None, str(o))
    r = adm(f"disputes/{pid}/resolve", {"admin_id": admin_id, "decision": "partial", "refund_amount": float(price)})
    check("возврат = вся сумма для qisman — 400", r.status_code == 400, f"{r.status_code}")
    c0, _ = money(client_id)
    w0, _ = money(d1_id)
    R = D(20000)
    r = adm(f"disputes/{pid}/resolve", {"admin_id": admin_id, "decision": "partial", "refund_amount": 20000, "note": "test"})
    check("решение принято", r.status_code == 200 and r.json()["resolution"] == "partial", r.text[:200])
    c1, cf1 = money(client_id)
    w1, _ = money(d1_id)
    check("клиент заплатил цену − R", c0 - c1 == price - R and cf1 == 0, f"{c0 - c1} vs {price - R}, frozen={cf1}")
    check("водитель получил цену − R − 5 000", w1 - w0 == price - R - 5000, f"{w1 - w0}")
    st = sql("SELECT status FROM freight_orders WHERE id=:i", i=fid)[0][0]
    check("перевозка завершена", st == "done", st)
    r = adm(f"disputes/{pid}/resolve", {"admin_id": admin_id, "decision": "close"})
    check("повторное решение — 409", r.status_code == 409, f"{r.status_code}")
    cv = [m["text"] for m in requests.get(f"{API}/disputes/{pid}", headers=client).json()["messages"]]
    check("клиент видит текст решения", any("Qaror: qisman" in (t or "") for t in cv), str(cv[-1:]))

    head("4. MIJOZ FOYDASIGA и NAQD")
    r = requests.post(f"{API}/freight/orders", headers=client, json={**A, "vehicle_code": "gazel", "body_type": "tent"})
    f2 = r.json()["id"]
    requests.post(f"{API}/drivers/freight/orders/{f2}/accept", headers=d1)
    p2 = requests.post(f"{API}/disputes", headers=d1, json={"kind": "freight", "order_id": f2, "reason": "client_absent"}).json()["id"]
    c0, _ = money(client_id)
    r = adm(f"disputes/{p2}/resolve", {"admin_id": admin_id, "decision": "client"})
    c1, cf1 = money(client_id)
    check("отменено в пользу клиента, деньги не списаны", r.status_code == 200 and c1 == c0 and cf1 == 0, f"{c0}->{c1} frozen={cf1}")
    r = requests.post(f"{API}/freight/orders", headers=client, json={**A, "vehicle_code": "gazel", "body_type": "tent", "payment_method": "cash"})
    f3 = r.json()["id"]
    requests.post(f"{API}/drivers/freight/orders/{f3}/accept", headers=d1)
    requests.post(f"{API}/drivers/freight/orders/{f3}/loaded", headers=d1)
    p3 = requests.post(f"{API}/disputes", headers=client, json={"kind": "freight", "order_id": f3, "reason": "price_differs"}).json()["id"]
    r = adm(f"disputes/{p3}/resolve", {"admin_id": admin_id, "decision": "partial", "refund_amount": 1000})
    check("naqd: qisman — 409", r.status_code == 409, f"{r.status_code} {r.text[:120]}")
    w0 = money(d1_id)
    r = adm(f"disputes/{p3}/resolve", {"admin_id": admin_id, "decision": "close"})
    check("naqd: yopildi, деньги не двигались", r.status_code == 200 and money(d1_id) == w0, str(money(d1_id)))

    head("5. QISMAN — техника (Go wallet)")
    eq = sql("SELECT e.id, e.owner_id FROM equipment e WHERE e.deleted_at IS NULL AND e.owner_id <> :c LIMIT 1", c=client_id)[0]
    owner_saved = (eq[1], money(eq[1]))
    total = D(300000)
    eq_order_id = sql("""INSERT INTO orders (user_id, equipment_id, start_date, end_date, status, total_amount, commission,
                         frozen_amount, payment_method, owner_frozen, delivery_latitude, delivery_longitude, delivery_address)
                         VALUES (:u, :e, CURRENT_DATE, CURRENT_DATE, 'confirmed', :t, 5000, :t, 'balance', 0, '41.3', '69.24', 'Test') RETURNING id""",
                      u=client_id, e=eq[0], t=total)[0][0]
    set_money(client_id, 1_000_000, frozen=total)
    o0, _ = money(eq[1])
    pe = requests.post(f"{API}/disputes", headers=client, json={"kind": "equipment", "order_id": eq_order_id, "reason": "poor_quality"}).json()
    check("спор по технике открыт, автоподтверждение остановлено",
          sql("SELECT problem_reported_at FROM orders WHERE id=:i", i=eq_order_id)[0][0] is not None, str(pe)[:150])
    c0, _ = money(client_id)
    r = adm(f"disputes/{pe['id']}/resolve", {"admin_id": admin_id, "decision": "partial", "refund_amount": 100000})
    c1, cf1 = money(client_id)
    o1, _ = money(eq[1])
    check("решено", r.status_code == 200, r.text[:200])
    check("клиент заплатил 200 000, заморозка снята", c0 - c1 == 200000 and cf1 == 0, f"{c0 - c1} frozen={cf1}")
    check("владелец получил 195 000", o1 - o0 == 195000, f"{o1 - o0}")
    check("заказ completed", sql("SELECT status FROM orders WHERE id=:i", i=eq_order_id)[0][0] == "completed")

    head("6. ЧАТ ПОДДЕРЖКИ")
    t = requests.get(f"{API}/support/thread", headers=client, params={"app": "client"}).json()
    check("до первого сообщения чата нет", t["status"] == "none")
    t = requests.post(f"{API}/support/messages", headers=client, json={"app": "client", "text": "SMS kelmayapti"}).json()
    check("сообщение отправлено", t["status"] == "open" and t["messages"][-1]["mine"] is True, str(t)[:150])
    r = adm(f"support/{t['id']}/reply", {"admin_id": admin_id, "text": "Tekshiryapmiz"})
    check("админ ответил", r.status_code == 200, r.text[:120])
    u = requests.get(f"{API}/support/unread", headers=client, params={"app": "client"}).json()["count"]
    check("непрочитанных — 1", u == 1, str(u))
    t = requests.get(f"{API}/support/thread", headers=client, params={"app": "client"}).json()
    check("ответ виден, непрочитанные обнулились", t["messages"][-1]["is_admin"] is True and
          requests.get(f"{API}/support/unread", headers=client, params={"app": "client"}).json()["count"] == 0)
    adm(f"support/{t['id']}/close", {"admin_id": admin_id})
    t2 = requests.post(f"{API}/support/messages", headers=client, json={"app": "client", "text": "Yana savol"}).json()
    check("после закрытия — новый чат", t2["id"] != t["id"], f"{t2['id']} {t['id']}")
    t3 = requests.get(f"{API}/support/thread", headers=other, params={"app": "client"}).json()
    check("чужой чат не виден", t3["status"] == "none")

    head("7. ОТЗЫВЫ")
    review_id = sql("INSERT INTO reviews (equipment_id, user_id, rating, comment) VALUES (:e, :u, 1, 'Telegram @spam') RETURNING id",
                    e=eq[0], u=client_id)[0][0]
    vis = lambda: any(x["id"] == review_id for x in requests.get(f"{API}/reviews/", headers=client, params={"equipment_id": eq[0], "limit": 200}).json())  # noqa: E731
    check("отзыв виден до модерации", vis())
    r = adm(f"reviews/{review_id}/moderate", {"admin_id": admin_id, "hide": True, "reason": "ads"})
    check("скрыт", r.status_code == 200 and r.json()["hidden"] is True, r.text[:120])
    check("скрытый не отдаётся в /reviews", not vis())
    n = sql("SELECT COUNT(*) FROM notifications WHERE user_id=:u AND type='review_hidden'", u=client_id)[0][0]
    check("автор получил уведомление", n == 1, str(n))
finally:
    for c, base, km, mode, bc in (saved or []):
        sql("UPDATE delivery_vehicles SET base_fee=:b, price_per_km=:k, price_mode=:m, has_body_choice=:bc WHERE code=:c",
            b=base, k=km, m=mode, bc=bc, c=c)
    for key, v in (saved_comm or []):
        sql("UPDATE app_settings SET value = CAST(:v AS jsonb) WHERE key=:k", v=json.dumps(v), k=key)
    if owner_saved:
        set_money(owner_saved[0], owner_saved[1][0], frozen=owner_saved[1][1])
    if review_id:
        sql("DELETE FROM reviews WHERE id=:i", i=review_id)
    if created_ids:
        sql("DELETE FROM order_problems WHERE user_id = ANY(:i)", i=created_ids)
        sql("DELETE FROM admin_actions WHERE entity='dispute' AND entity_id NOT IN (SELECT id FROM order_problems)")
        sql("DELETE FROM freight_orders WHERE client_id = ANY(:i) OR driver_id = ANY(:i)", i=created_ids)
        if eq_order_id:
            sql("DELETE FROM balance_transactions WHERE order_id=:o", o=eq_order_id)
            sql("DELETE FROM budget_reserves WHERE order_id=:o", o=eq_order_id)
            sql("DELETE FROM orders WHERE id=:o", o=eq_order_id)
        sql("DELETE FROM users WHERE id = ANY(:i)", i=created_ids)
        sql("DELETE FROM otp_verifications WHERE phone = ANY(:p)", p=created_phones)

print(f"\nИтого: {ok_count} OK, {fail_count} FAIL")
sys.exit(1 if fail_count else 0)
