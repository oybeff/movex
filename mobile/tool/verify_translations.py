#!/usr/bin/env python3
"""
Tarjimalarni tekshirish.

QA ruscha interfeysning yarmi o'zbekcha qolganini topdi: satrlar to'g'ridan
to'g'ri kodga yozilgan edi va .tr() dan o'tmasdi. Ikkinchi bir xato — kodda
ishlatilgan kalit lug'atda yo'q bo'lsa, easy_localization ekranga kalitning
o'zini chiqaradi ("orders.order_accepted").

Uchta narsani tekshiradi:
  1. ru.json va uz.json kalitlari bir xilmi;
  2. kodda ishlatilgan har bir kalit lug'atda bormi;
  3. kodda .tr() dan o'tmagan o'zbekcha satr qolmadimi.

Ishga tushirish (mobile/ papkasidan):
    python3 tool/verify_translations.py
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "lib")
TRANSLATIONS = os.path.join(ROOT, "assets", "translations")

PLURAL_FORMS = {"zero", "one", "two", "few", "many", "other"}

KEY_IN_CODE = re.compile(r"'([a-z0-9_]+(?:\.[a-z0-9_]+)+)'\s*\.\s*(?:tr|plural)\(")

# O'zbekcha ekanini bildiruvchi so'zlar. Ruscha yoki inglizcha matnda
# uchramaydi, shuning uchun yolg'on ishorat bermaydi.
UZBEK_WORDS = re.compile(
    r"\b("
    r"Yetkaz\w*|Sana|Tanla\w*|Buyurtma\w*|Texnika\w*|Jami|Holat\w*|Komissiya|"
    r"Xarita\w*|Joylashuv\w*|Hisob\w*|Barcha\w*|Bekor|Summa\w*|Joriy|Masalan|"
    r"tahlili|daromad|ma'lumot\w*|Bo'sh|Band|Tanlangan|to'ldirish|"
    r"bo'yicha|xabarlar|egasi|narxi|oralig'\w*|tafsilotlari|kiriting|"
    r"yo'q|Qo'sh\w*|Saqlash|O'chirish|Tahrirlash|Mijoz|so'm|Kutilmoqda"
    r")\b"
)

# Kalitga o'xshash satr ('orders.title') — bu matn emas
KEY_LIKE = re.compile(r"^[a-z0-9_]+(\.[a-z0-9_]+)+$")
STRING_LITERAL = re.compile(r"'((?:[^'\\\n]|\\.)*)'|\"((?:[^\"\\\n]|\\.)*)\"")

ok = 0
problems = []


def check(name, condition, detail=""):
    global ok
    if condition:
        ok += 1
        print(f"  [OK]   {name}")
    else:
        problems.append(f"{name}: {detail}")
        print(f"  [FAIL] {name}\n         {detail}")


def flatten(d, prefix=""):
    out = {}
    for key, value in d.items():
        full = f"{prefix}{key}"
        if isinstance(value, dict) and not PLURAL_FORMS & set(value):
            out.update(flatten(value, full + "."))
        else:
            out[full] = value
    return out


def dart_files():
    for root, _, files in os.walk(LIB):
        for name in files:
            if name.endswith(".dart"):
                yield os.path.join(root, name)


print("=" * 66)
print("ТАРЖИМАЛАРНИ ТЕКШИРИШ")
print("=" * 66)

ru = flatten(json.load(open(os.path.join(TRANSLATIONS, "ru.json"), encoding="utf-8")))
uz = flatten(json.load(open(os.path.join(TRANSLATIONS, "uz.json"), encoding="utf-8")))

only_ru = sorted(set(ru) - set(uz))
only_uz = sorted(set(uz) - set(ru))
check("ru.json va uz.json kalitlari bir xil",
      not only_ru and not only_uz,
      f"faqat ru: {only_ru[:6]}  faqat uz: {only_uz[:6]}")

blank = sorted(k for k, v in {**ru, **uz}.items() if isinstance(v, str) and not v.strip())
check("bo'sh tarjima yo'q", not blank, str(blank[:6]))

used = set()
for path in dart_files():
    used |= set(KEY_IN_CODE.findall(open(path, encoding="utf-8").read()))

missing = sorted(k for k in used if k not in ru)
check(f"kodda ishlatilgan {len(used)} kalitning hammasi lug'atda bor",
      not missing, str(missing[:8]))

hardcoded = []
for path in dart_files():
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("import"):
            continue
        for match in STRING_LITERAL.finditer(line):
            text = match.group(1) if match.group(1) is not None else match.group(2)
            if not text or KEY_LIKE.match(text):
                continue
            if line[match.end():match.end() + 4].startswith(".tr("):
                continue
            if UZBEK_WORDS.search(text):
                rel = os.path.relpath(path, ROOT)
                hardcoded.append(f"{rel}:{number}  {text[:50]}")

check("kodda .tr() dan o'tmagan o'zbekcha satr yo'q",
      not hardcoded,
      "\n         ".join(hardcoded[:8]))

print("=" * 66)
print(f"ИТОГ: {ok} пройдено, {len(problems)} провалено")
print("=" * 66)
sys.exit(1 if problems else 0)
