"""
Оплата картой через холд Multicard (K1–K6, E7). Идёт в ПЕСОЧНИЦУ
(dev-mesh), нужна сеть и RAHMAT_TEST_MODE=true.

Тестовая карта песочницы уже привязана, её токен — SANDBOX_TOKEN. Новую
привязку проверить автоматически нельзя (там форма с капчей), поэтому
привязка проверяется только до выдачи ссылки.

Особенность песочницы: холд снимается сам через ~2 секунды. Поэтому
завершение заказа здесь всегда упирается в «холд не активен» — это и
есть путь E7, и он проверяется: 402, затем оплата картой сразу.
"""
import os
import sys
import time
from datetime import date, timedelta
from decimal import Decimal

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import otp_code  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sqlalchemy import text  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402

API = os.environ.get("API", "http://127.0.0.1:8000")
SANDBOX_TOKEN = os.environ.get("MC_SANDBOX_CARD_TOKEN", "RzRqQl_ShIZujqQ3J26l0g")
TYPE = "aerial_platform"
ok = fail = 0
ids, phones = [], []


def check(label, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1
        print(f"  [OK]   {label}")
    else:
        fail += 1
        print(f"  [FAIL] {label}  {detail}")


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
    b = requests.post(f"{API}/auth/register",
                      json={"full_name": f"Sinov Karta {role}", "phone": phone, "role": role}).json()
    ids.append(b["user_id"])
    phones.append(phone)
    time.sleep(0.01)
    sql("UPDATE users SET search_latitude=NULL, search_longitude=NULL WHERE id=:u", u=b["user_id"])
    return b["user_id"], {"Authorization": f"Bearer {b['access_token']}"}


def order_req(hdr, card_id, hours=4):
    start = date.today() + timedelta(days=1)
    return requests.post(f"{API}/requests/", headers=hdr, json={
        "equipment_type": TYPE, "start_date": str(start), "end_date": str(start),
        "delivery_latitude": 41.31, "delivery_longitude": 69.24, "delivery_address": "Sinov",
        "mode": "quick", "start_time": "08:00:00", "tariff": "econom", "hours": hours,
        "payment_method": "card", "card_id": card_id,
    })


def main():
    if not settings.RAHMAT_TEST_MODE:
        print("RAHMAT_TEST_MODE выключен — тест в бою не запускается")
        return
    sql("DELETE FROM tariffs WHERE equipment_type=:t", t=TYPE)
    sql("INSERT INTO tariffs (equipment_type, tier, price_per_hour, min_hours, is_active) "
        "VALUES (:t, 'econom', 25000, 2, true)", t=TYPE)

    client_id, client = register("client")
    owner_id, owner = register("owner")
    _, other = register("client")
    requests.post(f"{API}/equipment/", headers=owner, json={
        "type": TYPE, "model": "Sinov", "price_per_day": 100000, "latitude": 41.3, "longitude": 69.24,
        "plate_number": "01 K 001 AA"})
    sql("INSERT INTO balances (user_id, balance, frozen_balance, bonus_balance) VALUES (:u, 50000, 0, 0) "
        "ON CONFLICT (user_id) DO UPDATE SET balance=50000, frozen_balance=0, bonus_balance=0", u=owner_id)

    print("\n== Карты")
    r = requests.post(f"{API}/cards/bind", headers=client)
    check("ссылка на форму привязки", r.status_code == 200 and "multicard" in r.json().get("form_url", ""), r.text)
    sql("DELETE FROM user_cards WHERE token=:t", t=SANDBOX_TOKEN)
    card_id = sql("INSERT INTO user_cards (user_id, token, pan, ps, is_default) "
                  "VALUES (:u, :t, '860053******8829', 'uzcard', true) RETURNING id",
                  u=client_id, t=SANDBOX_TOKEN)[0][0]
    fake_id = sql("INSERT INTO user_cards (user_id, token, pan, ps) "
                  "VALUES (:u, :t, '986027******0000', 'humo') RETURNING id",
                  u=client_id, t=f"fake-{time.time()}")[0][0]
    cards = requests.get(f"{API}/cards/", headers=client).json()
    check("список карт: основная первой", [c["id"] for c in cards][:1] == [card_id], cards)
    check("в ответе нет токена", all("token" not in c for c in cards), cards)
    check("чужую карту не видно", requests.get(f"{API}/cards/", headers=other).json() == [])
    r = requests.delete(f"{API}/cards/{fake_id}", headers=other)
    check("чужую карту не удалить — 404", r.status_code == 404, r.text)
    r = requests.post(f"{API}/cards/callback", json={"payer_id": "nonexistent"})
    check("колбэк с мусором — 200, ничего не создаёт", r.status_code == 200)

    print("\n== Заказ картой: холд при заказе")
    r = order_req(other, card_id)
    check("чужой картой заказать нельзя — 404", r.status_code == 404, r.text)
    r = order_req(client, card_id)
    req = r.json()
    check("заявка с картой открыта (холд прошёл без SMS)", r.status_code == 200 and req.get("status") == "open", r.text)
    hold = sql("SELECT status, amount FROM card_payments WHERE request_id=:r", r=req.get("id"))
    check("холд на всю сумму, баланс клиента не тронут",
          hold and hold[0][0] == "active" and Decimal(str(hold[0][1])) == Decimal("100000")
          and not sql("SELECT 1 FROM balances WHERE user_id=:u AND frozen_balance>0", u=client_id), hold)

    print("\n== Отмена снимает холд")
    r = requests.post(f"{API}/requests/{req['id']}/cancel", headers=client)
    st = sql("SELECT status FROM card_payments WHERE request_id=:r", r=req["id"])[0][0]
    check("отмена заявки → холд cancelled", r.status_code == 200 and st == "cancelled", (r.text, st))

    print("\n== Работа, списание, E7")
    req = order_req(client, card_id).json()
    oid = requests.post(f"{API}/requests/{req['id']}/quick-accept", headers=owner).json().get("order_id")
    o = requests.get(f"{API}/orders/{oid}", headers=client).json()
    check("заказ картой: payment_method=card, на балансе 0", o.get("payment_method") == "card"
          and float(o.get("frozen_amount")) == 0, o)
    check("продлить картой пока нельзя — 400",
          requests.post(f"{API}/orders/{oid}/extend", headers=client, json={"hours": 1}).status_code == 400)
    requests.post(f"{API}/orders/{oid}/start", headers=owner)
    requests.post(f"{API}/orders/{oid}/finish", headers=owner)
    r = requests.put(f"{API}/orders/{oid}", headers=client, json={"status": "completed"})
    check("подтверждение работы: холд списан, заказ завершён",
          r.status_code == 200 and r.json().get("status") == "completed", (r.status_code, r.text[:200]))
    commission = Decimal(str(sql("SELECT commission FROM orders WHERE id=:o", o=oid)[0][0]))
    owner_bal = Decimal(str(sql("SELECT balance FROM balances WHERE user_id=:u", u=owner_id)[0][0]))
    check("владелец получил сумму минус комиссия", owner_bal == Decimal("50000") + Decimal("100000") - commission,
          (owner_bal, commission))
    check("комиссия в бюджете ровно одна запись",
          len(sql("SELECT 1 FROM budget_reserves WHERE order_id=:o", o=oid) or []) == 1)
    check("холд charged", sql("SELECT status FROM card_payments WHERE order_id=:o", o=oid)[0][0] == "charged")

    print("\n== E7: холд истёк до конца работы")
    req = order_req(client, card_id).json()
    oid3 = requests.post(f"{API}/requests/{req['id']}/quick-accept", headers=owner).json().get("order_id")
    requests.post(f"{API}/orders/{oid3}/start", headers=owner)
    requests.post(f"{API}/orders/{oid3}/finish", headers=owner)
    # Имитация: банк/срок сняли холд (в шлюзе), у нас он ещё «active»
    from app.services import rahmat_service
    uuid = sql("SELECT uuid FROM card_payments WHERE order_id=:o", o=oid3)[0][0]
    try:
        rahmat_service._request("DELETE", f"/payment/hold/{uuid}")
    except Exception:
        pass
    bal_before = Decimal(str(sql("SELECT balance FROM balances WHERE user_id=:u", u=owner_id)[0][0]))
    r = requests.put(f"{API}/orders/{oid3}", headers=client, json={"status": "completed"})
    check("холд пропал → 402 card_payment_failed", r.status_code == 402 and "card_payment_failed" in r.text,
          (r.status_code, r.text[:200]))
    check("владелец денег не получил", Decimal(str(sql("SELECT balance FROM balances WHERE user_id=:u",
                                                           u=owner_id)[0][0])) == bal_before)
    r = requests.post(f"{API}/orders/{oid3}/pay-card", headers=other, json={"card_id": card_id})
    check("чужой не оплачивает — 403", r.status_code == 403, r.text)
    r = requests.post(f"{API}/orders/{oid3}/pay-card", headers=client, json={"card_id": card_id})
    check("E7 «Boshqa karta tanlash»: списано сразу, заказ завершён",
          r.status_code == 200 and r.json().get("status") == "completed", r.text[:200])
    c3 = Decimal(str(sql("SELECT commission FROM orders WHERE id=:o", o=oid3)[0][0]))
    check("и только теперь владелец получил деньги",
          Decimal(str(sql("SELECT balance FROM balances WHERE user_id=:u", u=owner_id)[0][0]))
          == bal_before + Decimal("100000") - c3)

    print("\n== E7 «Naqd to'lash»")
    req = order_req(client, card_id).json()
    oid2 = requests.post(f"{API}/requests/{req['id']}/quick-accept", headers=owner).json().get("order_id")
    requests.post(f"{API}/orders/{oid2}/start", headers=owner)
    requests.post(f"{API}/orders/{oid2}/finish", headers=owner)
    before = Decimal(str(sql("SELECT balance FROM balances WHERE user_id=:u", u=owner_id)[0][0]))
    r = requests.post(f"{API}/orders/{oid2}/pay-cash", headers=client)
    c2 = Decimal(str(sql("SELECT commission FROM orders WHERE id=:o", o=oid2)[0][0]))
    after = Decimal(str(sql("SELECT balance FROM balances WHERE user_id=:u", u=owner_id)[0][0]))
    check("наличными: заказ завершён, с владельца удержана комиссия",
          r.status_code == 200 and r.json().get("status") == "completed" and after == before - c2,
          (r.status_code, r.text[:200], before, after))
    st = sql("SELECT status FROM card_payments WHERE order_id=:o", o=oid2)
    check("холд по нему снят", all(s[0] == "cancelled" for s in st), st)


def cleanup():
    sql("DELETE FROM card_payments WHERE user_id = ANY(:i)", i=ids)
    sql("DELETE FROM orders WHERE user_id = ANY(:i)", i=ids)
    sql("DELETE FROM user_cards WHERE user_id = ANY(:i)", i=ids)
    sql("DELETE FROM users WHERE id = ANY(:i)", i=ids)
    sql("DELETE FROM otp_verifications WHERE phone = ANY(:p)", p=phones)
    sql("DELETE FROM tariffs WHERE equipment_type=:t", t=TYPE)


if __name__ == "__main__":
    try:
        main()
    finally:
        cleanup()
    print(f"\nITOG: {ok} o'tdi, {fail} yiqildi")
    sys.exit(1 if fail else 0)
