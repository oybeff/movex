"""
Telegram vebhukini tekshirish.

Vebhuk — KIRISH nuqtasi: unga kelgan "contact" xabari so'rovni
tasdiqlaydi, ya'ni odamni telefon raqami bo'yicha ilovaga kiritadi.
Shuning uchun bu yerda parol ham, kod ham so'ralmaydi va manzil
himoyasi butun kirishning himoyasi bo'lib qoladi.

Ikki narsa tekshiriladi:

1. Manzilga faqat Telegram kira oladi. Maxfiy so'z bo'lmasa — 404,
   noto'g'ri bo'lsa — 403.
2. BEGONA raqam bilan kirib bo'lmaydi. Telegram contact xabarida
   user_id bo'ladi; u yuboruvchiga teng bo'lmasa, raqam o'zinikimas —
   bunday xabar so'rovni tasdiqlamasligi kerak. Aks holda istalgan
   odam boshqasining kontaktini yuborib, uning hisobiga kirardi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_telegram_webhook.py
"""
import os
import sys
import time

import requests

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

from app.core.config import settings  # noqa: E402

API = "http://127.0.0.1:8000"
HOOK = f"{API}/auth/telegram/webhook"
HEADER = "X-Telegram-Bot-Api-Secret-Token"

SECRET = settings.TELEGRAM_WEBHOOK_SECRET

#: Sinov uchun chat raqami — haqiqiy odamniki bilan to'qnashmasin
CHAT_ID = 900000000 + int(time.time()) % 1000000
OTHER_ID = CHAT_ID + 1
TEST_PHONE = f"99890{CHAT_ID % 10000000:07d}"

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


def post(payload, secret=None, raw=None):
    headers = {}
    if secret is not None:
        headers[HEADER] = secret
    if raw is not None:
        headers["Content-Type"] = "application/json"
        return requests.post(HOOK, data=raw, headers=headers, timeout=30)
    return requests.post(HOOK, json=payload, headers=headers, timeout=30)


def message(chat_id, **extra):
    msg = {"message_id": 1, "chat": {"id": chat_id}, "from": {"id": chat_id}}
    msg.update(extra)
    return {"update_id": int(time.time() * 1000) % 2_000_000_000, "message": msg}


def request_status(token):
    r = requests.get(f"{API}/auth/telegram/status", params={"token": token}, timeout=20)
    return r.json().get("status")


def cleanup():
    """Sinov qoldiqlarini o'chiradi — baza toza qolsin."""
    from sqlalchemy import text

    from app.db.session import SessionLocal

    db = SessionLocal()
    try:
        db.execute(text("DELETE FROM telegram_login_requests WHERE chat_id = :c"),
                   {"c": CHAT_ID})
        db.execute(text("DELETE FROM telegram_accounts WHERE chat_id = :c OR phone = :p"),
                   {"c": CHAT_ID, "p": TEST_PHONE})
        db.commit()
    except Exception as exc:  # noqa: BLE001
        db.rollback()
        print(f"  (tozalash bajarilmadi: {exc})")
    finally:
        db.close()


# ------------------------------------------------------- manzil himoyasi

head("Manzilga kirish")

if not SECRET:
    # So'z ko'rsatilmagan — manzil YOPIQ bo'lishi shart. Aynan shu holat
    # xavfli: ochiq qolsa, uni bilgan har kim soxta kirish yuborardi.
    r = post(message(CHAT_ID, text="/start"))
    check("maxfiy so'z yo'q — manzil yopiq (404)", r.status_code == 404, f"{r.status_code}")

    r = post(message(CHAT_ID, text="/start"), secret="istalgan")
    check("so'z bilan ham yopiq", r.status_code == 404, f"{r.status_code}")

    print("\n  TELEGRAM_WEBHOOK_SECRET bo'sh — so'rab turish rejimi.")
    print("  Prodda so'z to'ldiriladi, shunda qolgan tekshiruvlar ham ishlaydi.")
else:
    r = post(message(CHAT_ID, text="/start"))
    check("sarlavhasiz so'rov rad etildi (403)", r.status_code == 403, f"{r.status_code}")

    r = post(message(CHAT_ID, text="/start"), secret=SECRET[:-1] + "x")
    check("noto'g'ri so'z rad etildi (403)", r.status_code == 403, f"{r.status_code}")

    r = post(message(CHAT_ID, text="/start"), secret=SECRET)
    check("to'g'ri so'z bilan qabul qilindi (200)", r.status_code == 200, f"{r.status_code}")

    # Buzuq tanaga ham 200 kerak: boshqa javobda Telegram AYNAN shu
    # yangilikni qayta-qayta yuboraveradi va navbat butunlay to'xtaydi.
    r = post(None, secret=SECRET, raw=b"bu json emas")
    check("buzuq tanaga ham 200", r.status_code == 200, f"{r.status_code}")

    r = post({"update_id": 1}, secret=SECRET)
    check("xabarsiz yangilikka ham 200", r.status_code == 200, f"{r.status_code}")

    # --------------------------------------------- begona raqam bilan kirish

    head("Begona raqam bilan kirib bo'lmasligi")

    started = requests.post(f"{API}/auth/telegram/start", timeout=20)
    check("kirish so'rovi yaratildi", started.status_code == 200, started.text[:120])
    token = started.json().get("token") if started.status_code == 200 else None

    if token:
        check("yangi so'rov — pending", request_status(token) == "pending")

        post(message(CHAT_ID, text=f"/start {token}"), secret=SECRET)
        check("/start dan keyin hali tasdiqlanmagan",
              request_status(token) == "pending",
              "raqam ulashilmasdan tasdiqlanib qoldi")

        # ASOSIY holat: kontakt BOSHQA odamniki (user_id yuboruvchiga teng emas)
        post(message(CHAT_ID, contact={"phone_number": "+998901112233",
                                       "user_id": OTHER_ID}), secret=SECRET)
        check("begona kontakt so'rovni TASDIQLAMADI",
              request_status(token) == "pending",
              "begona raqam bilan kirish ochilib ketdi")

        # user_id umuman yo'q — eski mijozlar shunday yuborishi mumkin
        post(message(CHAT_ID, contact={"phone_number": "+998901112233"}), secret=SECRET)
        check("user_id siz kontakt ham tasdiqlamadi",
              request_status(token) == "pending")

        # O'Z raqami — mana endi tasdiqlanishi kerak
        post(message(CHAT_ID, contact={"phone_number": f"+{TEST_PHONE}",
                                       "user_id": CHAT_ID}), secret=SECRET)
        check("o'z raqami bilan tasdiqlandi",
              request_status(token) == "confirmed",
              "haqiqiy kontakt ham o'tmadi — kirish umuman ishlamaydi")

        # Noma'lum token — hech narsa buzilmasin
        r = post(message(CHAT_ID + 5, text="/start notoken12345"), secret=SECRET)
        check("noma'lum token — 200, xatosiz", r.status_code == 200, f"{r.status_code}")

    cleanup()

head(f"ITOG: {ok_count} o'tdi, {fail_count} yiqildi")
raise SystemExit(1 if fail_count else 0)
