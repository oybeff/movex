"""
Buyurtma narxini SERVERDA hisoblash.

Mijoz yuborgan total_amount va commission qiymatlariga ishonib bo'lmaydi —
ilovani o'zgartirib yoki to'g'ridan-to'g'ri API'ga so'rov yuborib, istalgan
narxni qo'yish mumkin edi. Narx faqat shu yerda hisoblanadi: texnikaning
prays-listi, ijara sanalari va yetkazib berish masofasi bo'yicha.

Formula mobil ilovadagi hisob bilan bir xil bo'lishi SHART
(rent_equipment_page.dart), aks holda mijoz ekranda bir summani ko'rib,
hisobidan boshqa summa yechiladi.
"""
from dataclasses import dataclass
from datetime import date
from decimal import Decimal, ROUND_HALF_UP
from math import asin, cos, radians, sin, sqrt
from typing import Optional

from sqlalchemy.orm import Session

from app.models.app_settings import AppSettings
from app.models.equipment import Equipment

# ---------------------------------------------------------------- komissiya
#
# Platforma ulushini TEXNIKA EGASI to'laydi: mijoz ijara va yetkazib berish
# narxini to'laydi, ulushi esa buyurtma yakunlanganda egasining pulidan
# ushlab qolinadi.
#
# Ilgari ulush mijozning summasiga USTIGA qo'shilardi. Yangi ilova uchun 10%
# ko'p, shuning uchun hozircha har qanday buyurtmadan qat'iy 5 000 so'm
# olinadi. Rejim app_settings orqali almashtiriladi, kodni tahrirlash shart
# emas.
COMMISSION_SETTING_KEY = "commission_percent"
COMMISSION_MODE_KEY = "commission_mode"
COMMISSION_FIXED_KEY = "commission_fixed"

MODE_PERCENT = "percent"
MODE_FIXED = "fixed"

DEFAULT_COMMISSION_PERCENT = Decimal("10")
DEFAULT_COMMISSION_FIXED = Decimal("5000")
DEFAULT_COMMISSION_MODE = MODE_FIXED

EARTH_RADIUS_KM = Decimal("6371")

# Maksimal ijara muddati — bir yildan uzun buyurtma xato deb qaraladi.
MAX_RENTAL_DAYS = 365


@dataclass(frozen=True)
class OrderPrice:
    """Buyurtmaning hisoblangan narxi."""
    days: int
    subtotal: Decimal          # ijara narxi (kunlik narx * kunlar)
    commission: Decimal        # platforma ulushi — EGASINING pulidan ushlanadi
    delivery_distance: Optional[Decimal]  # km
    delivery_fee: Decimal      # yetkazib berish narxi
    total: Decimal             # mijoz to'laydigan summa: ijara + yetkazish

    @property
    def owner_receives(self) -> Decimal:
        """Buyurtma yakunlanganda egasiga tushadigan summa."""
        return self.total - self.commission


def _round_to_sum(value: Decimal) -> Decimal:
    """So'mgacha yaxlitlash — mobil ilovadagi .round() bilan bir xil."""
    return value.quantize(Decimal("1"), rounding=ROUND_HALF_UP)


def _setting(db: Session, key: str) -> Optional[str]:
    row = db.query(AppSettings).filter(AppSettings.key == key).first()
    return None if row is None or row.value is None else str(row.value)


def get_commission_percent(db: Session) -> Decimal:
    """
    Komissiya foizi. Noto'g'ri yoki yo'q bo'lsa — standart 10%.
    Adminka app_settings orqali o'zgartirishi mumkin.
    """
    raw = _setting(db, COMMISSION_SETTING_KEY)
    if raw is None:
        return DEFAULT_COMMISSION_PERCENT
    try:
        percent = Decimal(raw)
    except (ArithmeticError, TypeError, ValueError):
        return DEFAULT_COMMISSION_PERCENT
    return percent if 0 <= percent <= 100 else DEFAULT_COMMISSION_PERCENT


def get_commission_fixed(db: Session) -> Decimal:
    """Qat'iy ulush, so'mda. Manfiy yoki xato qiymat — standart 5 000."""
    raw = _setting(db, COMMISSION_FIXED_KEY)
    if raw is None:
        return DEFAULT_COMMISSION_FIXED
    try:
        amount = Decimal(raw)
    except (ArithmeticError, TypeError, ValueError):
        return DEFAULT_COMMISSION_FIXED
    return amount if amount >= 0 else DEFAULT_COMMISSION_FIXED


def get_commission_mode(db: Session) -> str:
    """'fixed' yoki 'percent'. Notanish qiymat — standart rejim."""
    raw = (_setting(db, COMMISSION_MODE_KEY) or "").strip().lower()
    return raw if raw in (MODE_FIXED, MODE_PERCENT) else DEFAULT_COMMISSION_MODE


def calculate_commission(db: Session, subtotal: Decimal, total: Decimal) -> Decimal:
    """
    Platforma ulushi. Egasining pulidan ushlanadi.

    Ulush hech qachon buyurtma summasidan OSHMAYDI: aks holda arzon
    buyurtmada (masalan 3 000 so'mlik) egasining balansi minusga ketardi —
    ya'ni u ishlagani uchun pul to'lab qolardi.
    """
    if get_commission_mode(db) == MODE_FIXED:
        commission = get_commission_fixed(db)
    else:
        commission = subtotal * get_commission_percent(db) / Decimal("100")

    commission = _round_to_sum(commission)
    return min(commission, total) if total > 0 else Decimal("0")


def rental_days(start_date: date, end_date: date) -> int:
    """Ijara kunlari. Boshlanish va tugash kunlari ham hisobga olinadi."""
    return (end_date - start_date).days + 1


def distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> Decimal:
    """Haversine formulasi — ikki nuqta orasidagi masofa, km."""
    d_lat = radians(lat2 - lat1)
    d_lon = radians(lon2 - lon1)
    a = (
        sin(d_lat / 2) ** 2
        + cos(radians(lat1)) * cos(radians(lat2)) * sin(d_lon / 2) ** 2
    )
    return EARTH_RADIUS_KM * Decimal(str(2 * asin(sqrt(a))))


def _to_float(value) -> Optional[float]:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def calculate_order_price(
    db: Session,
    equipment: Equipment,
    start_date: date,
    end_date: date,
    delivery_latitude: Optional[str],
    delivery_longitude: Optional[str],
    price_per_day_override: Optional[Decimal] = None,
) -> OrderPrice:
    """
    Buyurtma narxini to'liq hisoblab beradi.

    Xato sanalar yoki narxsiz texnika uchun ValueError qaytaradi —
    chaqiruvchi uni HTTP 400 ga aylantiradi.

    price_per_day_override — zayavka bo'yicha kelishilgan kunlik narx.
    Egasi taklifda katalogdagidan boshqa narx aytishi mumkin, shuning uchun
    kerak.

    DIQQAT: bu qiymat FAQAT bazadagi request_offers yozuvidan olinadi.
    So'rov tanasidan kelgan narxni bu yerga uzatish MUMKIN EMAS — aks holda
    mijoz o'z narxini yuborib, ekskavatorni 1 000 so'mga olardi. Aynan shu
    teshik pricing_service yozilishiga sabab bo'lgan.
    """
    days = rental_days(start_date, end_date)
    if days <= 0:
        raise ValueError("Tugash sanasi boshlanish sanasidan oldin bo'lishi mumkin emas")
    if days > MAX_RENTAL_DAYS:
        raise ValueError(f"Ijara muddati {MAX_RENTAL_DAYS} kundan oshmasligi kerak")

    daily_rate = (
        price_per_day_override
        if price_per_day_override is not None
        else equipment.price_per_day
    )
    if daily_rate is None or Decimal(str(daily_rate)) <= 0:
        raise ValueError("Texnikaning kunlik narxi ko'rsatilmagan")

    subtotal = _round_to_sum(Decimal(str(daily_rate)) * days)

    # Yetkazib berish: texnika joyidan mijoz ko'rsatgan nuqtagacha.
    # Masofani ham server hisoblaydi — mijozdan kelgan qiymatga ishonmaymiz.
    delivery_distance: Optional[Decimal] = None
    delivery_fee = Decimal("0")

    eq_lat = _to_float(equipment.latitude)
    eq_lon = _to_float(equipment.longitude)
    to_lat = _to_float(delivery_latitude)
    to_lon = _to_float(delivery_longitude)

    if None not in (eq_lat, eq_lon, to_lat, to_lon):
        delivery_distance = distance_km(eq_lat, eq_lon, to_lat, to_lon).quantize(
            Decimal("0.01"), rounding=ROUND_HALF_UP
        )
        if equipment.delivery_price_per_km is not None:
            delivery_fee = _round_to_sum(
                delivery_distance * Decimal(str(equipment.delivery_price_per_km))
            )

    # Mijoz FAQAT ijara va yetkazib berish uchun to'laydi. Platforma ulushi
    # bu summaga qo'shilmaydi — u buyurtma yakunlanganda egasining pulidan
    # ushlab qolinadi.
    total = subtotal + delivery_fee

    # Ulush umumiy summadan oshmasligi uchun uni total bilan solishtiramiz
    commission = calculate_commission(db, subtotal, total)

    return OrderPrice(
        days=days,
        subtotal=subtotal,
        commission=commission,
        delivery_distance=delivery_distance,
        delivery_fee=delivery_fee,
        total=total,
    )
