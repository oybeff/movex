"""
Texnika egasining pul yechishi.

Pul harakati qat'iy: ariza berilganda summa muzlatiladi, to'langanda
balansdan yechiladi, rad etilganda muzlatish qaytariladi. Muzlatish
kerak, aks holda ega bir xil pulni bir necha marta so'rab olishi mumkin.

Pul yechishdan platforma ulushi ushlab qolinadi va uni TEXNIKA EGASI
to'laydi. Sabab oddiy: bir buyurtmadan atigi 5 000 so'm olinadi, va bu
summa pulni kartaga o'tkazish uchun to'lov tizimi oladigan foizni
qoplamaydi.

Ulush ariza summasidan ICHIDAN ushlanadi: 100 000 so'radi — balansidan
100 000 yechiladi, kartaga 95 000 tushadi. Shuning uchun ega balansini
oxirgi so'migacha yecha oladi; ustiga qo'shilganda esa to'liq balansni
yechishning iloji bo'lmasdi.
"""
from decimal import Decimal, ROUND_HALF_UP
from typing import List, Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.account_state import assert_not_frozen
from app.core.messages import t
from app.models.app_settings import AppSettings
from app.models.balance import Balance, BalanceTransaction
from app.models.payout_request import PayoutRequest
from app.schemas.payout import PayoutRequestCreate
from app.services.balance_service import get_or_create_balance, withdrawable_balance

MIN_PAYOUT_SUM = Decimal("50000")

# ------------------------------------------------------------- komissiya
#
# Tuzilishi buyurtma komissiyasi bilan bir xil (pricing_service.py):
# rejim + ikkala qiymat. Ikkovi bir vaqtda ishlamaydi — rejim qaysi biri
# amal qilishini belgilaydi. Adminkadan almashtiriladi, kodni tahrirlash
# shart emas.
PAYOUT_COMMISSION_MODE_KEY = "payout_commission_mode"
PAYOUT_COMMISSION_FIXED_KEY = "payout_commission_fixed"
PAYOUT_COMMISSION_PERCENT_KEY = "payout_commission_percent"

MODE_FIXED = "fixed"
MODE_PERCENT = "percent"

DEFAULT_PAYOUT_COMMISSION_MODE = MODE_FIXED
DEFAULT_PAYOUT_COMMISSION_FIXED = Decimal("5000")
DEFAULT_PAYOUT_COMMISSION_PERCENT = Decimal("10")


def _setting(db: Session, key: str) -> Optional[str]:
    row = db.query(AppSettings).filter(AppSettings.key == key).first()
    return None if row is None or row.value is None else str(row.value)


def get_commission_mode(db: Session) -> str:
    """'fixed' yoki 'percent'. Notanish qiymat — standart rejim."""
    raw = (_setting(db, PAYOUT_COMMISSION_MODE_KEY) or "").strip().lower()
    return raw if raw in (MODE_FIXED, MODE_PERCENT) else DEFAULT_PAYOUT_COMMISSION_MODE


def get_commission_fixed(db: Session) -> Decimal:
    """Qat'iy ushlanma, so'mda. Manfiy yoki xato qiymat — standart 5 000."""
    raw = _setting(db, PAYOUT_COMMISSION_FIXED_KEY)
    if raw is None:
        return DEFAULT_PAYOUT_COMMISSION_FIXED
    try:
        amount = Decimal(raw)
    except (ArithmeticError, TypeError, ValueError):
        return DEFAULT_PAYOUT_COMMISSION_FIXED
    return amount if amount >= 0 else DEFAULT_PAYOUT_COMMISSION_FIXED


def get_commission_percent(db: Session) -> Decimal:
    """Ushlanma foizi. Xato yoki chegaradan tashqari qiymat — standart 10%."""
    raw = _setting(db, PAYOUT_COMMISSION_PERCENT_KEY)
    if raw is None:
        return DEFAULT_PAYOUT_COMMISSION_PERCENT
    try:
        percent = Decimal(raw)
    except (ArithmeticError, TypeError, ValueError):
        return DEFAULT_PAYOUT_COMMISSION_PERCENT
    return percent if 0 <= percent <= 100 else DEFAULT_PAYOUT_COMMISSION_PERCENT


def calculate_commission(db: Session, amount: Decimal) -> Decimal:
    """
    Pul yechishdan ushlanadigan summa.

    Ushlanma ariza summasidan OSHMAYDI: aks holda kartaga manfiy summa
    tushib qolardi. Buyurtma komissiyasida ham xuddi shu qoida.
    """
    if get_commission_mode(db) == MODE_FIXED:
        commission = get_commission_fixed(db)
    else:
        commission = amount * get_commission_percent(db) / Decimal("100")

    commission = commission.quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    if commission < 0:
        return Decimal("0")
    return min(commission, amount)


def _money(value: Decimal) -> str:
    """95000 -> "95 000". Izohda summa o'qiladigan ko'rinishda turishi kerak."""
    return f"{int(value):,}".replace(",", " ")


def _user_language(db: Session, user_id: int):
    """Izoh egasining tilida yoziladi — u "Amallar tarixi"da shundayligicha turadi."""
    from app.models.user import User
    user = db.query(User).filter(User.id == user_id).first()
    return user.language if user else None


def create_request(db: Session, user_id: int, data: PayoutRequestCreate) -> PayoutRequest:
    # Muzlatilgan hisob pul yecha olmaydi — nizoli holatlar aynan shuning
    # uchun muzlatiladi.
    from app.models.user import User
    assert_not_frozen(db.query(User).filter(User.id == user_id).first())
    amount = Decimal(str(data.amount)).quantize(Decimal("0.01"))

    if amount < MIN_PAYOUT_SUM:
        raise HTTPException(
            status_code=400,
            detail=f"Eng kam yechish summasi {int(MIN_PAYOUT_SUM):,} so'm".replace(",", " "),
        )

    get_or_create_balance(db, user_id)

    # Qatorni bloklaymiz: bir vaqtda kelgan ikki ariza bitta pulni
    # ikki marta band qilib qo'ymasligi kerak.
    balance = (
        db.query(Balance)
        .filter(Balance.user_id == user_id)
        .with_for_update()
        .one()
    )
    # Sovg'a pulini YECHIB BO'LMAYDI — u summadan chiqarib tashlanadi.
    available = withdrawable_balance(balance)

    if available < amount:
        bonus = Decimal(str(balance.bonus_balance or 0))
        detail = (
            f"Yetarli mablag' yo'q. Yechish mumkin: {float(available)} so'm, "
            f"so'ralgan: {float(amount)} so'm"
        )
        if bonus > 0:
            # Aks holda odam balansida 50 000 turganini ko'rib, nega
            # yechilmayotganini tushunmasdi.
            detail += (
                f". Sovg'a puli ({float(bonus)} so'm) faqat ilova ichida "
                f"ishlatiladi, kartaga yechilmaydi"
            )
        raise HTTPException(status_code=400, detail=detail)

    # Ushlanma ariza berilgan paytdagi sozlama bo'yicha hisoblanadi va
    # o'sha holicha saqlanadi: admin ertaga foizni o'zgartirsa, kecha
    # berilgan ariza qayta hisoblanib ketmasligi kerak.
    commission = calculate_commission(db, amount)
    payout_amount = amount - commission

    if payout_amount <= 0:
        # Ushlanma butun summani yeb qo'ygan holat. Bunday arizani qabul
        # qilish — egadan pulni olib, evaziga hech narsa bermaslik.
        raise HTTPException(
            status_code=400,
            detail=(
                f"Komissiya ({int(commission):,} so'm) so'ralgan summadan kam "
                f"emas. Kattaroq summa kiriting.".replace(",", " ")
            ),
        )

    balance.frozen_balance = Decimal(str(balance.frozen_balance)) + amount

    request = PayoutRequest(
        user_id=user_id,
        amount=amount,
        commission=commission,
        payout_amount=payout_amount,
        status="pending",
        card_number=data.card_number,
        card_holder=data.card_holder,
        comment=data.comment,
    )
    db.add(request)
    db.commit()
    db.refresh(request)
    return request


def list_for_user(db: Session, user_id: int) -> List[PayoutRequest]:
    return (
        db.query(PayoutRequest)
        .filter(PayoutRequest.user_id == user_id)
        .order_by(PayoutRequest.created_at.desc())
        .all()
    )


def list_all(db: Session, status: Optional[str] = None, skip: int = 0, limit: int = 100) -> List[PayoutRequest]:
    query = db.query(PayoutRequest)
    if status:
        query = query.filter(PayoutRequest.status == status)
    return query.order_by(PayoutRequest.created_at.desc()).offset(skip).limit(limit).all()


def _load_pending(db: Session, request_id: int) -> PayoutRequest:
    request = db.query(PayoutRequest).filter(PayoutRequest.id == request_id).first()
    if request is None:
        raise HTTPException(status_code=404, detail="Ariza topilmadi")
    if request.status != "pending":
        raise HTTPException(
            status_code=400,
            detail=f"Ariza allaqachon ko'rib chiqilgan: {request.status}",
        )
    return request


def mark_paid(db: Session, request_id: int, admin_id: int, admin_comment: Optional[str] = None) -> PayoutRequest:
    """Pul o'tkazildi: balansdan yechamiz va muzlatishni olib tashlaymiz."""
    from datetime import datetime, timezone

    request = _load_pending(db, request_id)
    amount = Decimal(str(request.amount))

    balance = (
        db.query(Balance)
        .filter(Balance.user_id == request.user_id)
        .with_for_update()
        .one()
    )

    if Decimal(str(balance.frozen_balance)) < amount or Decimal(str(balance.balance)) < amount:
        raise HTTPException(
            status_code=400,
            detail="Balansdagi ma'lumot arizaga mos kelmaydi, qo'lda tekshiring",
        )

    balance.frozen_balance = Decimal(str(balance.frozen_balance)) - amount
    balance.balance = Decimal(str(balance.balance)) - amount

    # Balansdan to'liq summa yechiladi, kartaga esa komissiyasiz qismi
    # o'tkaziladi — farqi platformada qoladi. Izohda ikkalasi ham
    # ko'rsatiladi, aks holda ega yo'qolgan pulni izlab qolardi.
    commission = Decimal(str(request.commission or 0))
    net = Decimal(str(request.payout_amount or amount))
    language = _user_language(db, request.user_id)

    if commission > 0:
        description = t(
            "tx.payout_with_commission",
            language,
            request_id=request.id,
            card=request.card_masked,
            net=_money(net),
            commission=_money(commission),
        )
    else:
        description = t(
            "tx.payout",
            language,
            request_id=request.id,
            card=request.card_masked,
        )

    db.add(
        BalanceTransaction(
            user_id=request.user_id,
            amount=amount,
            type="withdrawal",
            status="completed",
            # Izoh egasining "Amallar tarixi"ga tushadi — uning tilida.
            description=description,
        )
    )

    request.status = "paid"
    request.processed_by = admin_id
    request.processed_at = datetime.now(timezone.utc)
    request.admin_comment = admin_comment

    db.commit()
    db.refresh(request)
    return request


def reject(db: Session, request_id: int, admin_id: int, admin_comment: Optional[str] = None) -> PayoutRequest:
    """Rad etildi: pul egasida qoladi, faqat muzlatish olib tashlanadi."""
    from datetime import datetime, timezone

    request = _load_pending(db, request_id)
    amount = Decimal(str(request.amount))

    balance = (
        db.query(Balance)
        .filter(Balance.user_id == request.user_id)
        .with_for_update()
        .one()
    )
    frozen = Decimal(str(balance.frozen_balance))
    # Muzlatish qandaydir sababga ko'ra kamayib qolgan bo'lsa, manfiy qilmaymiz
    balance.frozen_balance = frozen - amount if frozen >= amount else Decimal("0")

    request.status = "rejected"
    request.processed_by = admin_id
    request.processed_at = datetime.now(timezone.utc)
    request.admin_comment = admin_comment

    db.commit()
    db.refresh(request)
    return request
