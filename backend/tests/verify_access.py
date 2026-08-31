"""
Kirish huquqlarini tekshirish.

Bu testlar yopilgan teshiklarni qorovullaydi: ilgari har qanday tizimga
kirgan foydalanuvchi begona buyurtmalarni ko'rar va o'chirar, begona
yozishmalarni o'qir, boshqa odamning telefon raqamini o'zgartirar va
istalgan hisobni o'chira olardi.

Test IDEMPOTENT — bazani tozalamasdan qayta ishga tushirsa bo'ladi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_access.py
"""
import os
import sys
import re
import time

import requests

API = "http://127.0.0.1:8000"

OWNER_PHONE = "998901110001"
CLIENT_PHONE = "998901110002"
ADMIN_PHONE = "998900000000"
# Begona foydalanuvchi — har safar yangi, testlar bir-biriga xalaqit bermasin
STRANGER_PHONE = f"9989011{int(time.time()) % 100000:05d}"

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


# Kirish _auth.py da: admin kodi javobda kelmaydi va bazadan o'qiladi.
# Sababi o'sha faylda yozilgan.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import otp_code, token  # noqa: E402


def register(phone, name, role):
    """Ro'yxatdan o'tkazish va token olish."""
    requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": otp_code(phone)})
    requests.post(f"{API}/auth/register", json={"full_name": name, "phone": phone, "role": role})
    return token(phone)


owner = token(OWNER_PHONE)
client = token(CLIENT_PHONE)
admin = token(ADMIN_PHONE)
stranger = register(STRANGER_PHONE, "Begona Foydalanuvchi", "client")

client_id = requests.get(f"{API}/users/me", headers=client).json()["id"]
stranger_id = requests.get(f"{API}/users/me", headers=stranger).json()["id"]
print(f"клиент id={client_id}, посторонний id={stranger_id}")

head("1. ЗАКАЗЫ — ЧУЖИЕ НЕ ВИДНЫ")

client_orders = requests.get(f"{API}/orders/", headers=client).json()
stranger_orders = requests.get(f"{API}/orders/", headers=stranger).json()
check("у клиента есть свои заказы", len(client_orders) > 0, f"{len(client_orders)}")
check("посторонний не видит ни одного чужого заказа", stranger_orders == [],
      f"увидел {len(stranger_orders)}")

owner_orders = requests.get(f"{API}/orders/", headers=owner).json()
check("владелец видит заказы на свою технику", len(owner_orders) > 0, f"{len(owner_orders)}")

admin_orders = requests.get(f"{API}/orders/", headers=admin).json()
check("админ видит все заказы", len(admin_orders) >= len(client_orders),
      f"админ {len(admin_orders)}, клиент {len(client_orders)}")

some_order_id = client_orders[0]["id"]
r = requests.get(f"{API}/orders/{some_order_id}", headers=stranger)
check("посторонний не может открыть чужой заказ по id", r.status_code == 403, f"{r.status_code}")

r = requests.get(f"{API}/orders/{some_order_id}", headers=client)
check("свой заказ открывается", r.status_code == 200, f"{r.status_code}")

head("2. УДАЛЕНИЕ ЗАКАЗА — ТОЛЬКО АДМИН")

r = requests.delete(f"{API}/orders/{some_order_id}", headers=stranger)
check("посторонний не может удалить заказ", r.status_code == 403, f"{r.status_code}")

r = requests.delete(f"{API}/orders/{some_order_id}", headers=client)
check("даже владелец заказа не может его удалить", r.status_code == 403, f"{r.status_code}")

head("3. ПОЛЬЗОВАТЕЛИ — ЧУЖОЙ ПРОФИЛЬ ЗАЩИЩЁН")

r = requests.get(f"{API}/users/", headers=stranger)
check("обычный пользователь не может выгрузить список всех", r.status_code == 403, f"{r.status_code}")

r = requests.get(f"{API}/users/", headers=admin)
check("админ список видит", r.status_code == 200, f"{r.status_code}")

r = requests.get(f"{API}/users/{client_id}", headers=stranger)
check("посторонний не может открыть чужой профиль", r.status_code == 403, f"{r.status_code}")

# Мобилка показывает контакты контрагента по заказу — клиент и владелец
# должны видеть друг друга, иначе им не созвониться.
r = requests.get(f"{API}/users/{client_id}", headers=owner)
check("владелец видит профиль своего клиента по общему заказу",
      r.status_code == 200, f"{r.status_code} {r.text[:120]}")

owner_id = requests.get(f"{API}/users/me", headers=owner).json()["id"]
r = requests.get(f"{API}/users/{owner_id}", headers=client)
check("клиент видит профиль владельца техники", r.status_code == 200, f"{r.status_code}")

r = requests.get(f"{API}/users/{owner_id}", headers=stranger)
check("посторонний профиль владельца не видит", r.status_code == 403, f"{r.status_code}")

r = requests.put(f"{API}/users/{client_id}", headers=stranger,
                 json={"phone": "998999999999"})
check("нельзя сменить телефон чужого аккаунта", r.status_code == 403, f"{r.status_code}")

r = requests.delete(f"{API}/users/{client_id}", headers=stranger)
check("нельзя удалить чужой аккаунт", r.status_code == 403, f"{r.status_code}")

r = requests.put(f"{API}/users/{stranger_id}", headers=stranger, json={"full_name": "Yangi Ism"})
check("свой профиль редактируется", r.status_code == 200, f"{r.status_code} {r.text[:100]}")

r = requests.put(f"{API}/users/me", headers=stranger, json={"phone": CLIENT_PHONE})
check("занятый телефон отклоняется понятной ошибкой, а не 500",
      r.status_code == 400, f"{r.status_code}")

r = requests.post(f"{API}/users/", headers=stranger,
                  json={"full_name": "Hacker", "phone": "998900000001",
                        "role": "admin", "password": "x"})
check("нельзя создать себе админа через /users/", r.status_code == 403, f"{r.status_code}")

head("4. ЧАТЫ И СООБЩЕНИЯ — ЧУЖАЯ ПЕРЕПИСКА ЗАКРЫТА")

r = requests.post(f"{API}/chats/", headers=client, json={"order_id": some_order_id})
check("участник заказа может открыть чат", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
chat_id = r.json().get("id") if r.status_code == 200 else None

r = requests.post(f"{API}/chats/", headers=stranger, json={"order_id": some_order_id})
check("посторонний не может открыть чат по чужому заказу", r.status_code == 403, f"{r.status_code}")

if chat_id:
    r = requests.post(f"{API}/messages/", headers=client,
                      json={"chat_id": chat_id, "message_text": "Salom"})
    check("участник может написать в чат", r.status_code == 200, f"{r.status_code} {r.text[:120]}")

    r = requests.post(f"{API}/messages/", headers=stranger,
                      json={"chat_id": chat_id, "message_text": "чужое сообщение"})
    check("посторонний не может писать в чужой чат", r.status_code == 403, f"{r.status_code}")

    r = requests.get(f"{API}/messages/?chat_id={chat_id}", headers=stranger)
    check("посторонний не может читать чужую переписку", r.status_code == 403, f"{r.status_code}")

    r = requests.get(f"{API}/messages/?chat_id={chat_id}", headers=client)
    check("участник переписку читает", r.status_code == 200, f"{r.status_code}")

    r = requests.get(f"{API}/messages/", headers=stranger)
    check("запрос сообщений без chat_id больше не отдаёт всё подряд",
          r.status_code == 400, f"{r.status_code}")

    r = requests.get(f"{API}/chats/{chat_id}", headers=stranger)
    check("посторонний не может открыть чужой чат", r.status_code == 403, f"{r.status_code}")

stranger_chats = requests.get(f"{API}/chats/", headers=stranger).json()
check("в списке чатов постороннего пусто", stranger_chats == [], f"{len(stranger_chats)}")

head("5. ОТЗЫВЫ — СОЗДАНИЕ БОЛЬШЕ НЕ ПАДАЕТ")

r = requests.post(f"{API}/reviews/", headers=client,
                  json={"equipment_id": 1, "rating": 5, "comment": "Yaxshi texnika"})
check("отзыв создаётся (раньше был 500)", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
review = r.json() if r.status_code == 200 else {}
check("автор взят из токена, а не из тела запроса",
      review.get("user_id") == client_id, str(review.get("user_id")))

r = requests.post(f"{API}/reviews/", headers=client,
                  json={"equipment_id": 1, "rating": 9})
check("оценка вне диапазона 1..5 отклонена", r.status_code == 422, f"{r.status_code}")

if review.get("id"):
    r = requests.put(f"{API}/reviews/{review['id']}", headers=stranger, json={"rating": 1})
    check("нельзя править чужой отзыв", r.status_code == 403, f"{r.status_code}")

    r = requests.delete(f"{API}/reviews/{review['id']}", headers=stranger)
    check("нельзя удалить чужой отзыв", r.status_code == 403, f"{r.status_code}")

    r = requests.delete(f"{API}/reviews/{review['id']}", headers=client)
    check("свой отзыв удаляется", r.status_code == 200, f"{r.status_code}")

head("6. ПЛАТЕЖИ — ЧУЖИЕ НЕ ВИДНЫ")

stranger_payments = requests.get(f"{API}/payments/", headers=stranger).json()
check("посторонний не видит чужих платежей", stranger_payments == [],
      f"увидел {len(stranger_payments)}")

r = requests.delete(f"{API}/payments/1", headers=stranger)
check("удалять платежи может только админ", r.status_code == 403, f"{r.status_code}")

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
