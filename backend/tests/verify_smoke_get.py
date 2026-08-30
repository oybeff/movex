"""
Дымовой прогон: дёргаем КАЖДЫЙ GET-эндпоинт из OpenAPI и ищем 500-е.

Смысл: 500 означает, что код падает — обращение к несуществующему полю,
кривой запрос, забытый импорт. 401/403/404/422 это нормальные ответы,
их не считаем проблемой.
"""
import re
from datetime import datetime

import requests

API = "http://127.0.0.1:8000"

# Подстановки для параметров пути
SAMPLES = {
    "equipment_id": 1,
    "order_id": 1,
    "user_id": 2,
    "chat_id": 1,
    "message_id": 1,
    "review_id": 1,
    "payment_id": 1,
    "company_id": 1,
    "photo_id": 1,
    "transaction_id": 1,
    "notification_id": 1,
    "request_id": 1,
    "filename": "test.sql",
    "key": "commission_percent",
    "lang": "ru",
    "method_id": 1,
}


def token(phone):
    r = requests.post(f"{API}/auth/send-otp", json={"phone": phone})
    code = re.search(r"(\d{4})\s*$", r.json()["message"]).group(1)
    r = requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": code})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


admin = token("998900000000")
owner = token("998901110001")

spec = requests.get(f"{API}/openapi.json").json()

problems = []
checked = 0
skipped = []

for path, methods in sorted(spec["paths"].items()):
    if "get" not in methods:
        continue

    url = path
    for name, value in SAMPLES.items():
        url = url.replace("{" + name + "}", str(value))

    if "{" in url:
        skipped.append(path)
        continue

    for label, headers in (("admin", admin), ("owner", owner)):
        try:
            r = requests.get(f"{API}{url}", headers=headers, timeout=20)
        except Exception as exc:
            problems.append((path, label, "EXC", str(exc)[:80]))
            continue

        checked += 1
        if r.status_code >= 500:
            problems.append((path, label, r.status_code, r.text[:120]))

print(f"проверено вызовов: {checked}")
print(f"пропущено путей:   {len(skipped)}  {skipped}")
print()

if problems:
    print(f"НАЙДЕНО ПРОБЛЕМ: {len(problems)}")
    for path, who, status, detail in problems:
        print(f"  [{status}] {path}  (как {who})")
        print(f"          {detail}")
    raise SystemExit(1)
else:
    print("500-х нет — все GET-эндпоинты отвечают корректно")
    raise SystemExit(0)
