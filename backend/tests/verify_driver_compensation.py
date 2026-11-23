"""
MoveX GO Driver, макет 02: компенсация за напрасный выезд (E1, E7) и
оценка клиента водителем (D6). 23.11.2026.

Проверяется:
- настройка 0 (по умолчанию) — денег не двигает: отмена после выезда
  возвращает клиенту залог целиком, как было;
- E1 наличные: клиент отменил ПОСЛЕ «Ketdik» — владелец получает
  компенсацию из залога, клиенту возвращается остаток, деньги сходятся;
- отмена ДО выезда — без компенсации;
- компенсация не больше залога и не трогает бонус клиента;
- E7 «Mijoz kelmadi»: раньше 15 минут — отмена без денег; после —
  с компенсацией; до «Yetib keldim» — 409; клиенту — 403;
- E7 для заказа с баланса: компенсация из эскроу, остаток клиенту,
  и ветка «старого заказа» (frozen_amount == 0) НЕ срабатывает, даже
  если компенсация забрала весь эскроу;
- D6: оценка до завершения — 409, чужому — 403, повтор переписывает,
  неизвестные плашки отбрасываются, средняя видна во входящем заказе.
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

API = os.environ.get("API", "http://127.0.0.1:8000")
TYPE = "auger_drill"   # свой тип — не мешать другим наборам
COMP_KEY = "cancel_compensation_amount"
DEPOSIT_KEY = "cash_deposit_amount"
ok_count = fail_count = 0
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


def setting(key, value):
    if value is None:
        sql("DELETE FROM app_settings WHERE key=:k", k=key)
    elif sql("SELECT 1 FROM app_settings WHERE key=:k", k=key):
        sql("UPDATE app_settings SET value=to_jsonb(CAST(:v AS text)) WHERE key=:k", k=key, v=str(value))
    else:
        sql("INSERT INTO app_settings (key, value) VALUES (:k, to_jsonb(CAST(:v AS text)))", k=key, v=str(value))


def get_setting(key):
    row = sql("SELECT value #>> '{}' FROM app_settings WHERE key=:k", k=key)
    return row[0][0] if row else None


def register(role):
    phone = f"9989{int(time.time() * 1000) % 100000000:08d}"[:12]
    requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": otp_code(phone)})
    r = requests.post(f"{API}/auth/register", json={"full_name": f"Sinov Komp {role}", "phone": phone, "role": role})
    body = r.json()
    created_ids.append(body["user_id"])
    created_phones.append(phone)
    time.sleep(0.01)
    sql("UPDATE users SET search_latitude=NULL, search_longitude=NULL WHERE id=:u", u=body["user_id"])
    return body["user_id"], {"Authorization": f"Bearer {body['access_token']}"}


def money(uid):
    row = sql("SELECT balance, frozen_balance FROM balances WHERE user_id=:u", u=uid)
    return (Decimal(str(row[0][0])), Decimal(str(row[0][1]))) if row else (Decimal(0), Decimal(0))


def set_money(uid, balance, frozen=0, bonus=0):
    if sql("SELECT 1 FROM balances WHERE user_id=:u", u=uid):
        sql("UPDATE balances SET balance=:b, frozen_balance=:f, bonus_balance=:x WHERE user_id=:u",
            b=balance, f=frozen, x=bonus, u=uid)
    else:
        sql("INSERT INTO balances (user_id, balance, frozen_balance, bonus_balance) VALUES (:u, :b, :f, :x)",
            b=balance, f=frozen, x=bonus, u=uid)


def order(client, owner, owner_id, payment="cash"):
    start = date.today() + timedelta(days=1)
    r = requests.post(f"{API}/requests/", headers=client, json={
        "equipment_type": TYPE, "start_date": str(start), "end_date": str(start),
        "delivery_latitude": 41.31, "delivery_longitude": 69.24, "delivery_address": "Sinov",
        "mode": "quick", "start_time": "08:00:00", "tariff": "econom", "hours": 1,
        "payment_method": payment,
    })
    assert r.status_code == 200, r.text
    set_money(owner_id, 1000000)
    r = requests.post(f"{API}/requests/{r.json()['id']}/quick-accept", headers=owner)
    assert r.status_code == 200, r.text
    return r.json()["order_id"]


def total_money(*uids):
    return sum(money(u)[0] for u in uids)


def main():
    sql("DELETE FROM tariffs WHERE equipment_type=:t", t=TYPE)
    sql("INSERT INTO tariffs (equipment_type, tier, price_per_hour, min_hours) VALUES (:t,'econom',200000,1)", t=TYPE)
    client_id, client = register("client")
    owner_id, owner = register("owner")
    other_id, other = register("owner")
    requests.post(f"{API}/equipment/", headers=owner, json={
        "type": TYPE, "model": "Sinov komp", "price_per_day": "500000",
        "latitude": "41.30", "longitude": "69.25", "status": "available", "available": True})

    r = requests.get(f"{API}/drivers/settings", headers=owner)
    check("/drivers/settings отвечает, ожидание 15 минут",
          r.status_code == 200 and r.json()["no_show_wait_minutes"] == 15, r.text)

    head("1. Настройка 0 — денег не двигает")
    setting(COMP_KEY, None)
    setting(DEPOSIT_KEY, 50000)
    check("по умолчанию компенсация 0", requests.get(f"{API}/drivers/settings", headers=owner).json()
          ["compensation_amount"] == 0)
    set_money(client_id, 100000)
    oid = order(client, owner, owner_id)
    requests.post(f"{API}/orders/{oid}/depart", headers=owner)
    r = requests.put(f"{API}/orders/{oid}", headers=client, json={"status": "cancelled"})
    check("клиент отменил после выезда", r.status_code == 200, r.text)
    check("залог вернулся целиком", money(client_id) == (Decimal("100000"), Decimal(0)), money(client_id))
    check("владельцу ничего", money(owner_id)[0] == Decimal("1000000"), money(owner_id))

    head("2. E1 наличные: отмена после «Ketdik»")
    setting(COMP_KEY, 30000)
    set_money(client_id, 100000)
    oid = order(client, owner, owner_id)
    before = total_money(client_id, owner_id)
    requests.post(f"{API}/orders/{oid}/depart", headers=owner)
    r = requests.put(f"{API}/orders/{oid}", headers=client, json={"status": "cancelled"})
    check("отменено", r.status_code == 200 and r.json()["status"] == "cancelled", r.text)
    check("в заказе compensation = 30 000", r.json().get("compensation") == 30000, r.json().get("compensation"))
    check("клиент: −30 000, заморозки нет", money(client_id) == (Decimal("70000"), Decimal(0)), money(client_id))
    check("владелец: +30 000", money(owner_id)[0] == Decimal("1030000"), money(owner_id))
    check("деньги не создаются и не исчезают", total_money(client_id, owner_id) == before)
    tx = sql("SELECT type FROM balance_transactions WHERE order_id=:o ORDER BY id", o=oid)
    check("две проводки: payment клиента и income владельца",
          sorted(x[0] for x in tx) == ["income", "payment"], tx)

    head("3. Отмена ДО выезда — без компенсации")
    set_money(client_id, 100000)
    oid = order(client, owner, owner_id)
    requests.put(f"{API}/orders/{oid}", headers=client, json={"status": "cancelled"})
    check("залог вернулся целиком", money(client_id) == (Decimal("100000"), Decimal(0)), money(client_id))

    head("4. Не больше залога и не из бонуса")
    setting(COMP_KEY, 80000)
    set_money(client_id, 100000)
    oid = order(client, owner, owner_id)
    requests.post(f"{API}/orders/{oid}/depart", headers=owner)
    requests.put(f"{API}/orders/{oid}", headers=client, json={"status": "cancelled"})
    check("80 000 > залога 50 000 — взято 50 000", money(client_id) == (Decimal("50000"), Decimal(0)),
          money(client_id))
    set_money(client_id, 100000, bonus=80000)
    oid = order(client, owner, owner_id)
    requests.post(f"{API}/orders/{oid}/depart", headers=owner)
    r = requests.put(f"{API}/orders/{oid}", headers=client, json={"status": "cancelled"})
    check("свои деньги 20 000 — взято только 20 000",
          r.json().get("compensation") == 20000 and money(client_id) == (Decimal("80000"), Decimal(0)),
          (r.json().get("compensation"), money(client_id)))

    head("5. E7 «Mijoz kelmadi»")
    setting(COMP_KEY, 30000)
    set_money(client_id, 100000)
    oid = order(client, owner, owner_id)
    r = requests.post(f"{API}/orders/{oid}/no-show", headers=owner)
    check("до «Yetib keldim» — 409", r.status_code == 409, r.text)
    requests.post(f"{API}/orders/{oid}/arrive", headers=owner)
    r = requests.post(f"{API}/orders/{oid}/no-show", headers=client)
    check("клиенту — 403", r.status_code == 403, r.text)
    r = requests.post(f"{API}/orders/{oid}/no-show", headers=owner)
    check("через минуту — отмена без денег",
          r.status_code == 200 and r.json()["status"] == "cancelled" and r.json().get("compensation") == 0, r.text)
    check("причина client_no_show, отменил владелец",
          r.json().get("cancel_reason") == "client_no_show" and r.json().get("cancelled_by") == "owner", r.json())
    check("залог вернулся", money(client_id) == (Decimal("100000"), Decimal(0)), money(client_id))

    oid = order(client, owner, owner_id)
    requests.post(f"{API}/orders/{oid}/arrive", headers=owner)
    sql("UPDATE orders SET arrived_at = now() - interval '16 minutes' WHERE id=:o", o=oid)
    before = total_money(client_id, owner_id)
    r = requests.post(f"{API}/orders/{oid}/no-show", headers=owner)
    check("через 16 минут — с компенсацией 30 000", r.json().get("compensation") == 30000, r.text)
    check("клиент −30 000, заморозки нет", money(client_id) == (Decimal("70000"), Decimal(0)), money(client_id))
    check("деньги сходятся", total_money(client_id, owner_id) == before)

    head("6. E7 с баланса: компенсация из эскроу")
    setting(DEPOSIT_KEY, 0)
    set_money(client_id, 1000000)
    oid = order(client, owner, owner_id, payment="balance")
    frozen = Decimal(str(sql("SELECT frozen_amount FROM orders WHERE id=:o", o=oid)[0][0]))
    check("эскроу заказа = 200 000", frozen == Decimal("200000"), frozen)
    requests.post(f"{API}/orders/{oid}/arrive", headers=owner)
    sql("UPDATE orders SET arrived_at = now() - interval '20 minutes' WHERE id=:o", o=oid)
    before = total_money(client_id, owner_id)
    r = requests.post(f"{API}/orders/{oid}/no-show", headers=owner)
    check("отменено с компенсацией 30 000", r.status_code == 200 and r.json().get("compensation") == 30000, r.text)
    check("клиент: −30 000, эскроу снят", money(client_id) == (Decimal("970000"), Decimal(0)), money(client_id))
    check("деньги сходятся", total_money(client_id, owner_id) == before)

    setting(COMP_KEY, 500000)   # больше всего эскроу
    set_money(client_id, 1000000)
    oid = order(client, owner, owner_id, payment="balance")
    requests.post(f"{API}/orders/{oid}/arrive", headers=owner)
    sql("UPDATE orders SET arrived_at = now() - interval '20 minutes' WHERE id=:o", o=oid)
    owner_before = money(owner_id)[0]
    r = requests.post(f"{API}/orders/{oid}/no-show", headers=owner)
    check("компенсация = весь эскроу 200 000", r.json().get("compensation") == 200000, r.text)
    check("ветка «старого заказа» не сработала: владелец +200 000, не −",
          money(owner_id)[0] == owner_before + Decimal("200000"), (owner_before, money(owner_id)))
    check("клиент −200 000", money(client_id) == (Decimal("800000"), Decimal(0)), money(client_id))
    setting(COMP_KEY, 30000)

    head("7. D6 оценка клиента")
    setting(DEPOSIT_KEY, 50000)
    set_money(client_id, 100000)
    oid = order(client, owner, owner_id)
    r = requests.post(f"{API}/orders/{oid}/rate-client", headers=owner, json={"rating": 5})
    check("до завершения — 409", r.status_code == 409, r.text)
    requests.post(f"{API}/orders/{oid}/start", headers=owner)
    requests.post(f"{API}/orders/{oid}/finish", headers=owner)
    r = requests.post(f"{API}/orders/{oid}/rate-client", headers=other, json={"rating": 1})
    check("чужой владелец — 403", r.status_code == 403, r.text)
    r = requests.post(f"{API}/orders/{oid}/rate-client", headers=owner,
                      json={"rating": 4, "tags": ["polite", "hack", "polite"]})
    check("оценка 4 сохранена, чужая плашка и повтор выброшены",
          r.status_code == 200 and r.json()["tags"] == ["polite"] and r.json()["rating"] == 4, r.text)
    r = requests.post(f"{API}/orders/{oid}/rate-client", headers=owner, json={"rating": 2, "tags": ["kept_waiting"]})
    n = sql("SELECT count(*), max(rating) FROM client_ratings WHERE order_id=:o", o=oid)[0]
    check("повтор переписывает, а не добавляет", n[0] == 1 and n[1] == 2, n)
    r = requests.post(f"{API}/orders/{oid}/rate-client", headers=owner, json={"rating": 6})
    check("оценка 6 — 422", r.status_code == 422, r.status_code)
    r = requests.get(f"{API}/orders/{oid}/client-rating", headers=owner)
    check("сводка: 2.0 из 1 оценки, своя оценка видна",
          r.json()["rating"] == 2.0 and r.json()["count"] == 1 and r.json()["mine"]["tags"] == ["kept_waiting"],
          r.text)
    requests.put(f"{API}/orders/{oid}", headers=client, json={"status": "completed"})

    start = date.today() + timedelta(days=1)
    requests.post(f"{API}/requests/", headers=client, json={
        "equipment_type": TYPE, "start_date": str(start), "end_date": str(start),
        "delivery_latitude": 41.31, "delivery_longitude": 69.24, "delivery_address": "Sinov",
        "mode": "quick", "start_time": "08:00:00", "tariff": "econom", "hours": 1, "payment_method": "cash"})
    inc = requests.get(f"{API}/requests/quick/incoming", headers=owner).json()
    mine = [x for x in inc if x["equipment_type"] == TYPE]
    check("во входящем заказе видна оценка клиента 2.0", mine and mine[0].get("client_rating") == 2.0,
          mine[:1])


def cleanup():
    db = SessionLocal()
    try:
        db.execute(text("DELETE FROM equipment_requests WHERE client_id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM orders WHERE user_id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM otp_verifications WHERE phone = ANY(:ps)"), {"ps": created_phones})
        db.execute(text("DELETE FROM tariffs WHERE equipment_type = :t"), {"t": TYPE})
        db.commit()
    finally:
        db.close()


if __name__ == "__main__":
    saved = {k: get_setting(k) for k in (COMP_KEY, DEPOSIT_KEY)}
    try:
        main()
    finally:
        for k, v in saved.items():
            setting(k, v)
        cleanup()
    print(f"\nITOG: {ok_count} o'tdi, {fail_count} yiqildi")
    sys.exit(1 if fail_count else 0)
