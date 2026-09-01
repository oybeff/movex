"""
Xabarnomalarni tekshirish.

Asosiy talab: xabarnoma to'g'ri odamga borsin va begonasi ko'rinmasin.
Ikkinchisi: xabarnoma yaratishdagi xato buyurtmani buzmasin.

Test IDEMPOTENT — bazani tozalamasdan qayta ishga tushirsa bo'ladi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_notifications.py
"""
import hashlib
import random
import re
from datetime import datetime, timedelta

import requests

API = "http://127.0.0.1:8000"

OWNER_PHONE = "998901110001"
CLIENT_PHONE = "998901110002"
EQUIPMENT_ID = 1

CLICK_SERVICE_ID = "111111"
CLICK_SECRET_KEY = "local_dev_click_secret"

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
    print(f"\n{'=' * 66}\n{t}\n{'=' * 66}")


def token(phone):
    r = requests.post(f"{API}/auth/send-otp", json={"phone": phone})
    code = re.search(r"(\d{4})\s*$", r.json()["message"]).group(1)
    r = requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": code})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def notifications(hdr, **params):
    return requests.get(f"{API}/notifications/", headers=hdr, params=params).json()


def topup_via_click(hdr, amount, click_id):
    tx = requests.post(f"{API}/balance/topup", headers=hdr,
                       json={"amount": amount, "payment_method": "click"}).json()
    tx_id, amt = tx["transaction_id"], float(tx["amount"])

    def cb(path, action, extra=None):
        st = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        raw = f"{click_id}{CLICK_SERVICE_ID}{CLICK_SECRET_KEY}{tx_id}{amt}{action}{st}"
        body = {"click_trans_id": click_id, "service_id": CLICK_SERVICE_ID,
                "merchant_trans_id": tx_id, "amount": amt, "action": action,
                "error": 0, "error_note": "Success", "sign_time": st,
                "sign_string": hashlib.md5(raw.encode()).hexdigest()}
        if extra:
            body.update(extra)
        return requests.post(f"{API}/balance/{path}", data=body).json()

    prep = cb("click/prepare", 0)
    cb("click/complete", 1, {"merchant_prepare_id": prep.get("merchant_prepare_id", tx_id)})


def free_dates(days=1, equipment_id=None, headers=None):
    """
    Band bo'lmagan sanalar.

    Ilgari sana joriy vaqtdan tasodifiy siljish bilan olinardi. Testlar ko'p
    marta ishlagach bazada yuzlab buyurtma to'planadi va siljish oralig'i
    to'lib qoladi — "bu sanada texnika band" xatosi chiqadi. Bu mahsulot
    xatosi emas, test o'zini o'zi bloklaydi.

    Endi oraliq ancha keng va tasodifiy; band bo'lsa boshqa sana olinadi.
    """
    for _ in range(25):
        offset = random.randint(500, 30000)
        start = datetime.now() + timedelta(days=offset)
        s = start.strftime("%Y-%m-%d")
        e = (start + timedelta(days=days)).strftime("%Y-%m-%d")
        if equipment_id is None or headers is None:
            return s, e
        busy = requests.get(
            f"{API}/orders/", headers=headers, params={"limit": 100}
        ).json()
        clash = any(
            o.get("equipment_id") == equipment_id
            and o.get("status") in ("pending", "confirmed")
            and o.get("start_date", "") <= e
            and o.get("end_date", "") >= s
            for o in (busy if isinstance(busy, list) else [])
        )
        if not clash:
            return s, e
    return s, e


client = token(CLIENT_PHONE)
owner = token(OWNER_PHONE)

topup_via_click(client, 10_000_000, 970000 + int(datetime.now().timestamp()) % 10000)

def newest_id(hdr):
    """
    Сравниваем по id самого свежего, а не по длине списка: список отдаётся
    с лимитом, и на накопленных данных длина перестаёт расти.
    """
    items = notifications(hdr, limit=1)
    return items[0]["id"] if items else 0


owner_before = newest_id(owner)
client_before = newest_id(client)
print(f"последнее уведомление: у владельца #{owner_before}, у клиента #{client_before}")

head("1. НОВЫЙ ЗАКАЗ → УВЕДОМЛЕНИЕ ВЛАДЕЛЬЦУ")

start, end = free_dates()
order = requests.post(f"{API}/orders/", headers=client, json={
    "equipment_id": EQUIPMENT_ID, "start_date": start, "end_date": end,
    "total_amount": 1, "commission": 1,
    "delivery_latitude": "41.31", "delivery_longitude": "69.28",
}).json()
check("заказ создан", "id" in order, str(order)[:200])

owner_notifs = notifications(owner)
check("владельцу пришло новое уведомление", newest_id(owner) > owner_before,
      f"было #{owner_before}, стало #{newest_id(owner)}")

newest = owner_notifs[0] if owner_notifs else {}
check("тип order_created", newest.get("type") == "order_created", str(newest.get("type")))
check("в уведомлении есть код типа техники для иконки",
      newest.get("equipment_type") == "excavator", str(newest.get("equipment_type")))
check("привязано к заказу", newest.get("order_id") == order.get("id"), str(newest.get("order_id")))
check("создано непрочитанным", newest.get("is_read") is False, str(newest.get("is_read")))

check("клиенту уведомление о своём же заказе не пришло",
      newest_id(client) == client_before,
      f"было #{client_before}, стало #{newest_id(client)}")

head("2. ПОДТВЕРЖДЕНИЕ И ЗАВЕРШЕНИЕ")

requests.put(f"{API}/orders/{order['id']}", headers=owner, json={"status": "confirmed"})
client_notifs = notifications(client)
check("клиенту пришло о подтверждении", newest_id(client) > client_before,
      f"было #{client_before}, стало #{newest_id(client)}")
check("тип order_confirmed", client_notifs[0].get("type") == "order_confirmed",
      str(client_notifs[0].get("type")))

requests.put(f"{API}/orders/{order['id']}", headers=owner, json={"status": "completed"})
check("о завершении уведомлены обе стороны",
      notifications(client)[0].get("type") == "order_completed"
      and notifications(owner)[0].get("type") == "order_completed",
      f"клиент {notifications(client)[0].get('type')}, владелец {notifications(owner)[0].get('type')}")

head("3. СЧЁТЧИК НЕПРОЧИТАННЫХ И ОТМЕТКА О ПРОЧТЕНИИ")

unread = requests.get(f"{API}/notifications/unread-count", headers=owner).json()
check("счётчик непрочитанных больше нуля", unread.get("unread", 0) > 0, str(unread))

nid = notifications(owner)[0]["id"]
r = requests.post(f"{API}/notifications/{nid}/read", headers=owner)
check("уведомление отмечено прочитанным",
      r.status_code == 200 and r.json().get("is_read") is True, r.text[:120])

r = requests.post(f"{API}/notifications/{nid}/read", headers=client)
check("чужое уведомление отметить нельзя", r.status_code == 404, f"{r.status_code}")

only_unread = notifications(owner, only_unread=True)
check("прочитанное ушло из списка непрочитанных",
      all(n["id"] != nid for n in only_unread))

requests.post(f"{API}/notifications/read-all", headers=owner)
after = requests.get(f"{API}/notifications/unread-count", headers=owner).json()
check("после read-all непрочитанных нет", after.get("unread") == 0, str(after))

head("4. УДАЛЕНИЕ")

r = requests.delete(f"{API}/notifications/{nid}", headers=client)
check("чужое уведомление удалить нельзя", r.status_code == 404, f"{r.status_code}")

r = requests.delete(f"{API}/notifications/{nid}", headers=owner)
check("своё удаляется", r.status_code == 200, f"{r.status_code}")
check("и правда исчезло", all(n["id"] != nid for n in notifications(owner)))

head("5. ТОКЕН УСТРОЙСТВА ДЛЯ PUSH")

device_token = f"test-token-{int(datetime.now().timestamp())}"
r = requests.post(f"{API}/notifications/devices", headers=client,
                  json={"token": device_token, "platform": "android"})
check("токен устройства зарегистрирован", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
check("сам токен обратно не отдаётся", device_token not in r.text, "токен утёк в ответе")

r = requests.post(f"{API}/notifications/devices", headers=client,
                  json={"token": device_token, "platform": "android"})
check("повторная регистрация того же токена не ломается", r.status_code == 200, f"{r.status_code}")

r = requests.post(f"{API}/notifications/devices", headers=client,
                  json={"token": device_token, "platform": "symbian"})
check("неизвестная платформа отклонена", r.status_code == 422, f"{r.status_code}")

r = requests.request("DELETE", f"{API}/notifications/devices", headers=client,
                     json={"token": device_token})
check("токен снимается при выходе", r.status_code == 200, f"{r.status_code}")

head("6. НАЗВАНИЕ ТЕХНИКИ, А НЕ КОД")

# QA нашёл в ленте "Yangi buyurtma: backhoe_loader JCB 3CX" — пользователю
# показывался служебный код. Название техники теперь собирает приложение
# из equipment_type + equipment_model, поэтому оба поля обязаны приходить.

# Коды берём из самого API — так тест не зависит от того, откуда запущен
TYPE_CODES = [t["code"] for t in
              requests.get(f"{API}/equipment/types", headers=owner).json()]

items = notifications(owner)
check("лента владельца не пуста", len(items) > 0, "нет уведомлений для проверки")

with_type = [n for n in items if n.get("equipment_type")]
check("в уведомлениях есть тип техники", len(with_type) > 0, "ни одного equipment_type")

check(
    "приходит модель техники",
    all("equipment_model" in n for n in items),
    "поле equipment_model отсутствует в ответе API",
)
# Модель обязательна только там, где машина уже известна. У заявки
# (request_created) её нет и быть не может: клиент называет ТИП, а
# конкретную машину предлагает владелец — позже.
order_notifications = [n for n in with_type if n["type"].startswith("order_")]
check(
    "у уведомлений о заказе модель заполнена",
    all(n.get("equipment_model") for n in order_notifications),
    str([n["id"] for n in order_notifications if not n.get("equipment_model")][:5]),
)
check(
    "у уведомления о новой заявке модели нет — машина ещё не выбрана",
    all(
        not n.get("equipment_model")
        for n in items
        if n["type"] == "request_created"
    ),
)

leaked = [
    (n["id"], n["title"], code)
    for n in items
    for code in TYPE_CODES
    if code in (n.get("title") or "")
]
check("код типа не попал в заголовок", not leaked, str(leaked[:3]))

head("7. ТЕКСТ НА ЯЗЫКЕ ПОЛУЧАТЕЛЯ")

# Текст уведомления пишет сервер, и он же уходит в push. Перевести его на
# телефоне нельзя, поэтому язык должен храниться у пользователя.

def set_language(hdr, code):
    return requests.put(f"{API}/users/me", headers=hdr, json={"language": code})

r = set_language(client, "ru")
check("язык сохраняется", r.status_code == 200, f"{r.status_code} {r.text[:120]}")

r = set_language(client, "de")
check("неподдерживаемый язык отклонён", r.status_code == 422, f"{r.status_code}")

set_language(owner, "uz")
set_language(client, "ru")

# Заказ -> владельцу по-узбекски
s2, e2 = free_dates(1)
order = requests.post(f"{API}/orders/", headers=client, json={
    "equipment_id": EQUIPMENT_ID, "start_date": s2, "end_date": e2,
    "delivery_latitude": "41.31", "delivery_longitude": "69.28",
}).json()

owner_last = notifications(owner)[0]
check("владельцу пришло по-узбекски",
      "Yangi buyurtma" in owner_last["title"], owner_last["title"])

# Отмена -> обеим сторонам, каждому на своём
requests.put(f"{API}/orders/{order['id']}", headers=client,
             json={"status": "cancelled"})

client_last = notifications(client)[0]
owner_last = notifications(owner)[0]
check("клиенту пришло по-русски",
      "Заказ отменён" in client_last["title"], client_last["title"])
check("владельцу — по-узбекски",
      "bekor qilindi" in owner_last["title"], owner_last["title"])
check("тело клиента тоже по-русски",
      client_last["body"] and "Заказ" in client_last["body"], str(client_last["body"]))

# Дата в теле — в привычном формате, а не ISO
set_language(client, "ru")
s3, e3 = free_dates(1)
requests.post(f"{API}/orders/", headers=client, json={
    "equipment_id": EQUIPMENT_ID, "start_date": s3, "end_date": e3,
    "delivery_latitude": "41.31", "delivery_longitude": "69.28",
})
body = notifications(owner)[0]["body"] or ""
check("дата в теле не в формате ISO", "-" not in body.split(",")[-1] or "." in body,
      body)

set_language(client, "uz")

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
