"""
Регионы цен (Шерзодбек, 24.11.2026): admin/zones.php, zone_service.

Проверяется:
- точка в многоугольнике (свой ray casting, без библиотек);
- котировка: в зоне — цена зоны, вне — базовая; незаданная пара в зоне —
  базовая; надбавка зоны ложится на итог и округляется вверх до 1 000;
- пакет (Tezkor 6 ч): цена зоны — это цена ПАКЕТА;
- создание заказа считает ту же сумму, что котировка, и пишет зону в заявку;
- зона расширяет область обслуживания: Андижан вне ташкентского
  прямоугольника, без зоны — 400, с зоной — заказ создаётся;
- выключенная зона не действует;
- /settings/app-status отдаёт зоны приложению.
"""
import json
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
from app.services.zone_service import point_in_polygon  # noqa: E402

API = os.environ.get("API", "http://127.0.0.1:8000")
ok_count = fail_count = 0
created_ids, created_phones, zone_ids = [], [], []
TYPE = "compressor"   # не занят другими наборами; прежние тарифы восстанавливаются
_saved_tariffs = []

# Грубый квадрат вокруг Андижана (вне ташкентского прямоугольника).
ANDIJAN = [[40.60, 72.10], [40.95, 72.10], [40.95, 72.60], [40.60, 72.60]]
IN_ANDIJAN = (40.78, 72.34)
TASHKENT = (41.31, 69.24)


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
    r = requests.post(f"{API}/auth/register", json={"full_name": f"Sinov Hudud {role}", "phone": phone, "role": role})
    body = r.json()
    created_ids.append(body["user_id"])
    created_phones.append(phone)
    time.sleep(0.01)
    return body["user_id"], {"Authorization": f"Bearer {body['access_token']}"}


def set_money(uid, balance):
    if sql("SELECT 1 FROM balances WHERE user_id=:u", u=uid):
        sql("UPDATE balances SET balance=:b, frozen_balance=0, bonus_balance=0 WHERE user_id=:u", b=balance, u=uid)
    else:
        sql("INSERT INTO balances (user_id, balance, frozen_balance, bonus_balance) VALUES (:u, :b, 0, 0)",
            b=balance, u=uid)


def quotes(hdr, point, hours=2):
    r = requests.get(f"{API}/requests/tariffs", headers=hdr, params={
        "equipment_type": TYPE, "hours": hours, "latitude": point[0], "longitude": point[1]})
    return {q["tier"]: q for q in r.json()}


def order(hdr, point, tier="econom", hours=2):
    start = date.today() + timedelta(days=1)
    return requests.post(f"{API}/requests/", headers=hdr, json={
        "equipment_type": TYPE, "start_date": str(start), "end_date": str(start),
        "delivery_latitude": point[0], "delivery_longitude": point[1], "delivery_address": "Sinov",
        "mode": "quick", "start_time": "08:00:00", "tariff": tier, "hours": hours,
        "payment_method": "balance", "budget": 1000,
    })


def main():
    head("0. Точка в многоугольнике")
    check("центр квадрата — внутри", point_in_polygon(*IN_ANDIJAN, ANDIJAN))
    check("Ташкент — снаружи", not point_in_polygon(*TASHKENT, ANDIJAN))
    tri = [[0, 0], [0, 10], [10, 0]]
    check("треугольник: (2,2) внутри, (8,8) снаружи", point_in_polygon(2, 2, tri) and not point_in_polygon(8, 8, tri))

    _saved_tariffs.extend(sql("SELECT tier, price_per_hour, min_hours, is_active, eta_minutes, package_hours, "
                              "package_price FROM tariffs WHERE equipment_type = :t", t=TYPE) or [])
    sql("DELETE FROM tariffs WHERE equipment_type = :t", t=TYPE)
    sql("INSERT INTO tariffs (equipment_type, tier, price_per_hour, min_hours, package_hours, package_price) VALUES "
        "(:t,'econom',350000,1,NULL,NULL),(:t,'fast',400000,6,6,2400000)", t=TYPE)
    client_id, client = register("client")

    head("1. Без зон: Андижан вне области")
    set_money(client_id, 50_000_000)
    r = order(client, IN_ANDIJAN)
    check("заказ в Андижане без зоны — 400", r.status_code == 400, f"{r.status_code} {r.text[:120]}")

    zid = sql("INSERT INTO price_zones (name, polygon, surcharge_percent, sort_order) "
              "VALUES ('Sinov Andijon', CAST(:p AS json), 0, 0) RETURNING id", p=json.dumps(ANDIJAN))[0][0]
    zone_ids.append(zid)
    sql("INSERT INTO zone_tariffs (zone_id, equipment_type, tier, price) VALUES (:z, :t, 'econom', 300000)",
        z=zid, t=TYPE)

    head("2. Котировка по зоне")
    a = quotes(client, IN_ANDIJAN)
    t = quotes(client, TASHKENT)
    check("Андижан: econom 2 ч = 300 000 × 2", Decimal(str(a["econom"]["total"])) == 600000, a.get("econom"))
    check("в котировке имя зоны", a["econom"].get("zone_name") == "Sinov Andijon", a["econom"].get("zone_name"))
    check("Ташкент: econom 2 ч = 350 000 × 2 (базовая)", Decimal(str(t["econom"]["total"])) == 700000, t.get("econom"))
    check("Ташкент без зоны", t["econom"].get("zone_name") is None)
    check("незаданный в зоне Tezkor — базовый пакет 2 400 000", Decimal(str(a["fast"]["total"])) == 2400000, a.get("fast"))

    sql("INSERT INTO zone_tariffs (zone_id, equipment_type, tier, price) VALUES (:z, :t, 'fast', 2000000)",
        z=zid, t=TYPE)
    a = quotes(client, IN_ANDIJAN)
    check("Tezkor в зоне: цена пакета 2 000 000, 6 ч", Decimal(str(a["fast"]["total"])) == 2000000
          and a["fast"]["hours"] == 6, a.get("fast"))

    sql("UPDATE price_zones SET surcharge_percent = 15 WHERE id = :z", z=zid)
    a = quotes(client, IN_ANDIJAN)
    check("надбавка 15%: 600 000 → 690 000", Decimal(str(a["econom"]["total"])) == 690000, a.get("econom"))
    sql("UPDATE price_zones SET surcharge_percent = 7 WHERE id = :z", z=zid)
    a = quotes(client, IN_ANDIJAN)
    check("7%: 642 000 — уже круглое", Decimal(str(a["econom"]["total"])) == 642000, a.get("econom"))
    a3 = quotes(client, IN_ANDIJAN, hours=3)
    check("7% от 900 000 = 963 000", Decimal(str(a3["econom"]["total"])) == 963000, a3.get("econom"))

    head("3. Создание заказа — та же сумма")
    sql("UPDATE price_zones SET surcharge_percent = 10 WHERE id = :z", z=zid)
    exp = Decimal(str(quotes(client, IN_ANDIJAN)["econom"]["total"]))
    r = order(client, IN_ANDIJAN)
    check("заказ в Андижане с зоной создан", r.status_code in (200, 201), f"{r.status_code} {r.text[:150]}")
    if r.status_code in (200, 201):
        body = r.json()
        rid = body["id"]
        row = sql("SELECT budget, price_zone_id, frozen_amount FROM equipment_requests WHERE id=:i", i=rid)[0]
        check("сумма заказа = котировке (660 000)", Decimal(str(row[0])) == exp == 660000, f"{row[0]} {exp}")
        check("зона записана в заявку", row[1] == zid, row[1])
        check("заморожено столько же", Decimal(str(row[2])) == exp, row[2])
        requests.post(f"{API}/requests/{rid}/cancel", headers=client)

    head("4. Выключенная зона не действует")
    sql("UPDATE price_zones SET is_enabled = false WHERE id = :z", z=zid)
    a = quotes(client, IN_ANDIJAN)
    check("выключена — базовая 700 000", Decimal(str(a["econom"]["total"])) == 700000, a.get("econom"))
    r = order(client, IN_ANDIJAN)
    check("выключена — Андижан снова вне области (400)", r.status_code == 400, f"{r.status_code}")
    sql("UPDATE price_zones SET is_enabled = true WHERE id = :z", z=zid)

    head("5. Зоны в /settings/app-status")
    st = requests.get(f"{API}/settings/app-status").json()
    names = [z["name"] for z in st.get("zones", [])]
    check("зона отдаётся приложению", "Sinov Andijon" in names, names)
    check("с многоугольником", any(len(z["polygon"]) >= 3 for z in st.get("zones", [])))


def cleanup():
    db = SessionLocal()
    try:
        db.execute(text("DELETE FROM equipment_requests WHERE client_id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM otp_verifications WHERE phone = ANY(:ps)"), {"ps": created_phones})
        db.execute(text("DELETE FROM price_zones WHERE id = ANY(:ids)"), {"ids": zone_ids})
        db.execute(text("DELETE FROM tariffs WHERE equipment_type = :t"), {"t": TYPE})
        for r in _saved_tariffs:
            db.execute(text("INSERT INTO tariffs (equipment_type, tier, price_per_hour, min_hours, is_active, "
                            "eta_minutes, package_hours, package_price) VALUES (:t,:a,:b,:c,:d,:e,:f,:g)"),
                       {"t": TYPE, "a": r[0], "b": r[1], "c": r[2], "d": r[3], "e": r[4], "f": r[5], "g": r[6]})
        db.commit()
    finally:
        db.close()


if __name__ == "__main__":
    try:
        main()
    finally:
        cleanup()
    print(f"\nITOG: {ok_count} o'tdi, {fail_count} yiqildi")
    sys.exit(1 if fail_count else 0)
