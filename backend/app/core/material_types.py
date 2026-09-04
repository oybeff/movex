"""
Qurilish materiallari ma'lumotnomasi.

Nega texnika turlari ro'yxatiga qo'shilmadi. Texnika IJARAGA olinadi va
narxi kunlik; material esa SOTIB olinadi va narxi dona/tonna/m³ uchun.
Bitta ro'yxatga tiqilsa, butun narx hisoblash mashinasi "kunlik narx ×
kunlar" formulasini g'ishtga ham qo'llardi — uch kunga g'isht buyurtma
qilish ma'nosizlik, eskrou esa noto'g'ri summani muzlatardi.

Kod bazada saqlanadi, nomi tarjimadan olinadi — texnika turlaridagi bilan
bir xil qoida (mobile/lib/core/constants/material_types.dart va
assets/translations/*.json, `material_types` bo'limi).
"""
from decimal import Decimal
from typing import Dict, List, Optional

#: O'lchov birliklari. Sotuvchi shulardan birini tanlaydi.
UNIT_PIECE = "piece"     # dona
UNIT_BAG = "bag"         # qop
UNIT_TONNE = "tonne"     # tonna
UNIT_M3 = "m3"           # kub metr

UNITS: List[str] = [UNIT_PIECE, UNIT_BAG, UNIT_TONNE, UNIT_M3]

FALLBACK = "other"


class MaterialType:
    """Bitta material turi va uning odatdagi qiymatlari."""

    def __init__(self, code: str, unit: str, unit_weight_kg: Decimal):
        self.code = code
        #: Sotuvchi uchun taklif qilinadigan birlik — o'zgartira oladi
        self.unit = unit
        #: Bitta birlikning taxminiy og'irligi. MASHINANI TANLASH shunga
        #: bog'liq: 5 000 dona g'isht ≈ 17 tonna, ya'ni "Labo" ketmaydi.
        self.unit_weight_kg = unit_weight_kg


#: Og'irliklar O'zbekiston bozoridagi odatdagi qiymatlar bo'yicha.
#: Sotuvchi o'z tovariga aniqrog'ini yozishi mumkin — bu faqat boshlang'ich.
TYPES: Dict[str, MaterialType] = {
    m.code: m
    for m in [
        MaterialType("brick", UNIT_PIECE, Decimal("3.5")),        # g'isht
        MaterialType("gas_block", UNIT_PIECE, Decimal("18")),     # gazoblok
        MaterialType("cement", UNIT_BAG, Decimal("50")),          # sement, qop
        MaterialType("sand", UNIT_M3, Decimal("1500")),           # qum
        MaterialType("gravel", UNIT_M3, Decimal("1400")),         # shag'al
        MaterialType("stone", UNIT_M3, Decimal("1600")),          # tosh
        MaterialType("rebar", UNIT_TONNE, Decimal("1000")),       # armatura
        MaterialType("concrete", UNIT_M3, Decimal("2400")),       # beton
        MaterialType("lumber", UNIT_M3, Decimal("600")),          # yog'och
        MaterialType(FALLBACK, UNIT_PIECE, Decimal("1")),
    ]
}

CODES: List[str] = list(TYPES.keys())


def is_valid_type(code: Optional[str]) -> bool:
    return bool(code) and code in TYPES


def normalize(code: Optional[str]) -> str:
    """Noma'lum qiymat 'other' ga aylanadi."""
    if not code:
        return FALLBACK
    value = code.strip().lower()
    return value if value in TYPES else FALLBACK


def is_valid_unit(unit: Optional[str]) -> bool:
    return bool(unit) and unit in UNITS


def default_unit(code: Optional[str]) -> str:
    return TYPES[normalize(code)].unit


def default_unit_weight(code: Optional[str]) -> Decimal:
    return TYPES[normalize(code)].unit_weight_kg
