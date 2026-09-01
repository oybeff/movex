"""
Texnika turlarini tanish (normalize_type) tekshiruvi.

Eng muhim holat: "Ekskavator-yuklagich" oddiy "Ekskavator" deb tushunilmasligi
kerak — kalit so'zlar ro'yxatidagi TARTIB shuni ta'minlaydi. Yangi tur
qo'shganda shu testni qayta ishga tushiring.

Ishga tushirish:  venv/bin/python tests/verify_equipment_types.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.equipment_types import type_name, EQUIPMENT_TYPE_CODES, normalize_type

CASES = [
    # aniqroq moslik umumiysidan ustun turishi kerak
    ("Ekskavator-yuklagich", "backhoe_loader"),
    ("Экскаватор-погрузчик", "backhoe_loader"),
    ("Mini ekskavator", "mini_excavator"),
    ("мини-экскаватор", "mini_excavator"),
    ("Ekskavator", "excavator"),
    ("экскаватор", "excavator"),
    ("EXCAVATOR", "excavator"),
    ("excavator", "excavator"),

    ("Avtokran", "truck_crane"),
    ("автокран", "truck_crane"),
    ("кран 25т", "truck_crane"),
    ("Manipulyator", "manipulator"),
    ("Avtovishka", "aerial_platform"),

    ("Buldozer", "bulldozer"),
    ("Фронтальный погрузчик", "front_loader"),
    ("Samosval", "dump_truck"),
    ("Greyder", "grader"),
    ("Katok", "roller"),
    ("Yamobur", "auger_drill"),
    ("эвакуатор", "tow_truck"),
    ("Kompressor", "compressor"),

    ("Betonnasos", "concrete_pump"),
    ("Бетононасос", "concrete_pump"),
    ("Бетономешалка", "concrete_mixer"),
    ("миксер", "concrete_mixer"),

    # tanib bo'lmaydigan qiymatlar
    ("qandaydir texnika", "other"),
    ("", "other"),
    (None, "other"),
]


def main() -> int:
    failed = 0

    for raw, expected in CASES:
        got = normalize_type(raw)
        if got != expected:
            failed += 1
            print(f"  [FAIL] {raw!r} -> {got} (kutilgan: {expected})")

    # har bir kod haqiqatan ma'lumotnomada bormi
    for _, expected in CASES:
        if expected not in EQUIPMENT_TYPE_CODES:
            failed += 1
            print(f"  [FAIL] ma'lumotnomada '{expected}' kodi yo'q")

    # type_name kodni o'qiladigan nomga aylantiradi
    for code in EQUIPMENT_TYPE_CODES:
        for lang in ("uz", "ru"):
            name = type_name(code, lang)
            if not name or name == code:
                failed += 1
                print(f"  [FAIL] type_name({code!r}, {lang!r}) -> {name!r}")

    if type_name(None) != "":
        failed += 1
        print("  [FAIL] type_name(None) bo'sh satr qaytarishi kerak")

    # Kod foydalanuvchi ko'radigan matnga tushib qolmasin.
    #
    # Bir necha marta shunday bo'lgan: xabarnoma sarlavhasida
    # "backhoe_loader JCB 3CX", tranzaksiya izohida "excavator Komatsu
    # PC200", adminkada "excavator - Komatsu PC200". Har safar sabab bitta —
    # equipment.type ni to'g'ridan-to'g'ri f-satrga qo'yish.
    import re
    from pathlib import Path

    backend_root = Path(__file__).resolve().parent.parent / "app"
    leaks = []
    raw_in_text = re.compile(r'f"[^"]*\{\s*equipment\.type\s*\}')
    for path in backend_root.rglob("*.py"):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if raw_in_text.search(line):
                leaks.append(f"backend/app/{path.relative_to(backend_root)}:{number}")

    # ILOVA ham tekshiriladi.
    #
    # Ilgari bu tekshiruv faqat backend fayllariga qarardi, va aynan shuning
    # uchun to'rtinchi holatni o'tkazib yubordi: mijozning asosiy ekranida
    # texnika kartochkasi sarlavhasi "excavator", "mini_excavator" deb
    # chiqardi — lotin harflarida, ma'lumotnoma kodi ko'rinishida. Brauzerda
    # ko'rinib qoldi, tekshiruvda emas.
    #
    # Ikki naqsh qidiriladi:
    #   '${tech.type}'  — satr ichida
    #   Text(\n  tech.type,  — to'g'ridan-to'g'ri Text ga
    # Faqat texnikaga tegishli o'zgaruvchilar: transaction.type yoki
    # method.type — boshqa soha, ularni ushlash kerak emas.
    mobile_root = Path(__file__).resolve().parent.parent.parent / "mobile" / "lib"
    equipmentish = r"[A-Za-z_]*(?:[Tt]ech|[Ee]quipment|\beq)[A-Za-z0-9_]*!?"
    interpolated = re.compile(r"\$\{?\s*" + equipmentish + r"\.type\s*\}?")
    bare_arg = re.compile(r"^\s*" + equipmentish + r"\.type\s*,\s*$")

    if mobile_root.is_dir():
        for path in mobile_root.rglob("*.dart"):
            lines = path.read_text(encoding="utf-8").splitlines()
            for number, line in enumerate(lines, 1):
                if "EquipmentTypes" in line or "//" in line.split(".type")[0]:
                    continue
                hit = interpolated.search(line)
                if not hit and bare_arg.match(line):
                    previous = lines[number - 2].rstrip() if number >= 2 else ""
                    hit = previous.endswith("Text(") or previous.endswith("child: Text(")
                if hit:
                    leaks.append(f"mobile/lib/{path.relative_to(mobile_root)}:{number}")

    if leaks:
        failed += len(leaks)
        for place in leaks:
            print(f"  [FAIL] kod foydalanuvchiga ko'rinmoqda: {place}")

    print(f"\n{len(CASES)} holat tekshirildi, {failed} ta xato")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
