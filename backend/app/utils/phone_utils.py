"""
Telefon raqam bilan ishlash uchun utility funksiyalar
"""
import re
from typing import Optional


def clean_phone_number(phone: str) -> str:
    """
    Telefon raqamdan barcha belgilar va probellarni olib tashlash
    
    Misol:
        +998 90 123 45 67 -> 998901234567
        +998-90-123-45-67 -> 998901234567
        998 (90) 123-45-67 -> 998901234567
    """
    # Faqat raqamlarni qoldirish
    cleaned = re.sub(r'[^\d]', '', phone)
    return cleaned


def to_db_phone(phone: str) -> str:
    """
    Bazada saqlanadigan YAGONA ko'rinish: 998901234567.

    Kirish har doim shu ko'rinish bo'yicha qidiradi (`/auth` da raqamdan
    "+", probel va qavslar olib tashlanadi). Agar profilga raqam boshqacha
    yozilib qolsa — masalan "+998901234567" — odam O'Z hisobiga kira
    olmaydi: qidiruv uni topmaydi.

    Bo'sh yoki tanib bo'lmaydigan qiymat o'zgartirilmasdan qaytariladi:
    tekshiruv bu funksiyaning ishi emas.
    """
    digits = clean_phone_number(phone or "")
    if digits.startswith("00998"):
        digits = digits[5:]
    if len(digits) == 9:
        digits = "998" + digits
    elif len(digits) == 10 and digits.startswith("8"):
        digits = "998" + digits[1:]
    return digits


def format_phone_number(phone: str) -> str:
    """
    Telefon raqamni standart formatga keltirish: +998901234567
    
    Misol:
        998901234567 -> +998901234567
        901234567 -> +998901234567
        +998901234567 -> +998901234567
    """
    cleaned = clean_phone_number(phone)
    
    # Agar 998 bilan boshlanmasa, qo'shamiz
    if not cleaned.startswith('998'):
        if len(cleaned) == 9:  # Faqat 901234567
            cleaned = '998' + cleaned
        else:
            raise ValueError("Invalid phone number format")
    
    # + belgisini qo'shamiz
    if not cleaned.startswith('+'):
        cleaned = '+' + cleaned
    
    return cleaned


def validate_uzbek_phone(phone: str) -> bool:
    """
    O'zbekiston telefon raqamini validatsiya qilish
    
    Format: +998XXXXXXXXX (12 ta raqam + belgisi bilan)
    Operator kodlari: 90, 91, 93, 94, 95, 97, 98, 99, 33, 88, 77, 71, 50
    """
    try:
        formatted = format_phone_number(phone)
        
        # +998 bilan boshlanishi kerak
        if not formatted.startswith('+998'):
            return False
        
        # Uzunligi 13 bo'lishi kerak (+998XXXXXXXXX)
        if len(formatted) != 13:
            return False
        
        # Operator kodini tekshirish
        operator_code = formatted[4:6]
        # O'zbekiston kodlari. '20' — yangi kod (eSIM/yangi operatorlar),
        # ro'yxatda yo'q edi va +99820... raqamlar "noto'g'ri" deb rad
        # etilardi — hisob to'ldirish shundan yiqilgan. '55' ham qo'shildi.
        valid_operators = ['90', '91', '93', '94', '95', '97', '98', '99',
                           '33', '88', '77', '71', '50', '20', '55']
        
        if operator_code not in valid_operators:
            return False
        
        return True
    except:
        return False


def mask_phone_number(phone: str) -> str:
    """
    Telefon raqamni maskirovka qilish (xavfsizlik uchun)
    
    Misol:
        +998901234567 -> +998*****4567
    """
    try:
        formatted = format_phone_number(phone)
        if len(formatted) >= 13:
            return formatted[:4] + '*****' + formatted[-4:]
        return formatted
    except:
        return phone


def get_operator_name(phone: str) -> Optional[str]:
    """
    Telefon raqamdan operator nomini aniqlash
    """
    try:
        formatted = format_phone_number(phone)
        operator_code = formatted[4:6]
        
        operators = {
            '90': 'Beeline',
            '91': 'Beeline',
            '93': 'Uzmobile',
            '94': 'Uzmobile',
            '95': 'Uzmobile',
            '97': 'Uzmobile',
            '98': 'Ucell',
            '99': 'Ucell',
            '33': 'Ucell',
            '88': 'Mobiuz',
            '77': 'Mobiuz',
            '71': 'Humans',
            '50': 'Ums',
        }
        
        return operators.get(operator_code, 'Unknown')
    except:
        return None

