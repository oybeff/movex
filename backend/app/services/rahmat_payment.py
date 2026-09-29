"""
Rahmat to'lovlarining BIZNING tomondagi qismi: balans, tranzaksiya holati,
idempotentlik.

`rahmat_service.py` shlyuz bilan gaplashadi va bazani bilmaydi. Bu fayl
esa teskarisi: shlyuzdan kelgan holatni tranzaksiyaga va balansga
tushiradi. Ajratilgani bilib turib: to'lov tizimining protokoli
o'zgarganda pul harakati qoidalariga tegmaslik kerak, va aksincha.

Holat o'zgarishi UCH yo'l bilan keladi va uchalasi ham bitta funksiyaga
tushadi (`apply_gateway_state`):

    callback  — muvaffaqiyatli to'lovdan keyin bir marta
    webhook   — har bir holat o'zgarishida
    sync      — o'zimiz so'raganda (GET /payment/{uuid})

Bitta funksiya ataylab: uch joyda uchta nusxa bo'lsa, bittasida
"allaqachon to'langan" tekshiruvi unutilardi va bir to'lov balansga ikki
marta tushardi. Multicard esa callback'ni QAYTA yuborishi mumkin —
hujjat buni to'g'ridan-to'g'ri aytadi va idempotentlikni talab qiladi.
"""
from __future__ import annotations

import logging
from decimal import Decimal
from typing import Any, Dict, Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.messages import t
from app.models.balance import Balance, BalanceTransaction
from app.services import rahmat_service
from app.services.rahmat_service import RahmatError

logger = logging.getLogger(__name__)


def _user(db: Session, user_id: int):
    from app.models.user import User

    return db.query(User).filter(User.id == user_id).first()


def _language(db: Session, user_id: int) -> Optional[str]:
    user = _user(db, user_id)
    return user.language if user else None


# ------------------------------------------------------------- to'lov boshi

def start_topup(db: Session, transaction: BalanceTransaction) -> str:
    """
    Shlyuzda invoys yaratadi va chekaut havolasini qaytaradi.

    `uuid` DARHOL tranzaksiyaga yoziladi. Usiz keyin kelgan vebhuk (unda
    faqat uuid bor, invoice_id esa har doim emas) qaysi to'lov ekanini
    aniqlay olmaydi.
    """
    language = _language(db, transaction.user_id)
    # Chek satridagi nom — foydalanuvchi tilida: chek unga ko'rinadi.
    name = t("tx.topup", language, method="Rahmat")

    user = _user(db, transaction.user_id)
    phone = transaction.phone_number or (user.phone if user else None)

    try:
        data = rahmat_service.create_invoice(
            invoice_id=str(transaction.id),
            amount_sum=transaction.amount,
            lang=language or "uz",
            ofd=rahmat_service.build_ofd(db, transaction.amount, name),
            phone=phone,
        )
    except RahmatError as exc:
        logger.error(
            "Rahmat invoys yaratilmadi: tx=%s code=%s details=%s",
            transaction.id, exc.code, exc.details,
        )
        raise HTTPException(
            status_code=503,
            detail=f"To'lov tizimi javob bermadi ({exc.code}). Keyinroq urinib ko'ring.",
        )

    checkout_url = data.get("checkout_url")
    uuid = data.get("uuid")
    if not checkout_url or not uuid:
        logger.error("Rahmat javobida checkout_url yoki uuid yo'q: %s", data)
        raise HTTPException(status_code=503, detail="To'lov tizimi noto'g'ri javob qaytardi")

    transaction.rahmat_uuid = uuid
    transaction.rahmat_checkout_url = checkout_url
    payment = data.get("payment") if isinstance(data.get("payment"), dict) else {}
    transaction.rahmat_status = payment.get("status") or rahmat_service.STATUS_DRAFT
    db.commit()
    db.refresh(transaction)

    return checkout_url


# ------------------------------------------------------- holatni qo'llash

def find_transaction(
    db: Session,
    *,
    uuid: Optional[str] = None,
    invoice_id: Optional[str] = None,
) -> Optional[BalanceTransaction]:
    """
    Tranzaksiyani uuid yoki invoice_id bo'yicha topish.

    uuid ustuvor: u shlyuzning o'z raqami va hech qachon takrorlanmaydi.
    invoice_id — bizning tranzaksiya raqami, u faqat zaxira yo'l (birinchi
    callback uuid saqlanishidan oldin kelib qolsa).
    """
    if uuid:
        found = (
            db.query(BalanceTransaction)
            .filter(BalanceTransaction.rahmat_uuid == str(uuid))
            .first()
        )
        if found:
            return found

    if invoice_id is not None:
        try:
            transaction_id = int(str(invoice_id).strip())
        except (TypeError, ValueError):
            return None
        # Faqat hisob to'ldirish: invoice_id — oddiy son, va u boshqa
        # turdagi tranzaksiyaga (masalan buyurtma to'loviga) tushib
        # qolsa, unga tashqaridan "to'landi" deb yozib bo'lardi.
        return (
            db.query(BalanceTransaction)
            .filter(
                BalanceTransaction.id == transaction_id,
                BalanceTransaction.type == "topup",
            )
            .first()
        )

    return None


def _credit(db: Session, transaction: BalanceTransaction) -> None:
    """Balansni to'ldirish. Qator bloklangan holda chaqiriladi."""
    from app.services.balance_service import get_or_create_balance

    get_or_create_balance(db, transaction.user_id)
    balance = (
        db.query(Balance)
        .filter(Balance.user_id == transaction.user_id)
        .with_for_update()
        .one()
    )
    balance.balance = Decimal(str(balance.balance)) + Decimal(str(transaction.amount))


def _debit_reverted(db: Session, transaction: BalanceTransaction) -> None:
    """
    Qaytarilgan (revert) to'lov: tushgan pulni balansdan olib tashlaymiz.

    Balansda yetarli pul bo'lmasligi mumkin — odam uni allaqachon
    sarflagan bo'lsa. Bunday holatda balansni MANFIY qilmaymiz (CHECK
    cheklovi ruxsat bermaydi va u to'g'ri), qancha bor — shuncha
    yechamiz, qolganini logga yozamiz: bu qo'lda hal qilinadigan holat.
    Jim qoldirish esa eng yomoni — pul qaytarilgan, tovon esa bizda.
    """
    from app.services.balance_service import get_or_create_balance

    get_or_create_balance(db, transaction.user_id)
    balance = (
        db.query(Balance)
        .filter(Balance.user_id == transaction.user_id)
        .with_for_update()
        .one()
    )
    amount = Decimal(str(transaction.amount))
    available = Decimal(str(balance.balance)) - Decimal(str(balance.frozen_balance))
    taken = amount if available >= amount else max(available, Decimal("0"))

    balance.balance = Decimal(str(balance.balance)) - taken
    if taken < amount:
        logger.error(
            "Rahmat to'lovi qaytarildi, lekin balansda pul yetmadi: "
            "tx=%s user=%s kerak=%s yechildi=%s",
            transaction.id, transaction.user_id, amount, taken,
        )

    language = _language(db, transaction.user_id)
    db.add(
        BalanceTransaction(
            user_id=transaction.user_id,
            amount=taken if taken > 0 else amount,
            type="refund",
            status="completed",
            payment_method=transaction.payment_method,
            description=t("tx.topup_reverted", language, transaction_id=transaction.id),
        )
    )


def _notify_telegram(db: Session, transaction: BalanceTransaction) -> None:
    """Guruhga xabar. Xatosi to'lovga ta'sir qilmaydi, lekin jim ketmaydi."""
    try:
        from app.services.telegram_service import telegram_service

        user = _user(db, transaction.user_id)
        name = getattr(user, "full_name", None) or getattr(user, "username", None) or "—"
        telegram_service.send_payment_notification(
            user_name=name,
            phone_number=transaction.phone_number or getattr(user, "phone", None) or "N/A",
            amount=float(transaction.amount),
            transaction_id=transaction.id,
            payment_method="Rahmat",
        )
    except Exception:
        logger.exception("Telegram xabari yuborilmadi: tx=%s", transaction.id)


def apply_gateway_state(
    db: Session,
    transaction: BalanceTransaction,
    *,
    gateway_status: Optional[str],
    amount_tiyin: Optional[int] = None,
    uuid: Optional[str] = None,
    card_pan: Optional[str] = None,
    ps: Optional[str] = None,
    billing_id: Optional[str] = None,
    receipt_url: Optional[str] = None,
    payment_time: Optional[str] = None,
) -> str:
    """
    Shlyuz holatini tranzaksiyaga tushiradi. Bizning yangi holatni qaytaradi.

    IDEMPOTENT: allaqachon to'langan tranzaksiyaga ikkinchi marta
    "success" kelsa, balans QAYTA to'ldirilmaydi. Multicard callback'ni
    takrorlashi mumkin (timeout yoki HTTP 500 dan keyin), shuning uchun
    bu shart, tavsiya emas.

    Summa tekshiriladi: kelgan summa tranzaksiyadagiga mos kelmasa,
    hech narsa o'zgartirilmaydi. Aks holda soxta callback bilan 1 000
    so'mlik invoysga 10 000 000 yozib olish mumkin bo'lardi.
    """
    if amount_tiyin is not None:
        expected = rahmat_service.to_tiyin(transaction.amount)
        if int(amount_tiyin) != expected:
            raise ValueError(
                f"summa mos kelmadi: kutilgan {expected} tiyin, kelgan {amount_tiyin}"
            )

    # Qatorni bloklaymiz: bir vaqtda kelgan callback va vebhuk bitta
    # to'lovni ikki marta hisoblamasligi kerak.
    locked = (
        db.query(BalanceTransaction)
        .filter(BalanceTransaction.id == transaction.id)
        .with_for_update()
        .one()
    )

    if uuid and not locked.rahmat_uuid:
        locked.rahmat_uuid = str(uuid)
    if gateway_status:
        locked.rahmat_status = str(gateway_status)
    if card_pan:
        locked.rahmat_card_pan = str(card_pan)[:32]
    if ps:
        locked.rahmat_ps = str(ps)[:20]
    if billing_id:
        locked.rahmat_billing_id = str(billing_id)[:64]
    if receipt_url:
        locked.rahmat_receipt_url = str(receipt_url)[:500]
    if payment_time:
        locked.rahmat_payment_time = str(payment_time)[:32]

    target = rahmat_service.map_status(gateway_status)
    previous = locked.status

    if target == "completed":
        if previous != "completed":
            locked.status = "completed"
            _credit(db, locked)
            db.commit()
            _notify_telegram(db, locked)
        else:
            db.commit()

    elif target == "failed":
        if previous == "completed":
            # Pul tushgan, keyin "error" kelgan — o'zi bo'lmaydigan holat.
            # Pulga TEGMAYMIZ: xato xabarga ishonib balansdan yechish,
            # agar xabar noto'g'ri bo'lsa, o'g'irlik bo'lardi.
            logger.error(
                "Rahmat: to'langan tranzaksiyaga 'error' keldi, pul tegilmadi: tx=%s",
                locked.id,
            )
            db.commit()
        else:
            locked.status = "failed"
            db.commit()

    elif target == "canceled":
        if previous == "completed":
            locked.status = "canceled"
            _debit_reverted(db, locked)
        else:
            locked.status = "canceled"
        db.commit()

    else:
        # draft / progress / billing / hold — pul hali bizga tegishli emas
        db.commit()

    db.refresh(locked)
    return locked.status


def sync_transaction(db: Session, transaction: BalanceTransaction) -> str:
    """
    Holatni shlyuzdan so'rab aniqlash.

    Ilova to'lov sahifasidan qaytganda shuni chaqiradi: callback yo'lda
    kechikkan yoki umuman yo'qolgan bo'lishi mumkin, odam esa ekranda
    "pul tushmadi" ko'rib turadi. Haqiqatning manbasi — shlyuz.
    """
    if not transaction.rahmat_uuid:
        return transaction.status

    try:
        data = rahmat_service.get_payment(transaction.rahmat_uuid)
    except RahmatError as exc:
        logger.warning(
            "Rahmat holati so'ralmadi: tx=%s code=%s", transaction.id, exc.code
        )
        return transaction.status

    return apply_gateway_state(
        db,
        transaction,
        gateway_status=data.get("status"),
        amount_tiyin=data.get("payment_amount"),
        card_pan=data.get("card_pan"),
        ps=data.get("ps"),
        billing_id=data.get("billing_id"),
        receipt_url=data.get("receipt_url"),
        payment_time=data.get("payment_time"),
    )


def refund_topup(db: Session, transaction: BalanceTransaction) -> Dict[str, Any]:
    """
    To'lovni kartaga qaytarish.

    Balans `apply_gateway_state` orqali tuzatiladi — shlyuz 'revert'
    holatini qaytaradi va pul harakati qoidasi bitta joyda qoladi.
    """
    if not transaction.rahmat_uuid:
        raise HTTPException(status_code=400, detail="Bu tranzaksiya Rahmat orqali o'tmagan")

    try:
        data = rahmat_service.refund(transaction.rahmat_uuid)
    except RahmatError as exc:
        raise HTTPException(status_code=502, detail=f"{exc.code}: {exc.details}")

    apply_gateway_state(
        db,
        transaction,
        gateway_status=data.get("status") or rahmat_service.STATUS_REVERT,
    )
    return data
