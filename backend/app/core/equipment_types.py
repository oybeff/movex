"""
Texnika turlari ma'lumotnomasi — yagona haqiqat manbai.

Ilgari `equipment.type` erkin matn edi: egasi "Ekskavator", "экскаватор" yoki
"Ekskavator-pogruzchik" deb yozardi, katalogdagi filtr esa shu chalkashlikdan
yig'ilardi va turga ikonka biriktirib bo'lmasdi.

Endi bazada TUR KODI saqlanadi (`excavator`, `truck_crane`, ...), nomlari esa
shu yerdan olinadi. Mobil ilovadagi ro'yxat shu kodlar bilan bir xil bo'lishi
kerak: mobile/lib/core/constants/equipment_types.dart

Yangi tur qo'shish:
  1. shu ro'yxatga yozish;
  2. mobil ilovadagi ro'yxatga o'sha kodni qo'shish;
  3. assets/equipment_types/<icon>.png ikonkasini qo'yish;
  4. uz.json va ru.json ga nom qo'shish.
"""
from typing import Dict, List, Optional

# code — bazada saqlanadigan qiymat, o'zgartirib bo'lmaydi (eski yozuvlar buziladi).
EQUIPMENT_TYPES: List[Dict[str, str]] = [
    {"code": "excavator",       "name_ru": "Экскаватор",            "name_uz": "Ekskavator"},
    {"code": "backhoe_loader",  "name_ru": "Экскаватор-погрузчик",  "name_uz": "Ekskavator-yuklagich"},
    {"code": "mini_excavator",  "name_ru": "Мини-экскаватор",       "name_uz": "Mini ekskavator"},
    {"code": "bulldozer",       "name_ru": "Бульдозер",             "name_uz": "Buldozer"},
    {"code": "front_loader",    "name_ru": "Фронтальный погрузчик", "name_uz": "Frontal yuklagich"},
    {"code": "truck_crane",     "name_ru": "Автокран",              "name_uz": "Avtokran"},
    {"code": "manipulator",     "name_ru": "Манипулятор",           "name_uz": "Manipulyator"},
    {"code": "aerial_platform", "name_ru": "Автовышка",             "name_uz": "Avtovishka"},
    {"code": "dump_truck",      "name_ru": "Самосвал",              "name_uz": "Samosval"},
    {"code": "concrete_mixer",  "name_ru": "Бетономешалка",         "name_uz": "Beton aralashtirgich"},
    {"code": "concrete_pump",   "name_ru": "Бетононасос",           "name_uz": "Betonnasos"},
    {"code": "grader",          "name_ru": "Грейдер",               "name_uz": "Greyder"},
    {"code": "roller",          "name_ru": "Каток",                 "name_uz": "Katok"},
    {"code": "auger_drill",     "name_ru": "Ямобур",                "name_uz": "Yamobur"},
    {"code": "tow_truck",       "name_ru": "Трал / Эвакуатор",      "name_uz": "Tral / Evakuator"},
    {"code": "compressor",      "name_ru": "Компрессор",            "name_uz": "Kompressor"},
    # Ro'yxatga tushmagan texnika uchun. Eski yozuvlarni ko'chirishda ham ishlatiladi.
    {"code": "other",           "name_ru": "Другая техника",        "name_uz": "Boshqa texnika"},
]

EQUIPMENT_TYPE_CODES = {t["code"] for t in EQUIPMENT_TYPES}

FALLBACK_TYPE_CODE = "other"


def is_valid_type(code: Optional[str]) -> bool:
    return code in EQUIPMENT_TYPE_CODES


def get_type(code: str) -> Optional[Dict[str, str]]:
    for t in EQUIPMENT_TYPES:
        if t["code"] == code:
            return t
    return None


# Eski erkin matnli qiymatlarni kodga o'girish uchun kalit so'zlar.
# Tartib MUHIM: aniqroq moslik oldinroq turadi, aks holda "ekskavator-yuklagich"
# oddiy "ekskavator" deb tushunib qolinadi.
_KEYWORD_MAP = [
    ("backhoe_loader",  ["ekskavator-yuklagich", "ekskavator yuklagich", "экскаватор-погрузчик",
                         "экскаватор погрузчик", "backhoe", "pogruzchik"]),
    ("mini_excavator",  ["mini ekskavator", "miniekskavator", "мини-экскаватор", "мини экскаватор",
                         "mini excavator"]),
    ("excavator",       ["ekskavator", "экскаватор", "excavator"]),
    ("front_loader",    ["frontal yuklagich", "фронтальный погрузчик", "front loader", "yuklagich",
                         "погрузчик"]),
    ("bulldozer",       ["buldozer", "бульдозер", "bulldozer"]),
    ("truck_crane",     ["avtokran", "автокран", "kran", "кран", "crane"]),
    ("manipulator",     ["manipulyator", "манипулятор", "manipulator"]),
    ("aerial_platform", ["avtovishka", "автовышка", "vishka", "вышка", "aerial"]),
    ("dump_truck",      ["samosval", "самосвал", "dump truck", "wagon"]),
    ("concrete_pump",   ["betonnasos", "бетононасос", "beton nasos", "concrete pump"]),
    ("concrete_mixer",  ["beton aralashtirgich", "бетономешалка", "mikser", "миксер",
                         "concrete mixer", "betonomeshalka"]),
    ("grader",          ["greyder", "грейдер", "grader"]),
    ("roller",          ["katok", "каток", "roller"]),
    ("auger_drill",     ["yamobur", "ямобур", "auger", "bur"]),
    ("tow_truck",       ["evakuator", "эвакуатор", "tral", "трал", "tow truck"]),
    ("compressor",      ["kompressor", "компрессор", "compressor"]),
]


def normalize_type(raw: Optional[str]) -> str:
    """
    Erkin matnli turni kodga o'giradi. Tanib bo'lmasa — 'other'.
    Migratsiyada va eski mobil ilovalardan kelgan so'rovlarda ishlatiladi.
    """
    if not raw:
        return FALLBACK_TYPE_CODE

    value = raw.strip().lower()
    if value in EQUIPMENT_TYPE_CODES:
        return value

    for code, keywords in _KEYWORD_MAP:
        for keyword in keywords:
            if keyword in value:
                return code

    return FALLBACK_TYPE_CODE
