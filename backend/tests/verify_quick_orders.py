"""
Tez buyurtma: mijoz narxni qo'yadi, birinchi bo'lib olgan ega oladi.

Tekshiriladi:
- yaratilganda narx DARHOL muzlatiladi; pul yetmasa zayavka yo'q;
- narx va boshlanish vaqtisiz tez buyurtma bo'lmaydi;
- egaga karta: narx, "sizga tushadi" (komissiya ayirilgan), mijozning
  ismi/telefoni YO'Q; mos turi yo'q egaga ko'rinmaydi;
- "Rad etish" — shu egadan yashiriladi, boshqasida qoladi;
- olish: buyurtma darhol 'confirmed', pul QAYTA muzlatilmaydi, vaqt o'tadi;
- kech qolgan ega — 409; bir vaqtda ikki ega — faqat bittasi oladi;
- tez buyurtmaga taklif yuborib bo'lmaydi;
- buyurtma yakunlanganda pul egaga o'tadi (komissiya ayirilib);
- bekor qilish va muddat tugashi muzlatishni qaytaradi.
"""
import os
import sys
import threading
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

API = "http://127.0.0.1:8000"
ok_count = fail_count = 0
created_ids, created_phones = [], []
TYPE = "concrete_pump"   # sinov turi — boshqa testlar bilan to'qnashmasin


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
                      json={"full_name": f"Sinov Tez {role}", "phone": phone, "role": role})
    body = r.json()
    created_ids.append(body["user_id"])
    created_phones.append(phone)
    time.sleep(0.01)
    # radius filtri xalaqit bermasin
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
        "type": etype, "model": "Sinov tez", "price_per_day": "500000",
        "latitude": "41.30", "longitude": "69.25", "status": "available", "available": True,
    })
    return r.json()["id"]


def quick(hdr, price=600000, start_time="09:00:00", **extra):
    start = date.today() + timedelta(days=3)
    body = {
        "equipment_type": TYPE, "start_date": str(start), "end_date": str(start + timedelta(days=2)),
        "delivery_latitude": 41.31, "delivery_longitude": 69.24,
        "delivery_address": "Chilonzor, Bunyodkor ko'ch. 21",
        "mode": "quick", "budget": price, "start_time": start_time,
    }
    body.update(extra)
    return requests.post(f"{API}/requests/", headers=hdr, json=body)


def incoming(hdr):
    return requests.get(f"{API}/requests/quick/incoming", headers=hdr).json()


def expected_receive(price):
    db = SessionLocal()
    try:
        c = pricing_service.calculate_commission(db, Decimal(price), Decimal(price))
    finally:
        db.close()
    return Decimal(price) - c, c


def main():
    client_id, client = register("client")
    owner_a_id, owner_a = register("owner")
    owner_b_id, owner_b = register("owner")
    owner_c_id, owner_c = register("owner")   # mos texnikasi yo'q
    add_equipment(owner_a)
    eq_b = add_equipment(owner_b)
    add_equipment(owner_c, "excavator")

    head("1. Narx va vaqtsiz tez buyurtma bo'lmaydi, pul yetmasa — yo'q")
    set_money(client_id, 1000000)
    r = quick(client, start_time=None)
    check("vaqtsiz — 400", r.status_code == 400, f"{r.status_code} {r.text}")
    r = quick(client, price=None)
    check("narxsiz — 400", r.status_code in (400, 422), f"{r.status_code} {r.text}")
    before = sql("SELECT count(*) FROM equipment_requests WHERE client_id=:u", u=client_id)[0][0]
    r = quick(client, price=5000000)
    check("pul yetmaydi — 400", r.status_code == 400, f"{r.status_code} {r.text}")
    after = sql("SELECT count(*) FROM equipment_requests WHERE client_id=:u", u=client_id)[0][0]
    check("zayavka yaratilmadi", before == after)
    check("hech narsa muzlatilmadi", money(client_id)[1] == 0, money(client_id))

    head("2. Yaratildi — narx darhol muzlatildi")
    r = quick(client, price=600000)
    check("yaratildi — 200", r.status_code == 200, f"{r.status_code} {r.text}")
    rid = r.json()["id"]
    check("rejim quick", r.json().get("mode") == "quick", r.json())
    check("mijoz balansida 600 000 muzlatildi", money(client_id)[1] == 600000, money(client_id))

    head("3. Egaga karta: narx, sizga tushadi, ismsiz/telefonsiz")
    cards = [c for c in incoming(owner_a) if c["id"] == rid]
    check("A egaga ko'rinadi", len(cards) == 1, incoming(owner_a))
    card = cards[0] if cards else {}
    receive, commission = expected_receive(600000)
    check("narx 600 000", Decimal(str(card.get("price"))) == 600000, card)
    check(f"sizga tushadi = narx - komissiya ({receive})",
          Decimal(str(card.get("you_receive"))) == receive, card)
    check("boshlanish vaqti bor", str(card.get("start_time", "")).startswith("09:00"), card)
    check("kunlar = 3", card.get("days") == 3, card)
    check("telefon va ism yo'q", "phone" not in str(card).lower() and "Sinov" not in str(card), card)
    check("bosh harflar bor", card.get("client_initials") == "ST", card)
    check("C egaga (boshqa turi) ko'rinmaydi", all(c["id"] != rid for c in incoming(owner_c)))

    head("4. Rad etish — faqat shu egadan yashiriladi")
    requests.post(f"{API}/requests/{rid}/quick-decline", headers=owner_a)
    check("A dan yashirindi", all(c["id"] != rid for c in incoming(owner_a)))
    check("B da qoldi", any(c["id"] == rid for c in incoming(owner_b)))

    head("5. Taklif yuborib bo'lmaydi")
    r = requests.post(f"{API}/requests/{rid}/offers", headers=owner_b,
                      json={"equipment_id": eq_b, "price_per_day": "100000"})
    check("taklif — 400", r.status_code == 400, f"{r.status_code} {r.text}")

    head("6. B oladi — buyurtma darhol tasdiqlangan, pul ikki marta muzlamaydi")
    r = requests.post(f"{API}/requests/{rid}/quick-accept", headers=owner_b, json={})
    check("oldi — 200", r.status_code == 200, f"{r.status_code} {r.text}")
    order_id = r.json().get("order_id")
    order = sql("SELECT status, total_amount, commission, frozen_amount, start_time, equipment_id "
                "FROM orders WHERE id=:o", o=order_id)[0]
    check("buyurtma 'confirmed'", order[0] == "confirmed", order)
    check("summa = narx", Decimal(str(order[1])) == 600000, order)
    check("komissiya qayd etildi", Decimal(str(order[2])) == commission, order)
    check("vaqt buyurtmaga o'tdi", str(order[4]).startswith("09:00"), order)
    check("B ning texnikasi", order[5] == eq_b, order)
    check("mijoz muzlatmasi o'sha 600 000 (ikki marta emas)", money(client_id)[1] == 600000, money(client_id))
    req = sql("SELECT status, frozen_amount, order_id FROM equipment_requests WHERE id=:r", r=rid)[0]
    check("zayavka 'assigned', muzlatma buyurtmaga o'tdi",
          req[0] == "assigned" and Decimal(str(req[1])) == 0 and req[2] == order_id, req)
    r = requests.get(f"{API}/orders/{order_id}", headers=owner_b)
    check("B buyurtmani ochadi", r.status_code == 200, r.status_code)

    head("7. Kech qolgan ega — 409")
    r = requests.post(f"{API}/requests/{rid}/quick-accept", headers=owner_a, json={})
    check("A — 409", r.status_code == 409, f"{r.status_code} {r.text}")

    head("8. Yakunlanganda pul egaga o'tadi")
    owner_bal0 = money(owner_b_id)[0]
    r = requests.put(f"{API}/orders/{order_id}", headers=client, json={"status": "completed"})
    check("yakunlandi — 200", r.status_code == 200, f"{r.status_code} {r.text}")
    c_bal, c_frozen = money(client_id)
    check("mijozdan 600 000 yechildi, muzlatma 0", c_bal == 400000 and c_frozen == 0, (c_bal, c_frozen))
    check(f"egaga {receive} tushdi", money(owner_b_id)[0] - owner_bal0 == receive,
          (owner_bal0, money(owner_b_id)[0]))

    head("9. Bekor qilish muzlatmani qaytaradi")
    r = quick(client, price=100000)
    rid2 = r.json()["id"]
    check("100 000 muzlatildi", money(client_id)[1] == 100000, money(client_id))
    r = requests.post(f"{API}/requests/{rid2}/cancel", headers=client)
    check("bekor — 200", r.status_code == 200, f"{r.status_code} {r.text}")
    check("muzlatma qaytdi", money(client_id)[1] == 0, money(client_id))

    head("10. Muddat tugashi muzlatmani qaytaradi")
    r = quick(client, price=100000)
    rid3 = r.json()["id"]
    sql("UPDATE equipment_requests SET expires_at = now() - interval '1 minute' WHERE id=:r", r=rid3)
    incoming(owner_b)   # ro'yxat so'ralganda eskirganlar yopiladi
    st = sql("SELECT status, frozen_amount FROM equipment_requests WHERE id=:r", r=rid3)[0]
    check("zayavka 'expired'", st[0] == "expired", st)
    check("muzlatma qaytdi", money(client_id)[1] == 0, money(client_id))

    head("11. Bir vaqtda ikki ega — faqat bittasi oladi")
    r = quick(client, price=100000)
    rid4 = r.json()["id"]
    results = []

    def grab(hdr):
        results.append(requests.post(f"{API}/requests/{rid4}/quick-accept", headers=hdr, json={}).status_code)

    sql("DELETE FROM quick_request_declines WHERE request_id=:r", r=rid4)
    threads = [threading.Thread(target=grab, args=(h,)) for h in (owner_a, owner_b)]
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    check("bittasi 200, bittasi 409", sorted(results) == [200, 409], results)
    orders = sql("SELECT count(*) FROM orders WHERE user_id=:u AND total_amount=100000", u=client_id)[0][0]
    check("faqat bitta buyurtma", orders == 1, orders)


def cleanup():
    db = SessionLocal()
    try:
        db.execute(text("DELETE FROM orders WHERE user_id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM otp_verifications WHERE phone = ANY(:ps)"), {"ps": created_phones})
        db.commit()
    finally:
        db.close()


if __name__ == "__main__":
    try:
        main()
    finally:
        cleanup()
    print(f"\nNATIJA: {ok_count} OK, {fail_count} FAIL")
    sys.exit(1 if fail_count else 0)
