"""
Diagnostika — narxi qat'iy tez buyurtma, va adminkadan naqd pul.

Tekshiriladi:
- narx serverdan (GET /requests/diagnostika), adminkadagi sozlama ishlaydi;
- mijoz yuborgan narx va rejim E'TIBORGA OLINMAYDI: budget = 50 000,
  mode = quick, bir kunlik;
- yaratilganda 50 000 muzlatiladi; pul yetmasa — 400 va zayavka yo'q;
- turi mos kelmasa ham texnikasi bor egaga ko'rinadi, texnikasiz egaga — yo'q;
  egaga xabarnoma "Diagnostikaga borish";
- ega oladi: buyurtma 'confirmed', komissiya 5 000;
- yakunlanganda: mijozdan 50 000, egaga 45 000, platformaga 5 000;
- bekor qilish muzlatmani qaytaradi;
- diagnostika katalog turlari ro'yxatiga tushmaydi;
- naqd pul (POST /balance/internal/cash_topup): kalitsiz 403/404, haqiqiy
  balansga tushadi (bonus_balance ga emas), kartaga yechish mumkin,
  ikki marta bosish — 409.

Test komissiya sozlamasini (fixed 5 000) va diagnostika narxini vaqtincha
o'rnatadi, oxirida qaytaradi; yaratgan hisoblarini o'chiradi.
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

from app.core.config import settings  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402

API = __import__("os").environ.get("API", "http://127.0.0.1:8000")
SECRET = {"X-Admin-Secret": settings.ADMIN_INTERNAL_SECRET}
CARD = "8600533364098829"
SETTING_KEYS = ("commission_mode", "commission_fixed", "diagnostika_price_amount")

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


def set_setting(key, value):
    if value is None:
        sql("DELETE FROM app_settings WHERE key=:k", k=key)
    elif sql("SELECT 1 FROM app_settings WHERE key=:k", k=key):
        sql("UPDATE app_settings SET value=to_jsonb(CAST(:v AS text)) WHERE key=:k", k=key, v=str(value))
    else:
        sql("INSERT INTO app_settings (key, value) VALUES (:k, to_jsonb(CAST(:v AS text)))",
            k=key, v=str(value))


def register(role):
    phone = f"9989{int(time.time() * 1000) % 100000000:08d}"[:12]
    requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": otp_code(phone)})
    r = requests.post(f"{API}/auth/register",
                      json={"full_name": f"Sinov Diag {role}", "phone": phone, "role": role})
    body = r.json()
    created_ids.append(body["user_id"])
    created_phones.append(phone)
    time.sleep(0.01)
    # radius filtri xalaqit bermasin
    sql("UPDATE users SET search_latitude=NULL, search_longitude=NULL WHERE id=:u", u=body["user_id"])
    return body["user_id"], {"Authorization": f"Bearer {body['access_token']}"}


def money(uid):
    row = sql("SELECT balance, frozen_balance, bonus_balance FROM balances WHERE user_id=:u", u=uid)
    if not row:
        return Decimal(0), Decimal(0), Decimal(0)
    return tuple(Decimal(str(v)) for v in row[0])


def set_money(uid, balance, frozen=0):
    if sql("SELECT 1 FROM balances WHERE user_id=:u", u=uid):
        sql("UPDATE balances SET balance=:b, frozen_balance=:f, bonus_balance=0 WHERE user_id=:u",
            b=balance, f=frozen, u=uid)
    else:
        sql("INSERT INTO balances (user_id, balance, frozen_balance, bonus_balance) "
            "VALUES (:u, :b, :f, 0)", b=balance, f=frozen, u=uid)


def add_equipment(hdr, etype="excavator"):
    r = requests.post(f"{API}/equipment/", headers=hdr, json={
        "type": etype, "model": "Sinov diag", "price_per_day": "500000",
        "latitude": "41.30", "longitude": "69.25", "status": "available", "available": True,
    })
    return r.json()["id"]


START = date.today() + timedelta(days=2)


def diag(hdr, **extra):
    body = {
        "equipment_type": "diagnostika",
        "start_date": str(START), "end_date": str(START + timedelta(days=5)),
        "delivery_latitude": 41.31, "delivery_longitude": 69.24,
        "delivery_address": "Yunusobod, 4-kvartal",
        "mode": "tender", "budget": 1000, "start_time": "10:30:00",
    }
    body.update(extra)
    return requests.post(f"{API}/requests/", headers=hdr, json=body)


def incoming(hdr):
    return requests.get(f"{API}/requests/quick/incoming", headers=hdr).json()


def main():
    client_id, client = register("client")
    owner_a_id, owner_a = register("owner")   # ekskavator egasi
    owner_b_id, owner_b = register("owner")   # texnikasiz
    eq_a = add_equipment(owner_a, "excavator")

    head("1. Narx serverdan")
    set_setting("diagnostika_price_amount", None)
    r = requests.get(f"{API}/requests/diagnostika", headers=client)
    check("GET /requests/diagnostika — 200", r.status_code == 200, f"{r.status_code} {r.text}")
    check("standart narx 50 000", Decimal(str(r.json().get("price"))) == 50000, r.text)
    set_setting("diagnostika_price_amount", 70000)
    r = requests.get(f"{API}/requests/diagnostika", headers=client)
    check("adminkadagi narx (70 000) qo'llanadi", Decimal(str(r.json().get("price"))) == 70000, r.text)
    set_setting("diagnostika_price_amount", 50000)
    r = requests.get(f"{API}/requests/diagnostika")
    check("tokensiz — 401/403", r.status_code in (401, 403), r.status_code)
    types = requests.get(f"{API}/equipment/types").text
    check("katalog turlari ro'yxatida diagnostika yo'q", "diagnostika" not in types, types[:200])

    head("2. Pul yetmasa — 400, zayavka yo'q")
    set_money(client_id, 40000)
    before = sql("SELECT count(*) FROM equipment_requests WHERE client_id=:u", u=client_id)[0][0]
    r = diag(client)
    check("pul yetmaydi — 400", r.status_code == 400, f"{r.status_code} {r.text}")
    after = sql("SELECT count(*) FROM equipment_requests WHERE client_id=:u", u=client_id)[0][0]
    check("zayavka yaratilmadi", before == after)
    check("hech narsa muzlatilmadi", money(client_id)[1] == 0, money(client_id))

    head("3. Mijoz yuborgan narx va rejim e'tiborga olinmaydi")
    set_money(client_id, 200000)
    r = diag(client, budget=1000, mode="tender")
    check("yaratildi — 200", r.status_code == 200, f"{r.status_code} {r.text}")
    body = r.json()
    rid = body.get("id")
    check("rejim quick (tender yuborilgan bo'lsa ham)", body.get("mode") == "quick", body)
    check("narx 50 000 (1 000 yuborilgan)", Decimal(str(body.get("budget"))) == 50000, body)
    check("muzlatma 50 000", Decimal(str(body.get("frozen_amount"))) == 50000, body)
    check("bir kunlik: end_date = start_date", body.get("end_date") == str(START), body)
    check("mijoz balansida 50 000 muzlatildi", money(client_id)[1] == 50000, money(client_id))
    r = diag(client, start_time=None)
    check("vaqtsiz — 400", r.status_code == 400, f"{r.status_code} {r.text}")

    head("4. Kim ko'radi")
    cards = [c for c in incoming(owner_a) if c["id"] == rid]
    check("ekskavator egasiga ko'rinadi (tur mos emas)", len(cards) == 1, incoming(owner_a))
    card = cards[0] if cards else {}
    check("kartada narx 50 000", Decimal(str(card.get("price"))) == 50000, card)
    check("sizga tushadi 45 000", Decimal(str(card.get("you_receive"))) == 45000, card)
    check("kartada tur 'diagnostika'", card.get("equipment_type") == "diagnostika", card)
    check("texnikasiz egaga ko'rinmaydi", all(c["id"] != rid for c in incoming(owner_b)))
    feed = requests.get(f"{API}/requests/feed", headers=owner_a).json()
    check("ega lentasida ham bor", any(x["id"] == rid for x in feed), feed)
    notes = sql("SELECT type, title FROM notifications WHERE user_id=:u ORDER BY id DESC", u=owner_a_id)
    diag_notes = [n for n in notes if n[0] == "quick_request" and "Diagnostika" in (n[1] or "")]
    check("egaga xabarnoma 'Diagnostikaga borish'", len(diag_notes) >= 1, notes)
    check("texnikasiz egaga xabarnoma yo'q",
          not sql("SELECT 1 FROM notifications WHERE user_id=:u AND type='quick_request'", u=owner_b_id))
    r = requests.post(f"{API}/requests/{rid}/offers", headers=owner_a,
                      json={"equipment_id": eq_a, "price_per_day": "100000"})
    check("taklif yuborib bo'lmaydi — 400", r.status_code == 400, f"{r.status_code} {r.text}")
    r = requests.post(f"{API}/requests/{rid}/quick-accept", headers=owner_b, json={})
    check("texnikasiz ega ola olmaydi — 400", r.status_code == 400, f"{r.status_code} {r.text}")

    head("5. Ega oladi — buyurtma tasdiqlangan")
    r = requests.post(f"{API}/requests/{rid}/quick-accept", headers=owner_a, json={})
    check("oldi — 200", r.status_code == 200, f"{r.status_code} {r.text}")
    order_id = r.json().get("order_id")
    order = sql("SELECT status, total_amount, commission, equipment_id, start_time, start_date, end_date "
                "FROM orders WHERE id=:o", o=order_id)[0]
    check("buyurtma 'confirmed'", order[0] == "confirmed", order)
    check("summa 50 000", Decimal(str(order[1])) == 50000, order)
    check("komissiya 5 000", Decimal(str(order[2])) == 5000, order)
    check("egasining mashinasiga bog'landi", order[3] == eq_a, order)
    check("vaqt o'tdi", str(order[4]).startswith("10:30"), order)
    check("muzlatma ikki marta emas", money(client_id)[1] == 50000, money(client_id))
    r = requests.post(f"{API}/requests/{rid}/quick-accept", headers=owner_a, json={})
    check("qayta olish — 409", r.status_code == 409, f"{r.status_code} {r.text}")

    head("6. Yakunlanganda: mijozdan 50 000, egaga 45 000, platformaga 5 000")
    owner_bal0 = money(owner_a_id)[0]
    r = requests.put(f"{API}/orders/{order_id}", headers=client, json={"status": "completed"})
    check("yakunlandi — 200", r.status_code == 200, f"{r.status_code} {r.text}")
    c_bal, c_frozen, _ = money(client_id)
    check("mijozdan 50 000 yechildi, muzlatma 0", c_bal == 150000 and c_frozen == 0, (c_bal, c_frozen))
    check("egaga 45 000 tushdi", money(owner_a_id)[0] - owner_bal0 == 45000,
          (owner_bal0, money(owner_a_id)[0]))
    reserve = sql("SELECT COALESCE(SUM(amount),0) FROM budget_reserves WHERE order_id=:o", o=order_id)[0][0]
    check("platformaga 5 000 (budget_reserves)", Decimal(str(reserve)) == 5000, reserve)

    head("7. Bekor qilish muzlatmani qaytaradi")
    r = diag(client)
    rid2 = r.json()["id"]
    check("50 000 muzlatildi", money(client_id)[1] == 50000, money(client_id))
    r = requests.post(f"{API}/requests/{rid2}/cancel", headers=client)
    check("bekor — 200", r.status_code == 200, f"{r.status_code} {r.text}")
    check("muzlatma qaytdi", money(client_id)[1] == 0, money(client_id))
    check("balans tegilmadi", money(client_id)[0] == 150000, money(client_id))

    head("8. Naqd pul: kalitsiz ishlamaydi")
    r = requests.post(f"{API}/balance/internal/cash_topup", json={"user_id": client_id, "amount": 50000})
    check("kalitsiz — 403/404", r.status_code in (403, 404), r.status_code)
    r = requests.post(f"{API}/balance/internal/cash_topup", headers={"X-Admin-Secret": "xato"},
                      json={"user_id": client_id, "amount": 50000})
    check("noto'g'ri kalit — 403", r.status_code == 403, r.status_code)
    check("balans o'zgarmadi", money(client_id)[0] == 150000, money(client_id))

    head("9. Naqd pul haqiqiy balansga tushadi, kartaga yechish mumkin")
    set_money(owner_a_id, 0)
    r = requests.post(f"{API}/balance/internal/cash_topup", headers=SECRET,
                      json={"user_id": owner_a_id, "amount": 100000, "comment": "diagnostika"})
    check("yozildi — 200", r.status_code == 200, f"{r.status_code} {r.text}")
    bal, frozen, bonus = money(owner_a_id)
    check("balans 100 000", bal == 100000, (bal, frozen, bonus))
    check("bonus_balance ga tushmadi", bonus == 0, bonus)
    tx = sql("SELECT type, payment_method, status, description FROM balance_transactions "
             "WHERE user_id=:u ORDER BY id DESC LIMIT 1", u=owner_a_id)[0]
    check("tranzaksiya topup / cash / completed",
          tx[0] == "topup" and tx[1] == "cash" and tx[2] == "completed", tx)
    check("izohda kod emas, matn", "diagnostika" in (tx[3] or "") and "tx." not in (tx[3] or ""), tx)
    r = requests.post(f"{API}/balance/internal/cash_topup", headers=SECRET,
                      json={"user_id": owner_a_id, "amount": 100000})
    check("ikki marta bosildi — 409", r.status_code == 409, f"{r.status_code} {r.text}")
    check("ikkinchi marta tushmadi", money(owner_a_id)[0] == 100000, money(owner_a_id))
    r = requests.post(f"{API}/balance/internal/cash_topup", headers=SECRET,
                      json={"user_id": owner_a_id, "amount": 0})
    check("0 summa — 400", r.status_code == 400, f"{r.status_code} {r.text}")
    r = requests.post(f"{API}/payouts/", headers=owner_a,
                      json={"amount": 100000, "card_number": CARD, "card_holder": "SINOV"})
    check("naqd pulni to'liq yechish arizasi qabul qilindi", r.status_code == 200,
          f"{r.status_code} {r.text[:200]}")
    check("ariza summasi muzlatildi", money(owner_a_id)[1] == 100000, money(owner_a_id))

    head("10. Sovg'a bilan solishtirish: sovg'ani yechib bo'lmaydi")
    set_money(owner_b_id, 0)
    requests.post(f"{API}/balance/internal/bonus", headers=SECRET,
                  json={"user_id": owner_b_id, "amount": 100000})
    r = requests.post(f"{API}/payouts/", headers=owner_b,
                      json={"amount": 100000, "card_number": CARD, "card_holder": "SINOV"})
    check("sovg'ani yechish — 400", r.status_code == 400, f"{r.status_code} {r.text[:200]}")


def cleanup():
    db = SessionLocal()
    try:
        db.execute(text("DELETE FROM payout_requests WHERE user_id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM orders WHERE user_id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM otp_verifications WHERE phone = ANY(:ps)"), {"ps": created_phones})
        db.commit()
    finally:
        db.close()


if __name__ == "__main__":
    saved = {k: sql("SELECT value::text FROM app_settings WHERE key=:k", k=k) for k in SETTING_KEYS}
    set_setting("commission_mode", "fixed")
    set_setting("commission_fixed", 5000)
    try:
        main()
    finally:
        cleanup()
        for key, row in saved.items():
            if row:
                sql("UPDATE app_settings SET value=CAST(:v AS json) WHERE key=:k", k=key, v=row[0][0])
            else:
                set_setting(key, None)
    print(f"\nNATIJA: {ok_count} OK, {fail_count} FAIL")
    sys.exit(1 if fail_count else 0)
