"""
OTP himoyasini tekshirish.

Asosiy holat: kodni qayta so'rash urinishlar hisobini NOLLAMASLIGI kerak.
Ilgari nollardi, ya'ni 4 xonali kodni 4 tadan taxmin qilib, cheksiz
tanlab olish mumkin edi.

Har safar YANGI telefon raqami olinadi: test oxirida raqam bir soatga
bloklanadi va qayta ishlatib bo'lmaydi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_otp_security.py
"""
import re
import time

import requests

API = "http://127.0.0.1:8000"
MAX_ATTEMPTS = 5  # settings.OTP_MAX_ATTEMPTS

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


def send_otp(phone):
    r = requests.post(f"{API}/auth/send-otp", json={"phone": phone})
    return r.status_code, r.json()


def verify(phone, code):
    r = requests.post(f"{API}/auth/verify-otp",
                      json={"phone": phone, "otp_code": code})
    return r.status_code, r.json()


def text_of(payload):
    """Muvaffaqiyatda 'message', xatoda 'detail' keladi."""
    if isinstance(payload, dict):
        return payload.get("message") or payload.get("detail") or ""
    return str(payload)


def code_from(payload):
    match = re.search(r"(\d{4})\s*$", text_of(payload))
    return match.group(1) if match else None


def attempts_left(payload):
    """Xabar matnidan qolgan urinishlar sonini ajratib olamiz."""
    match = re.search(r"Qolgan urinishlar:\s*(\d+)", text_of(payload))
    return int(match.group(1)) if match else None


# Har bir prognoz uchun alohida raqam — blok bir soat turadi
phone = f"99890{int(time.time()) % 100000000:08d}"
print(f"тестовый номер: {phone}")

head("1. КОД ПРИХОДИТ")

status, resp = send_otp(phone)
check("код отправлен", status == 200, f"{status} {resp}")
real_code = code_from(resp)
check("в тест-режиме код виден в ответе", real_code is not None, str(resp))

head("2. СЧЁТЧИК ПОПЫТОК НЕ СБРАСЫВАЕТСЯ ПОСЛЕ ЗАПРОСА НОВОГО КОДА")

wrong = "0000" if real_code != "0000" else "1111"

for i in range(3):
    _, resp = verify(phone, wrong)
    left = attempts_left(resp)
    check(f"попытка {i + 1}: код отклонён, осталось {left}",
          left == MAX_ATTEMPTS - (i + 1), str(resp))

# Запрашиваем НОВЫЙ код — раньше это обнуляло счётчик
status, resp = send_otp(phone)
check("новый код запрошен", status == 200, f"{status} {resp}")
new_code = code_from(resp)

_, resp = verify(phone, wrong)
check("после нового кода счётчик ПРОДОЛЖИЛСЯ, а не начался заново",
      attempts_left(resp) == MAX_ATTEMPTS - 4,
      f"осталось {attempts_left(resp)}, ожидалось {MAX_ATTEMPTS - 4}: {resp}")

head("3. ПОСЛЕ ИСЧЕРПАНИЯ ПОПЫТОК НОМЕР БЛОКИРУЕТСЯ")

_, resp = verify(phone, wrong)
check("пятая неверная попытка блокирует номер",
      "bloklandi" in text_of(resp), str(resp))

_, resp = verify(phone, new_code or "1234")
check("даже верный код не проходит на заблокированном номере",
      "bloklangan" in text_of(resp), str(resp))

_, resp = send_otp(phone)
check("новый код на заблокированный номер не отправляется",
      "bloklangan" in text_of(resp), str(resp))

head("4. КОД АДМИНА НЕ ОТДАЁТСЯ ДАЖЕ В ТЕСТОВОМ РЕЖИМЕ")

# Тестовый режим кладёт код прямо в ответ — это удобно при разработке.
# Но как только сервер доступен снаружи (туннель, демо-стенд), это отдаёт
# админский аккаунт любому: номер известен, код спрашивается запросом.
# Админ в мобильное приложение не заходит, он работает через PHP-панель.

ADMIN_PHONE = "998900000000"

r = requests.post(f"{API}/auth/send-otp", json={"phone": ADMIN_PHONE})
check("запрос на админский номер принят", r.status_code == 200, f"{r.status_code}")

body = r.text
check("кода в ответе нет", "TEST MODE" not in body and "otp_code" not in body,
      body[:120])
check("четырёхзначного кода в тексте нет",
      re.search(r"\b\d{4}\b", r.json().get("message", "")) is None,
      r.json().get("message", ""))

# Обычный пользователь должен продолжать получать код — иначе сломается
# и разработка, и остальные тесты
ordinary = f"99890{(int(time.time()) + 7) % 100000000:08d}"
r = requests.post(f"{API}/auth/send-otp", json={"phone": ordinary})
check("обычному пользователю код по-прежнему приходит",
      "TEST MODE" in r.text, r.text[:120])

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
