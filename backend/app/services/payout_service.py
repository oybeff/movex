"""
Texnika egasining pul yechishi.

Pul harakati qat'iy: ariza berilganda summa muzlatiladi, to'langanda
balansdan yechiladi, rad etilganda muzlatish qaytariladi. Muzlatish
kerak, aks holda ega bir xil pulni bir necha marta so'rab olishi mumkin.
"""
from decimal import Decimal
from typing import List, Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.account_state import assert_not_frozen
from app.core.messages import t
from app.models.balance import Balance, BalanceTransaction
from app.models.payout_request import PayoutRequest
from app.schemas.payout import PayoutRequestCreate
from app.services.balance_service import get_or_create_balance

MIN_PAYOUT_SUM = Decimal("50000")


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
    available = Decimal(str(balance.balance)) - Decimal(str(balance.frozen_balance))

    if available < amount:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Yetarli mablag' yo'q. Mavjud: {float(available)} so'm, "
                f"so'ralgan: {float(amount)} so'm"
            ),
        )

    balance.frozen_balance = Decimal(str(balance.frozen_balance)) + amount

    request = PayoutRequest(
        user_id=user_id,
        amount=amount,
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

    db.add(
        BalanceTransaction(
            user_id=request.user_id,
            amount=amount,
            type="withdrawal",
            status="completed",
            # Izoh egasining "Amallar tarixi"ga tushadi — uning tilida.
            description=t(
                "tx.payout",
                _user_language(db, request.user_id),
                request_id=request.id,
                card=request.card_masked,
            ),
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
