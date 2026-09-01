"""
Adminka: begona saytdan yuborilgan so'rov o'tmasligi kerak (CSRF).

Nega bu alohida tekshiriladi. Panel faqat cookie bilan ishlaydi, cookie esa
brauzer tomonidan har qanday saytdan kelgan so'rovga qo'shiladi. Ya'ni admin
panelga kirgan holda begona sahifani ochsa, o'sha sahifadagi yashirin forma
o'zi jo'nab, admin nomidan amal bajarardi. Tekshiruv umuman yo'q edi:
foydalanuvchini o'chirish, parolini almashtirish, pul yechishni tasdiqlash —
hammasi shu yo'l bilan mumkin edi.

Bu test FAYLLARNI o'qiydi, PHP serverni ishga tushirmaydi: adminka tekshiruv
paytida ishlab turmasligi mumkin, tekshiruvni esa har doim o'tkazish kerak.

Ishga tushirish:
    venv/bin/python tests/verify_admin_csrf.py
"""
import os
import re
import sys

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADMIN = os.path.join(os.path.dirname(BACKEND), "admin")

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


def read(name):
    with open(os.path.join(ADMIN, name), encoding="utf-8") as f:
        return f.read()


head("1. ФУНКЦИИ ЗАЩИТЫ НА МЕСТЕ")

config = read("config.php")
check("generateCsrfToken объявлена", "function generateCsrfToken" in config)
check("verifyCsrfToken объявлена", "function verifyCsrfToken" in config)
check("requireCsrfToken объявлена", "function requireCsrfToken" in config)
check("токен из random_bytes, а не из времени", "random_bytes" in config)
check(
    "сравнение через hash_equals, а не ===",
    "hash_equals" in config,
    "простое сравнение позволяет подобрать токен по времени ответа",
)

head("2. КАЖДАЯ СТРАНИЦА С POST ПРОВЕРЯЕТ ТОКЕН")

# Sahifalar ro'yxati qo'lda emas, KATALOGDAN olinadi: yangi sahifa
# qo'shilsa, ro'yxatni yangilashni unutish mumkin — va aynan o'sha
# himoyasiz qolardi.
pages = sorted(
    f for f in os.listdir(ADMIN)
    if f.endswith(".php") and f not in ("config.php", "logout.php")
)

for name in pages:
    src = read(name)
    if "REQUEST_METHOD" not in src or "POST" not in src:
        continue

    if name == "login.php":
        # Kirish sahifasi die() qilmaydi: token eskirgan bo'lsa odam
        # qaytadan urinadi, aks holda uni o'z panelidan quvib chiqarardik.
        check(f"{name}: токен проверяется", "verifyCsrfToken" in src)
        continue

    check(
        f"{name}: requireCsrfToken() вызывается",
        "requireCsrfToken()" in src,
        "POST принимается без проверки происхождения запроса",
    )

head("3. КАЖДАЯ POST-ФОРМА ОТПРАВЛЯЕТ ТОКЕН")

# Tekshiruv bor, lekin formada token bo'lmasa — sahifa shunchaki ishlamaydi.
form_re = re.compile(r"<form\b[^>]*>", re.S | re.I)

for name in pages:
    src = read(name)
    forms = [m for m in form_re.finditer(src) if re.search(r'method=["\']POST', m.group(0), re.I)]
    if not forms:
        continue

    without_token = 0
    for m in forms:
        # Formaning yopilishigacha bo'lgan qismda token bo'lishi kerak
        end = src.find("</form>", m.end())
        body = src[m.end():end if end != -1 else len(src)]
        if "csrf_token" not in body:
            without_token += 1

    check(
        f"{name}: все {len(forms)} POST-форм с токеном",
        without_token == 0,
        f"без токена: {without_token}",
    )

head("4. ОПАСНЫЕ ДЕЙСТВИЯ ПРИКРЫТЫ")

# Bu amallar orqaga qaytmaydi yoki pulga tegadi.
dangerous = {
    "users.php": ["'delete'", "'set_password'", "'set_role'", "'block'"],
    "payouts.php": ["'paid'", "'rejected'"],  # 'paid' = pul haqiqatan yechildi
    "backup.php": ["'restore_backup'", "'delete_backup'"],
}
for name, actions in dangerous.items():
    src = read(name)
    present = [a.strip("'") for a in actions if a in src]
    check(
        f"{name}: {', '.join(present) or '—'} — под проверкой",
        "requireCsrfToken()" in src and len(present) == len(actions),
        f"найдено {len(present)} из {len(actions)}; "
        "проверка на месте" if "requireCsrfToken()" in src else "ПРОВЕРКИ НЕТ",
    )

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
sys.exit(1 if fail_count else 0)
