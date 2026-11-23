"""
Справочники из админки (23.11.2026): типы техники (equipment_catalog),
машины доставки (delivery_vehicles), переключатель стройматериалов.

Что сторожит:
  - /equipment/catalog отдаёт группы и включённые типы, без входа;
  - выключенный в админке тип нельзя заказать (кэш живёт 30 с — тест ждёт);
  - тип, заведённый в админке, проходит проверку как родной;
  - иконку грузит только админка (X-Admin-Secret), чужому — 403;
  - машины берутся из базы: Damas … HOWO, по возрастанию грузоподъёмности;
  - цена машины из админки считает доставку: (подача + км × цена) × рейсы;
  - выключенные стройматериалы: app-status = false и заказ — 403.

Тест возвращает базу как было: тип, машина и настройка восстанавливаются.

Запуск (сервер работает):
    API=http://127.0.0.1:8010 venv/Scripts/python tests/verify_catalog.py
"""
import io
import os
import sys
import time

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _auth import token  # noqa: E402

API = os.environ.get("API", "http://127.0.0.1:8000")
SECRET = os.environ.get("ADMIN_INTERNAL_SECRET")
if not SECRET:
    env = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env")
    for line in open(env, encoding="utf-8"):
        if line.startswith("ADMIN_INTERNAL_SECRET="):
            SECRET = line.split("=", 1)[1].strip()

SELLER_PHONE = "998901110001"
BUYER_PHONE = "998901110002"
ADMIN_PHONE = "998900000000"

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
    print(f"\n=== {t} ===")


def sql(query, **params):
    from sqlalchemy import text

    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        res = db.execute(text(query), params)
        db.commit()
        try:
            return res.fetchall()
        except Exception:
            return None
    finally:
        db.close()


buyer = token(BUYER_PHONE, API)
seller = token(SELLER_PHONE, API)
admin = token(ADMIN_PHONE, API)

head("1. СПРАВОЧНИК ТИПОВ")

r = requests.get(f"{API}/equipment/catalog", params={"lang": "uz"})
check("каталог отдаётся без входа", r.status_code == 200, f"{r.status_code}")
cat = r.json()
codes = [t["code"] for t in cat["types"]]
check("группы на месте", {g["code"] for g in cat["groups"]} >= {"earth", "lifting", "transport"},
      str(cat["groups"]))
check("все родные типы в каталоге", {"excavator", "bulldozer", "truck_crane", "front_loader"} <= set(codes),
      str(codes))
exc = next(t for t in cat["types"] if t["code"] == "excavator")
check("название на узбекском", exc["name"] == "Ekskavator", exc["name"])
r = requests.get(f"{API}/equipment/catalog", params={"lang": "ru"})
check("и на русском", next(t for t in r.json()["types"] if t["code"] == "excavator")["name"] == "Экскаватор")
check("у типа есть признак тарифа", "has_tariff" in exc)

head("2. НОВЫЙ ТИП ИЗ АДМИНКИ И ВЫКЛЮЧЕНИЕ")

sql("DELETE FROM equipment_catalog WHERE code = 'vacuum_test'")
sql("""INSERT INTO equipment_catalog (code, name_uz, name_ru, group_code, sort_order)
       VALUES ('vacuum_test', 'Assenizator (test)', 'Ассенизатор (тест)', 'other', 999)""")
sql("UPDATE equipment_catalog SET is_enabled = false WHERE code = 'compressor'")
try:
    r = requests.get(f"{API}/equipment/catalog")
    codes = [t["code"] for t in r.json()["types"]]
    check("новый тип сразу виден в каталоге", "vacuum_test" in codes)
    check("выключенный тип пропал из каталога", "compressor" not in codes)

    print("  … ждём 31 с, пока обновится кэш типов на сервере")
    time.sleep(31)

    r = requests.post(f"{API}/listings/", headers=buyer, json={
        "title": "Assenizator kerak (test)", "description": "test",
        "equipment_type": "vacuum_test", "budget": 300000,
    })
    check("объявление с новым типом принято", r.status_code in (200, 201), f"{r.status_code} {r.text[:150]}")
    if r.status_code in (200, 201):
        lid = r.json()["id"]
        requests.post(f"{API}/listings/{lid}/cancel", headers=buyer)

    r = requests.post(f"{API}/listings/", headers=buyer, json={
        "title": "Kompressor kerak (test)", "description": "test",
        "equipment_type": "compressor", "budget": 300000,
    })
    check("с выключенным типом — отказ", r.status_code == 400, f"{r.status_code} {r.text[:150]}")
    if r.status_code in (200, 201):
        requests.post(f"{API}/listings/{r.json()['id']}/cancel", headers=buyer)

    head("3. ИКОНКА — ТОЛЬКО ИЗ АДМИНКИ")

    png = io.BytesIO(
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4"
        b"\x89\x00\x00\x00\rIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82"
    )
    r = requests.post(f"{API}/equipment/internal/catalog/vacuum_test/icon",
                      files={"file": ("x.png", png.getvalue(), "image/png")})
    check("без секрета — 403", r.status_code == 403, f"{r.status_code}")
    r = requests.post(f"{API}/equipment/internal/catalog/vacuum_test/icon", headers=admin,
                      files={"file": ("x.png", png.getvalue(), "image/png")})
    check("токен админа приложения не заменяет секрет", r.status_code == 403, f"{r.status_code}")
    r = requests.post(f"{API}/equipment/internal/catalog/vacuum_test/icon",
                      headers={"X-Admin-Secret": SECRET},
                      files={"file": ("../../evil.png", png.getvalue(), "image/png")})
    check("с секретом — загружено", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
    url = r.json().get("icon_url", "") if r.status_code == 200 else ""
    check("имя файла задал сервер (нет ../)", url.startswith("/static/catalog/") and ".." not in url, url)
    if url:
        check("иконка раздаётся", requests.get(f"{API}{url}").status_code == 200)
    r = requests.get(f"{API}/equipment/catalog")
    t = next((t for t in r.json()["types"] if t["code"] == "vacuum_test"), {})
    check("иконка видна в каталоге", t.get("icon_url") == url, str(t))
    r = requests.post(f"{API}/equipment/internal/catalog/no_such_type/icon",
                      headers={"X-Admin-Secret": SECRET},
                      files={"file": ("x.png", png.getvalue(), "image/png")})
    check("несуществующий тип — 404", r.status_code == 404, f"{r.status_code}")
    r = requests.post(f"{API}/equipment/internal/catalog/vacuum_test/icon",
                      headers={"X-Admin-Secret": SECRET},
                      files={"file": ("x.php", b"<?php echo 1;", "text/plain")})
    check("не картинка — отказ", r.status_code == 400, f"{r.status_code}")
finally:
    row = sql("SELECT icon_url FROM equipment_catalog WHERE code = 'vacuum_test'")
    if row and row[0][0]:
        path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "media",
                            row[0][0].replace("/static/", "", 1))
        if os.path.exists(path):
            os.remove(path)
    sql("DELETE FROM equipment_catalog WHERE code = 'vacuum_test'")
    sql("UPDATE equipment_catalog SET is_enabled = true WHERE code = 'compressor'")

head("4. МАШИНЫ ДОСТАВКИ ИЗ БАЗЫ")

r = requests.get(f"{API}/materials/vehicles", headers=buyer)
vehicles = r.json()
caps = [v["capacity_kg"] for v in vehicles]
check("машины по возрастанию грузоподъёмности", caps == sorted(caps), str(caps))
check("есть ступени 1, 2, 3, 4, 5 т", {1000, 2000, 3000, 4000, 5000} <= set(caps), str(caps))
check("у машин есть названия", all(v.get("name") for v in vehicles), str(vehicles[:3]))
check("Damas и Gazel на месте", {"damas", "gazel"} <= {v["code"] for v in vehicles})

sql("UPDATE delivery_vehicles SET is_enabled = false WHERE code = 'bongo'")
try:
    codes = [v["code"] for v in requests.get(f"{API}/materials/vehicles", headers=buyer).json()]
    check("выключенная машина не показывается", "bongo" not in codes, str(codes))
finally:
    sql("UPDATE delivery_vehicles SET is_enabled = true WHERE code = 'bongo'")

head("5. ЦЕНА ДОСТАВКИ ОТ МАШИНЫ")

r = requests.post(f"{API}/materials/products", headers=seller, json={
    "material_type": "brick", "title": "Кирпич (тест каталога)", "price_per_unit": 1000,
    "min_quantity": 100, "available_quantity": 50000, "delivery_price_per_km": 4000,
    "address": "Тошкент", "latitude": 41.30, "longitude": 69.24,
})
pid = r.json()["id"]
requests.post(f"{API}/materials/products/{pid}/moderate", headers=admin, json={"approve": True})
saved = sql("SELECT base_fee, price_per_km FROM delivery_vehicles WHERE code = 'gazel'")[0]
try:
    def quote(qty, vehicle=None):
        body = {"product_id": pid, "quantity": qty, "delivery_latitude": 41.35, "delivery_longitude": 69.30}
        if vehicle:
            body["vehicle_code"] = vehicle
        return requests.post(f"{API}/materials/quote", headers=buyer, json=body).json()

    q = quote(500)  # 1 750 кг → Gazel (2 т)
    check("1 750 кг — Gazel, а не Isuzu 5 т", q["vehicle_code"] == "gazel", q["vehicle_code"])
    check("в расчёте есть название машины", q.get("vehicle_name") == "Gazel", str(q.get("vehicle_name")))
    km = float(q["delivery_distance_km"])
    check("без цены у машины — цена км продавца",
          abs(float(q["delivery_fee"]) - round(km * 4000)) <= 1, f"{q['delivery_fee']} km={km}")

    sql("UPDATE delivery_vehicles SET base_fee = 50000, price_per_km = 3000 WHERE code = 'gazel'")
    q = quote(500)
    check("цена из админки: подача + км × цена",
          abs(float(q["delivery_fee"]) - round(50000 + km * 3000)) <= 1, f"{q['delivery_fee']} km={km}")
    check("итог = товар + доставка",
          abs(float(q["total"]) - (float(q["goods_amount"]) + float(q["delivery_fee"]))) < 0.01)
    q3 = quote(1500, vehicle="gazel")  # 5 250 кг на Gazel — 3 рейса
    check("на малой машине — рейсы", q3["trips"] == 3, str(q3["trips"]))
    check("и доставка × рейсы",
          abs(float(q3["delivery_fee"]) - round((50000 + km * 3000) * 3)) <= 2, str(q3["delivery_fee"]))
finally:
    sql("UPDATE delivery_vehicles SET base_fee = :b, price_per_km = :k WHERE code = 'gazel'",
        b=saved[0], k=saved[1])

head("6. ВЫКЛЮЧЕНИЕ СТРОЙМАТЕРИАЛОВ")

sql("UPDATE app_settings SET value = to_jsonb('0'::text) WHERE key = 'materials_enabled'")
try:
    s = requests.get(f"{API}/settings/app-status").json()
    check("app-status: materials_enabled = false", s.get("materials_enabled") is False, str(s.get("materials_enabled")))
    r = requests.post(f"{API}/materials/orders", headers=buyer, json={"product_id": pid, "quantity": 500})
    check("заказ при выключенном разделе — 403", r.status_code == 403, f"{r.status_code} {r.text[:120]}")
finally:
    sql("UPDATE app_settings SET value = to_jsonb('1'::text) WHERE key = 'materials_enabled'")
s = requests.get(f"{API}/settings/app-status").json()
check("включили обратно — true", s.get("materials_enabled") is True)

requests.post(f"{API}/materials/products/{pid}/moderate", headers=admin,
              json={"approve": False, "comment": "тест каталога"})

print(f"\nИтого: {ok_count} OK, {fail_count} FAIL")
sys.exit(1 if fail_count else 0)
