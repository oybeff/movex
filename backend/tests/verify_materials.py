"""
Qurilish materiallari: katalog, moderatsiya, mashina tanlash va PUL.

Asosiy talab pul bilan bog'liq: summani faqat server sanaydi, buyurtma
berilganda muzlatiladi, yetkazilganda yechiladi, bekor qilinganda esa
FAQAT muzlatish olib tashlanadi. Bu ikkisini chalkashtirish — pul chop
etish demak.

Test IDEMPOTENT: har safar o'z tovarini yaratadi va oxirida yopadi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_materials.py
"""
import os
import sys

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _auth import token  # noqa: E402

API = "http://127.0.0.1:8000"

SELLER_PHONE = "998901110001"
BUYER_PHONE = "998901110002"
ADMIN_PHONE = "998900000000"
OTHER_PHONE = "998901179425"

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


seller = token(SELLER_PHONE)
buyer = token(BUYER_PHONE)
admin = token(ADMIN_PHONE)
other = token(OTHER_PHONE)


def balance_of(hdr):
    b = requests.get(f"{API}/balance/me", headers=hdr).json()
    return float(b["balance"]), float(b["frozen_balance"])


head("1. СПРАВОЧНИКИ")

r = requests.get(f"{API}/materials/types", headers=buyer)
check("справочник материалов отдаётся", r.status_code == 200, f"{r.status_code}")
types = r.json()
codes = [t["code"] for t in types]
check("кирпич, цемент и газоблок на месте",
      {"brick", "cement", "gas_block"}.issubset(set(codes)), str(codes))
brick = next(t for t in types if t["code"] == "brick")
check("у кирпича единица — штука", brick["default_unit"] == "piece", brick["default_unit"])

r = requests.get(f"{API}/materials/vehicles", headers=buyer)
vehicles = r.json()
check("машины отсортированы от малой к большой",
      [v["capacity_kg"] for v in vehicles] == sorted(v["capacity_kg"] for v in vehicles),
      str([v["capacity_kg"] for v in vehicles]))

head("2. ТОВАР ПРОХОДИТ МОДЕРАЦИЮ")

r = requests.post(f"{API}/materials/products", headers=seller, json={
    "material_type": "brick",
    "title": "Кирпич М-100 (тест)",
    "price_per_unit": 900,
    "min_quantity": 100,
    "available_quantity": 50000,
    "delivery_price_per_km": 4000,
    "address": "Тошкент, завод",
    "latitude": 41.30, "longitude": 69.24,
})
check("товар создан", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
product = r.json()
pid = product["id"]
check("новый товар СРАЗУ в модерации, а не в продаже",
      product["status"] == "pending", product["status"])
check("единица и вес подставлены из справочника",
      product["unit"] == "piece" and float(product["unit_weight_kg"]) == 3.5,
      f"{product['unit']} {product['unit_weight_kg']}")

r = requests.post(f"{API}/materials/products", headers=seller, json={
    "material_type": "kirpich_ruchnoy", "title": "Что-то", "price_per_unit": 100,
})
check("неизвестный вид материала отклонён", r.status_code == 400, f"{r.status_code}")

catalog = requests.get(f"{API}/materials/products", headers=buyer).json()
check("непроверенного товара в каталоге НЕТ",
      not any(p["id"] == pid for p in catalog), str([p["id"] for p in catalog]))

r = requests.post(f"{API}/materials/orders", headers=buyer,
                  json={"product_id": pid, "quantity": 1000})
check("купить непроверенный товар нельзя", r.status_code == 400, f"{r.status_code}")

r = requests.post(f"{API}/materials/products/{pid}/moderate", headers=seller,
                  json={"approve": True})
check("продавец не может одобрить свой товар сам", r.status_code == 403, f"{r.status_code}")

r = requests.post(f"{API}/materials/products/{pid}/moderate", headers=admin,
                  json={"approve": True})
check("админ одобрил", r.status_code == 200 and r.json()["status"] == "approved",
      f"{r.status_code} {r.text[:120]}")

catalog = requests.get(f"{API}/materials/products", headers=buyer).json()
check("одобренный товар появился в каталоге",
      any(p["id"] == pid for p in catalog))

head("3. ПОДБОР МАШИНЫ ПО ВЕСУ")


def quote(quantity, vehicle=None):
    body = {"product_id": pid, "quantity": quantity,
            "delivery_latitude": 41.35, "delivery_longitude": 69.30}
    if vehicle:
        body["vehicle_code"] = vehicle
    return requests.post(f"{API}/materials/quote", headers=buyer, json=body)


q = quote(200).json()
check("200 кирпичей = 700 кг", float(q["weight_kg"]) == 700, str(q["weight_kg"]))
check("под 700 кг подаётся самая малая машина", q["vehicle_code"] == "labo",
      q["vehicle_code"])
check("одним рейсом", q["trips"] == 1, str(q["trips"]))

q = quote(5000).json()
check("5 000 кирпичей = 17.5 тонн", float(q["weight_kg"]) == 17500, str(q["weight_kg"]))
check("под 17.5 тонн подаётся машина, которая увезёт за раз",
      q["vehicle_capacity_kg"] >= 17500 and q["trips"] == 1,
      f"{q['vehicle_code']} {q['vehicle_capacity_kg']} × {q['trips']}")

q_forced = quote(5000, vehicle="labo").json()
check("если юзер сам выбрал малую машину — считается несколько рейсов",
      q_forced["vehicle_code"] == "labo" and q_forced["trips"] == 25,
      f"{q_forced['vehicle_code']} × {q_forced['trips']}")
check("доставка растёт пропорционально рейсам",
      float(q_forced["delivery_fee"]) == float(q["delivery_fee"]) * 25 / q["trips"],
      f"{q_forced['delivery_fee']} vs {q['delivery_fee']}")

q_big = quote(30000).json()
check("если не влезает даже в самую большую — несколько рейсов",
      q_big["trips"] > 1, str(q_big["trips"]))

r = quote(10)
check("меньше минимальной партии — отказ", r.status_code == 400, f"{r.status_code}")

r = quote(99999)
check("больше остатка на складе — отказ", r.status_code == 400, f"{r.status_code}")

head("4. ЗАКАЗ: ДЕНЬГИ ЗАМОРАЖИВАЮТСЯ")

b0, f0 = balance_of(buyer)
s0, _ = balance_of(seller)

r = requests.post(f"{API}/materials/orders", headers=buyer, json={
    "product_id": pid, "quantity": 1000,
    "delivery_address": "Тошкент, qurilish",
    "delivery_latitude": 41.35, "delivery_longitude": 69.30,
})
check("заказ создан", r.status_code == 200, f"{r.status_code} {r.text[:200]}")
order = r.json()
oid = order["id"]

expected_goods = 900 * 1000
check("стоимость товара посчитана сервером",
      float(order["goods_amount"]) == expected_goods,
      f"{order['goods_amount']} vs {expected_goods}")
check("итог = товар + доставка, комиссия НЕ добавлена покупателю",
      float(order["total_amount"]) ==
      float(order["goods_amount"]) + float(order["delivery_fee"]),
      f"{order['total_amount']}")
check("комиссия записана и она с продавца", float(order["commission"]) > 0,
      str(order["commission"]))

b1, f1 = balance_of(buyer)
check("баланс покупателя НЕ уменьшился", b1 == b0, f"{money(b1)} vs {money(b0)}")
check("заморожена ровно сумма заказа",
      round(f1 - f0, 2) == float(order["total_amount"]),
      f"{money(f1 - f0)} vs {money(order['total_amount'])}")

r = requests.post(f"{API}/materials/orders", headers=seller,
                  json={"product_id": pid, "quantity": 1000})
check("свой товар купить нельзя", r.status_code == 400, f"{r.status_code}")

r = requests.get(f"{API}/materials/orders", headers=other).json()
check("чужой в списке заказов ничего не видит",
      not any(o["id"] == oid for o in r), str([o["id"] for o in r]))

head("5. ДОСТАВКА: ДЕНЬГИ ПЕРЕХОДЯТ")

r = requests.post(f"{API}/materials/orders/{oid}/deliver", headers=buyer)
check("неподтверждённый заказ доставленным не отметить", r.status_code == 400,
      f"{r.status_code}")

r = requests.post(f"{API}/materials/orders/{oid}/confirm", headers=buyer)
check("покупатель не может подтвердить заказ за продавца", r.status_code == 403,
      f"{r.status_code}")

r = requests.post(f"{API}/materials/orders/{oid}/confirm", headers=seller)
check("продавец подтвердил", r.status_code == 200 and r.json()["status"] == "confirmed",
      f"{r.status_code} {r.text[:120]}")

b_mid, f_mid = balance_of(buyer)
check("подтверждение продавца деньги НЕ двигает", b_mid == b1 and f_mid == f1,
      f"{money(b_mid)} / {money(f_mid)}")

r = requests.post(f"{API}/materials/orders/{oid}/deliver", headers=seller)
check("ПРОДАВЕЦ не может отметить доставку сам — иначе заберёт деньги не привезя",
      r.status_code == 403, f"{r.status_code} {r.text[:120]}")

r = requests.post(f"{API}/materials/orders/{oid}/deliver", headers=buyer)
check("покупатель подтвердил получение", r.status_code == 200,
      f"{r.status_code} {r.text[:150]}")

b2, f2 = balance_of(buyer)
s2, _ = balance_of(seller)
total = float(order["total_amount"])
commission = float(order["commission"])

check("с покупателя списана полная сумма, а не только снята заморозка",
      round(b0 - b2, 2) == total, f"списано {money(b0 - b2)}, ждали {money(total)}")
check("заморозка снята", round(f2, 2) == round(f0, 2),
      f"{money(f2)} vs {money(f0)}")
check("продавец получил сумму МИНУС комиссию",
      round(s2 - s0, 2) == round(total - commission, 2),
      f"получил {money(s2 - s0)}, ждали {money(total - commission)}")

r = requests.post(f"{API}/materials/orders/{oid}/deliver", headers=buyer)
check("повторная доставка отклонена", r.status_code == 400, f"{r.status_code}")

head("6. ОТМЕНА: ДЕНЬГИ ОСТАЮТСЯ У ПОКУПАТЕЛЯ")

b3, f3 = balance_of(buyer)
r = requests.post(f"{API}/materials/orders", headers=buyer, json={
    "product_id": pid, "quantity": 500,
    "delivery_latitude": 41.35, "delivery_longitude": 69.30,
})
second = r.json()
b4, f4 = balance_of(buyer)
check("вторая заявка заморозила деньги", round(f4 - f3, 2) == float(second["total_amount"]),
      f"{money(f4 - f3)}")

r = requests.post(f"{API}/materials/orders/{second['id']}/cancel", headers=buyer)
check("покупатель отменил", r.status_code == 200 and r.json()["status"] == "cancelled",
      f"{r.status_code} {r.text[:120]}")

b5, f5 = balance_of(buyer)
check("баланс после отмены не изменился", b5 == b3, f"{money(b5)} vs {money(b3)}")
check("заморозка снята полностью", round(f5, 2) == round(f3, 2),
      f"{money(f5)} vs {money(f3)}")

third = requests.post(f"{API}/materials/orders", headers=buyer, json={
    "product_id": pid, "quantity": 300,
    "delivery_latitude": 41.35, "delivery_longitude": 69.30,
}).json()
r = requests.post(f"{API}/materials/orders/{third['id']}/reject", headers=seller)
check("продавец может отклонить заказ", r.status_code == 200 and
      r.json()["status"] == "rejected", f"{r.status_code} {r.text[:120]}")
b6, f6 = balance_of(buyer)
check("после отказа продавца деньги тоже разморожены", round(f6, 2) == round(f3, 2),
      f"{money(f6)} vs {money(f3)}")

head("7. РЕДАКТИРОВАНИЕ СНОВА ВЕДЁТ НА МОДЕРАЦИЮ")

r = requests.put(f"{API}/materials/products/{pid}", headers=seller,
                 json={"price_per_unit": 1200})
check("товар отредактирован", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
check("после смены цены товар СНОВА в модерации",
      r.json()["status"] == "pending", r.json()["status"])

catalog = requests.get(f"{API}/materials/products", headers=buyer).json()
check("и снова пропал из каталога до проверки",
      not any(p["id"] == pid for p in catalog))

r = requests.put(f"{API}/materials/products/{pid}", headers=other,
                 json={"price_per_unit": 1})
check("чужой товар редактировать нельзя", r.status_code == 403, f"{r.status_code}")

r = requests.delete(f"{API}/materials/products/{pid}", headers=seller)
check("товар с заказами удалить нельзя — иначе история денег повиснет",
      r.status_code == 400, f"{r.status_code}")

# Тестовый товар убираем из продажи, чтобы не мешал в каталоге
requests.post(f"{API}/materials/products/{pid}/moderate", headers=admin,
              json={"approve": False, "comment": "тестовый товар"})

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
