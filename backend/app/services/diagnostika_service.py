"""
Diagnostika — narxi qat'iy xizmat, tez buyurtma (mode='quick') sifatida.

Oddiy tez buyurtmadan farqi bitta: narxni MIJOZ EMAS, SERVER qo'yadi.
Narx app_settings.diagnostika_price_amount da (adminkadagi commission.php),
bo'lmasa — 50 000. Mijoz yuborgan budget e'tiborga olinmaydi: aks holda
"diagnostika" 1 000 so'mga buyurtma qilinardi.

Pulning qolgan hayoti — tez buyurtmaniki: yaratilganda muzlatiladi, ega
olganda buyurtmaga o'tadi, yakunlanganda egaga umumiy komissiya
(pricing_service.calculate_commission) ayirilib tushadi. Alohida stavka
yo'q va bo'lmasligi kerak — ikkitasi bir-biridan ajralib ketardi.
"""
from decimal import Decimal, InvalidOperation

from sqlalchemy.orm import Session

from app.models.app_settings import AppSettings

PRICE_KEY = "diagnostika_price_amount"
DEFAULT_PRICE = Decimal("50000")


def get_price(db: Session) -> Decimal:
    """Diagnostika narxi, so'm. Bo'sh, xato yoki 0 dan kichik — standart."""
    row = db.query(AppSettings).filter(AppSettings.key == PRICE_KEY).first()
    if row is None or row.value in (None, ""):
        return DEFAULT_PRICE
    try:
        value = Decimal(str(row.value))
    except (InvalidOperation, TypeError, ValueError):
        return DEFAULT_PRICE
    # 0 bo'lishi mumkin emas: tez buyurtmada narx > 0 (CHECK bazada ham bor)
    return value if value > 0 else DEFAULT_PRICE
