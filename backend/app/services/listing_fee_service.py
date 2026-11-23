"""
E'lon joylash uchun to'lov.

Faqat "E'lonlar" bo'limi (listings) — katalogga texnika qo'shish va
stroymateriallar bepul qoladi (egasi shunday tanladi).

Narx ikki darajali:
- umumiy — app_settings.listing_fee_amount, adminkadagi commission.php;
  0 yoki bo'sh — hamma uchun bepul;
- shaxsiy — users.listing_fee_override, users.php: NULL — umumiy narx,
  0 — shu odam uchun bepul, >0 — o'z narxi.

Pul balansdan e'lon YARATILGANDA yechiladi, xuddi shu tranzaksiyada:
e'lon saqlanmasa, pul ham yechilmaydi. Sovg'a ham ishlatiladi — avval
o'z puli, keyin sovg'a (bu qoidani models/balance.py dagi before_flush
ushlab turadi). Daromad budget_reserves ga e'lon bilan bog'lanib yoziladi —
adminkadagi budget.php da komissiyalar yonida ko'rinadi.
"""
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.messages import t
from app.models.balance import Balance, BalanceTransaction
from app.models.budget_reserve import BudgetReserve

LISTING_FEE_KEY = "listing_fee_amount"
TX_TYPE_LISTING_FEE = "listing_fee"


def general_fee(db: Session) -> Decimal:
    # E'lon joylash mutlaqo bepul (0 so'm)
    return Decimal("0")


def fee_for(db: Session, user) -> Decimal:
    # E'lon joylash mutlaqo bepul (0 so'm)
    return Decimal("0")


def charge(db: Session, user, listing) -> Decimal:
    """Narxni yechadi (0 bo'lsa — hech narsa). Pul yetmasa 402."""
    fee = fee_for(db, user)
    if fee <= 0:
        return Decimal("0")

    balance = (
        db.query(Balance).filter(Balance.user_id == user.id).with_for_update().first()
    )
    available = Decimal("0")
    if balance is not None:
        available = Decimal(str(balance.balance)) - Decimal(str(balance.frozen_balance))
    if balance is None or available < fee:
        raise HTTPException(
            status_code=402,
            detail=t("listing_fee.insufficient", user.language, fee=f"{fee:,.0f}".replace(",", " ")),
        )

    balance.balance = Decimal(str(balance.balance)) - fee
    db.add(BalanceTransaction(
        user_id=user.id,
        amount=fee,
        type=TX_TYPE_LISTING_FEE,
        status="completed",
        description=t("tx.listing_fee", user.language, title=listing.title),
    ))
    db.add(BudgetReserve(
        listing_id=listing.id,
        amount=fee,
        description=t("tx.listing_fee", None, title=listing.title),
    ))
    return fee
