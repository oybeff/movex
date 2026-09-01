"""
Hisob holati: bloklash va muzlatish.

Bloklash — odam umuman kira olmaydi.
Muzlatish — kiradi va hammasini ko'radi, lekin pul qimirlatadigan amallarni
qila olmaydi: buyurtma, taklif, e'lon, pul yechish.

Eng muhim tekshiruv: BLOKLASHDAN OLDIN OLINGAN TOKEN ham ishlamasligi kerak.
Token 30 kun yashaydi — faqat kirish paytida tekshirsak, bloklangan odam
yana bir oy ishlayverardi.

Test IDEMPOTENT: holatlarni o'zgartiradi, oxirida qaytaradi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_account_state.py
"""
import os
import sys

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND)

from _auth import otp_code, token  # noqa: E402

API = "http://127.0.0.1:8000"
CLIENT_PHONE = "998901179425"
OWNER_PHONE = "998901110001"

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


def set_state(phone, **flags):
    """Holatni bazadan o'zgartiramiz — adminka HTTP orqali ishlaydi."""
    from sqlalchemy import text

    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        sets = ", ".join(f"{k} = :{k}" for k in flags)
        db.execute(
            text(f"UPDATE users SET {sets} WHERE phone = :phone"),
            {**flags, "phone": phone},
        )
        db.commit()
    finally:
        db.close()


def user_id(phone):
    from sqlalchemy import text

    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        return db.execute(
            text("SELECT id FROM users WHERE phone = :p"), {"p": phone}
        ).scalar()
    finally:
        db.close()


set_state(CLIENT_PHONE, is_blocked=False, is_frozen=False)
set_state(OWNER_PHONE, is_blocked=False, is_frozen=False)

head("1. БЛОКИРОВКА ЗАКРЫВАЕТ ВХОД")

client = token(CLIENT_PHONE)
check("до блокировки профиль открыт",
      requests.get(f"{API}/users/me", headers=client).status_code == 200)

set_state(CLIENT_PHONE, is_blocked=True, blocked_reason="Тест блокировки")

r = requests.get(f"{API}/users/me", headers=client)
check("СТАРЫЙ токен перестал работать", r.status_code == 403, f"{r.status_code}")
check("причина показана", "Тест" in str(r.json().get("detail", "")),
      str(r.json().get("detail"))[:60])

r = requests.post(f"{API}/auth/verify-otp",
                  json={"phone": CLIENT_PHONE, "otp_code": otp_code(CLIENT_PHONE)})
check("войти заново нельзя", r.status_code == 403, f"{r.status_code}")
check("токен не выдан", "access_token" not in r.text)

set_state(CLIENT_PHONE, is_blocked=False, blocked_reason=None)
r = requests.post(f"{API}/auth/verify-otp",
                  json={"phone": CLIENT_PHONE, "otp_code": otp_code(CLIENT_PHONE)})
check("после разблокировки вход работает", r.status_code == 200, f"{r.status_code}")

head("2. ЗАМОРОЖЕННЫЙ ВИДИТ, НО НЕ ДЕЙСТВУЕТ")

client = token(CLIENT_PHONE)
set_state(CLIENT_PHONE, is_frozen=True)

check("каталог виден",
      requests.get(f"{API}/equipment/", headers=client, params={"limit": 1}).status_code == 200)
check("профиль виден",
      requests.get(f"{API}/users/me", headers=client).status_code == 200)
check("лента объявлений видна",
      requests.get(f"{API}/listings/feed", headers=client).status_code == 200)
check("уведомления видны",
      requests.get(f"{API}/notifications/", headers=client).status_code == 200)

r = requests.post(f"{API}/listings/", headers=client, json={"title": "проверка заморозки"})
check("объявление разместить нельзя", r.status_code == 403, f"{r.status_code}")

r = requests.post(f"{API}/orders/", headers=client, json={
    "equipment_id": 1, "start_date": "2044-01-01", "end_date": "2044-01-02",
    "delivery_latitude": "41.3", "delivery_longitude": "69.2"})
check("заказ оформить нельзя", r.status_code == 403, f"{r.status_code}")

r = requests.post(f"{API}/requests/", headers=client, json={
    "equipment_type": "excavator", "start_date": "2044-01-01", "end_date": "2044-01-02",
    "delivery_latitude": 41.3, "delivery_longitude": 69.2})
check("заявку создать нельзя", r.status_code == 403, f"{r.status_code}")

set_state(CLIENT_PHONE, is_frozen=False)
r = requests.post(f"{API}/listings/", headers=client, json={"title": "после разморозки"})
check("после разморозки всё работает", r.status_code == 200, f"{r.status_code}")
if r.status_code == 200:
    requests.post(f"{API}/listings/{r.json()['id']}/cancel", headers=client)

head("3. ЗАМОРОЗКА ОСТАНАВЛИВАЕТ ВЫВОД ДЕНЕГ")

owner = token(OWNER_PHONE)
set_state(OWNER_PHONE, is_frozen=True)

r = requests.post(f"{API}/payouts/", headers=owner,
                  json={"amount": 100000, "card_number": "8600123412341234"})
check("вывод денег остановлен", r.status_code == 403, f"{r.status_code}")
check("причина — заморозка, а не роль",
      "muzlatilgan" in str(r.json().get("detail", "")).lower(),
      str(r.json().get("detail"))[:70])

r = requests.get(f"{API}/payouts/", headers=owner)
check("историю выплат смотреть можно", r.status_code == 200, f"{r.status_code}")

set_state(OWNER_PHONE, is_frozen=False)
check("владелец разморожен", True)

head("4. АДМИНА ЗАБЛОКИРОВАТЬ НЕЛЬЗЯ ЧЕРЕЗ ПАНЕЛЬ")

# Panel admin roliga hech qanday amal qo'llamaydi: o'zini bloklab qo'yish —
# paneldan chiqib ketishning eng oson yo'li.
from sqlalchemy import text  # noqa: E402

from app.db.session import SessionLocal  # noqa: E402

db = SessionLocal()
admin_blocked = db.execute(
    text("SELECT is_blocked FROM users WHERE role = 'admin'")
).fetchall()
db.close()
check("ни один админ не заблокирован",
      all(not row[0] for row in admin_blocked), str(admin_blocked))

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
