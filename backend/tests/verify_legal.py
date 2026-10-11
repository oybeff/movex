"""
Oferta va maxfiylik siyosati haqiqatan ko'rinadi.

Prodda ilova "Maxfiylik siyosati hali yuklanmagan" deb ko'rsatgan — Google
Play siyosat ilova ichida ham bo'lishini talab qiladi. Bu test shunga
qaytmaslik uchun: ilova endpointlari va sayt sahifalari haqiqiy matn
qaytaradi, unda hozirgi ilovaga mos narsalar yozilgan.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_legal.py
"""
import sys

import requests

API = "http://127.0.0.1:8000"
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


for kind in ("privacy", "terms"):
    for lang in ("uz", "ru"):
        r = requests.get(f"{API}/settings/{kind}/{lang}")
        content = r.json().get("content", "") if r.ok else ""
        check(f"/settings/{kind}/{lang} — matn bor", r.ok and len(content) > 1500, len(content))
        check(f"/settings/{kind}/{lang} — zaglushka emas",
              "yuklanmagan" not in content and "не загружен" not in content)

    page = requests.get(f"{API}/{kind}")
    check(f"/{kind} — HTML sahifa", page.ok and "text/html" in page.headers.get("content-type", ""))

privacy = requests.get(f"{API}/privacy").text
check("siyosatda SMS shlyuzi (Eskiz) yozilgan", "Eskiz" in privacy)
check("siyosatda Multicard yozilgan", "Multicard" in privacy)
check("siyosatda ilovadan o'chirish yozilgan", "Удалить аккаунт" in privacy)
check("Telegram orqali kirish endi yo'q", "Вход через Telegram" not in privacy)
check("Click/Payme endi yo'q", "Payme" not in privacy)

print(f"\nNATIJA: {ok_count} OK, {fail_count} FAIL")
sys.exit(1 if fail_count else 0)
