"""
Регрессия: ветки отказа и отмены должны возвращать деньги клиенту.
Их я не трогал, но правил соседнюю ветку завершения — проверяю, что цело.
"""
import re

import requests

API = "http://127.0.0.1:8000"
ok = fail = 0


def money(x):
    return f"{float(x):,.0f}".replace(",", " ")


def check(label, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1
        print(f"  [OK]   {label}")
    else:
        fail += 1
        print(f"  [FAIL] {label}  {detail}")


def token(phone):
    r = requests.post(f"{API}/auth/send-otp", json={"phone": phone})
    code = re.search(r"(\d{4})\s*$", r.json()["message"]).group(1)
    r = requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": code})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def bal(hdr):
    b = requests.get(f"{API}/balance/me", headers=hdr).json()
    return float(b["balance"]), float(b["frozen_balance"])


client, owner = token("998901110002"), token("998901110001")


def topup_via_click(hdr, amount, click_id):
    """Пополнение полным путём Click: заявка -> prepare -> complete."""
    import hashlib
    from datetime import datetime

    SERVICE_ID, SECRET = "111111", "local_dev_click_secret"
    tx = requests.post(f"{API}/balance/topup", headers=hdr,
                       json={"amount": amount, "payment_method": "click"}).json()
    tx_id, amt = tx["transaction_id"], float(tx["amount"])

    def cb(path, action, extra=None):
        st = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        raw = f"{click_id}{SERVICE_ID}{SECRET}{tx_id}{amt}{action}{st}"
        body = {"click_trans_id": click_id, "service_id": SERVICE_ID,
                "merchant_trans_id": tx_id, "amount": amt, "action": action,
                "error": 0, "error_note": "Success", "sign_time": st,
                "sign_string": hashlib.md5(raw.encode()).hexdigest()}
        if extra:
            body.update(extra)
        return requests.post(f"{API}/balance/{path}", data=body).json()

    prep = cb("click/prepare", 0)
    cb("click/complete", 1, {"merchant_prepare_id": prep.get("merchant_prepare_id", tx_id)})


topup_via_click(client, 10000000, 900100)
print(f"баланс клиента для тестов: {money(bal(client)[0])} сум")


def make_order(start, end):
    return requests.post(f"{API}/orders/", headers=client, json={
        "equipment_id": 1, "start_date": start, "end_date": end,
        "total_amount": 1, "commission": 1,
        "delivery_latitude": "41.31", "delivery_longitude": "69.28",
    }).json()


for label, new_status, actor in [
    ("ОТКАЗ владельца (pending -> rejected)", "rejected", owner),
    ("ОТМЕНА клиентом (pending -> cancelled)", "cancelled", client),
]:
    print(f"\n=== {label} ===")
    before, _ = bal(client)
    o = make_order("2027-05-01", "2027-05-03")
    total = float(o["total_amount"])
    _, frozen = bal(client)
    check("деньги заморожены при создании", frozen == total, f"заморожено {money(frozen)}")

    r = requests.put(f"{API}/orders/{o['id']}", headers=actor, json={"status": new_status})
    check(f"переход в {new_status} прошёл",
          r.status_code == 200 and r.json().get("status") == new_status, r.text[:120])

    after, frozen_after = bal(client)
    check("заморозка снята", frozen_after == 0, f"осталось {money(frozen_after)}")
    check("деньги вернулись клиенту в полном объёме", after == before,
          f"было {money(before)}, стало {money(after)}")

print("\n=== ОТМЕНА уже подтверждённого заказа (confirmed -> cancelled) ===")
before, _ = bal(client)
o = make_order("2027-06-01", "2027-06-03")
requests.put(f"{API}/orders/{o['id']}", headers=owner, json={"status": "confirmed"})
r = requests.put(f"{API}/orders/{o['id']}", headers=client, json={"status": "cancelled"})
check("отмена подтверждённого заказа прошла",
      r.status_code == 200 and r.json().get("status") == "cancelled", r.text[:120])
after, frozen_after = bal(client)
check("заморозка снята", frozen_after == 0)
check("деньги вернулись клиенту", after == before,
      f"было {money(before)}, стало {money(after)}")

print(f"\n{'=' * 60}\nИТОГ: {ok} пройдено, {fail} провалено\n{'=' * 60}")
