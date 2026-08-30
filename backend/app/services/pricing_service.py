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

# Komissiya foizi app_settings jadvalidan olinadi, u yerda bo'lmasa — shu qiymat.
COMMISSION_SETTING_KEY = "commission_percent"
DEFAULT_COMMISSION_PERCENT = Decimal("10")

EARTH_RADIUS_KM = Decimal("6371")

# Maksimal ijara muddati — bir yildan uzun buyurtma xato deb qaraladi.
MAX_RENTAL_DAYS = 365


@dataclass(frozen=True)
class OrderPrice:
    """Buyurtmaning hisoblangan narxi."""
    days: int
    subtotal: Decimal          # ijara narxi (kunlik narx * kunlar)
    commission: Decimal        # platforma ulushi, faqat ijaradan
    delivery_distance: Optional[Decimal]  # km
    delivery_fee: Decimal      # yetkazib berish narxi
    total: Decimal             # mijoz to'laydigan umumiy summa


def _round_to_sum(value: Decimal) -> Decimal:
    """So'mgacha yaxlitlash — mobil ilovadagi .round() bilan bir xil."""
    return value.quantize(Decimal("1"), rounding=ROUND_HALF_UP)


def get_commission_percent(db: Session) -> Decimal:
    """
    Komissiya foizi. Noto'g'ri yoki yo'q bo'lsa — standart 10%.
    Adminka app_settings orqali o'zgartirishi mumkin.
    """
    row = (
        db.query(AppSettings)
        .filter(AppSettings.key == COMMISSION_SETTING_KEY)
        .first()
    )
    if row is None or row.value is None:
        return DEFAULT_COMMISSION_PERCENT

    try:
        percent = Decimal(str(row.value))
    except (ArithmeticError, TypeError, ValueError):
        return DEFAULT_COMMISSION_PERCENT

    if percent < 0 or percent > 100:
        return DEFAULT_COMMISSION_PERCENT
    return percent


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

    percent = get_commission_percent(db)
    commission = _round_to_sum(subtotal * percent / Decimal("100"))

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

    total = subtotal + commission + delivery_fee

    return OrderPrice(
        days=days,
        subtotal=subtotal,
        commission=commission,
        delivery_distance=delivery_distance,
        delivery_fee=delivery_fee,
        total=total,
    )
