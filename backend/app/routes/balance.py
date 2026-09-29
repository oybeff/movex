"""
Balans: to'ldirish, tarix va Rahmat (Multicard) callback'lari.

Callback manzillari OCHIQ (tokensiz) — ularga to'lov tizimi murojaat
qiladi. Shuning uchun har birida imzo tekshiriladi va summa
tranzaksiyadagi summa bilan solishtiriladi. Imzosiz manzil = istalgan
odam istalgan balansni to'ldirib olishi.
"""
import logging
from typing import Any, Dict, List

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.dependencies import get_db, get_current_user
from app.schemas import balance as balance_schema
from app.services import balance_service, rahmat_payment, rahmat_service

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/me", response_model=balance_schema.BalanceRead)
def get_my_balance(
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    """Joriy foydalanuvchi balansini olish"""
    balance = balance_service.get_balance(db, current_user.id)
    return balance


@router.get("/methods", response_model=List[balance_schema.PaymentMethodRead])
def payment_methods():
    """
    Ilova ko'rsatadigan to'lov usullari.

    Ro'yxat SERVERDAN keladi, ilovada yozib qo'yilmaydi: yig'ilgan APK'da
    qotib qolgan ro'yxat sozlamalar o'zgarganda yolg'on bo'lib qolardi.
    Sozlanmagan tizim ro'yxatga tushmaydi — bosilganda 503 beradigan
    tugmani ko'rsatishdan ma'no yo'q.
    """
    from app.services import payment_providers

    return [
        balance_schema.PaymentMethodRead(code=provider.code, title=provider.title)
        for provider in payment_providers.PROVIDERS
        if provider.is_configured()
    ]


@router.post("/topup", response_model=balance_schema.BalanceTopUpResponse)
def top_up_balance(
    transaction_data: balance_schema.BalanceTransactionCreate,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    """
    Hisob to'ldirish.

    Tranzaksiya 'pending' holatda yaratiladi va shlyuzda invoys ochiladi.
    Balans faqat to'lov tasdiqlangandan keyin to'ldiriladi.
    """
    transaction = balance_service.top_up_balance(db, current_user.id, transaction_data)

    payment_url = balance_service.start_payment(db, transaction)

    return {
        "transaction_id": transaction.id,
        "amount": float(transaction.amount),
        "payment_method": transaction.payment_method,
        "status": transaction.status,
        "payment_url": payment_url,
    }


@router.get("/transactions", response_model=List[balance_schema.BalanceTransactionRead])
def get_transaction_history(
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    """Hisob to'ldirish va to'lovlar tarixini olish"""
    transactions = balance_service.get_transactions(db, current_user.id, skip, limit)
    return transactions


@router.get("/transactions/{transaction_id}", response_model=balance_schema.BalanceTransactionRead)
def get_transaction(
    transaction_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    """Bitta tranzaksiyani olish"""
    transaction = balance_service.get_transaction(db, transaction_id, current_user.id)
    if not transaction:
        raise HTTPException(status_code=404, detail="Transaction not found")
    return transaction


@router.post("/transactions/{transaction_id}/sync", response_model=balance_schema.BalanceTransactionRead)
def sync_transaction(
    transaction_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    """
    Holatni to'lov tizimidan so'rab aniqlash.

    Ilova to'lov sahifasidan qaytgach shuni chaqiradi. Callback yo'lda
    kechikishi yoki tunnel uzilib, umuman kelmasligi mumkin — bunda odam
    pulini to'lagan, ekranda esa "kutilmoqda" turardi. Haqiqatning manbasi
    shlyuz, shuning uchun so'rab olamiz.

    E'tibor: bu yo'l "/transactions/{id}" dan KEYIN, lekin oxirida "/sync"
    borligi uchun ular chalkashmaydi.
    """
    transaction = balance_service.get_transaction(db, transaction_id, current_user.id)
    if not transaction:
        raise HTTPException(status_code=404, detail="Transaction not found")

    rahmat_payment.sync_transaction(db, transaction)
    db.refresh(transaction)
    return transaction


@router.put("/transactions/{transaction_id}", response_model=balance_schema.BalanceTransactionRead)
def update_transaction(
    transaction_id: int,
    transaction_update: balance_schema.BalanceTransactionUpdate,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    """Tranzaksiyani yangilash (faqat admin uchun)"""
    transaction = balance_service.update_transaction(
        db, transaction_id, current_user.id, transaction_update
    )
    if not transaction:
        raise HTTPException(status_code=404, detail="Transaction not found")
    return transaction


# ============================================================
# Rahmat (Multicard) callback'lari
# ============================================================
#
# Ikkisi ham OCHIQ manzil: murojaat qiluvchi — to'lov tizimi, unda
# bizning tokenimiz yo'q. Himoya imzoda.
#
# Javob shakli hujjat talabiga bo'ysunadi va bu muhim:
#   callback (success) — HTTP 200 va success=true bo'lmasa, Multicard
#   TO'LOVNI BEKOR QILADI (pul plateljchiga qaytadi). Ya'ni bizning
#   xatomiz odamning to'lovini buzadi, shuning uchun har qanday
#   kutilmagan holatda ham aniq javob qaytaramiz.
#   webhook — 2xx bo'lmasa, so'rov 5 marta qaytariladi.


async def _json_body(request: Request) -> Dict[str, Any]:
    """
    Tanani o'qish. Multicard JSON yuboradi, lekin forma ko'rinishida
    kelib qolsa ham tushunamiz: tanani o'qiy olmaslik tufayli to'lovni
    bekor qilib yuborishdan ko'ra, ikkinchi ko'rinishni ham qabul
    qilish arzonga tushadi.
    """
    try:
        body = await request.json()
        if isinstance(body, dict):
            return body
    except Exception:
        pass
    try:
        form = await request.form()
        return dict(form)
    except Exception:
        return {}


def _int_or_none(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


@router.post("/rahmat/callback")
async def rahmat_callback(request: Request, db: Session = Depends(get_db)) -> Dict[str, Any]:
    """
    Muvaffaqiyatli to'lov: pulni balansga yozamiz.

    Imzo: md5({store_id}{invoice_id}{amount}{secret}).

    Multicard bu so'rovni QAYTA yuborishi mumkin (bizdan timeout yoki 500
    kelgan bo'lsa). Takroriy so'rovda ham success=true qaytaradi va pul
    ikkinchi marta yozilmaydi — idempotentlik apply_gateway_state ichida.
    """
    data = await _json_body(request)

    store_id = data.get("store_id")
    invoice_id = data.get("invoice_id")
    amount = _int_or_none(data.get("amount"))
    uuid = data.get("uuid")

    if amount is None:
        return {"success": False, "message": "amount yo'q"}

    if not rahmat_service.verify_callback_sign(
        store_id=store_id,
        invoice_id=invoice_id,
        amount_tiyin=amount,
        sign=data.get("sign"),
    ):
        logger.warning("Rahmat callback: imzo mos kelmadi, invoice_id=%s", invoice_id)
        return {"success": False, "message": "Imzo mos kelmadi"}

    transaction = rahmat_payment.find_transaction(db, uuid=uuid, invoice_id=invoice_id)
    if transaction is None:
        logger.warning("Rahmat callback: tranzaksiya topilmadi, invoice_id=%s", invoice_id)
        return {"success": False, "message": "Tranzaksiya topilmadi"}

    try:
        status = rahmat_payment.apply_gateway_state(
            db,
            transaction,
            gateway_status=rahmat_service.STATUS_SUCCESS,
            amount_tiyin=amount,
            uuid=uuid,
            card_pan=data.get("card_pan"),
            ps=data.get("ps"),
            billing_id=data.get("billing_id"),
            receipt_url=data.get("receipt_url"),
            payment_time=data.get("payment_time"),
        )
    except ValueError as exc:
        # Summa mos kelmadi. success=false qaytarish TO'G'RI javob: pul
        # plateljchiga qaytadi, biz esa noto'g'ri summani hisoblamaymiz.
        logger.error("Rahmat callback: %s (invoice_id=%s)", exc, invoice_id)
        return {"success": False, "message": "Summa mos kelmadi"}
    except Exception:
        logger.exception("Rahmat callback ichki xato: invoice_id=%s", invoice_id)
        # 500 qaytarish tranzaksiyani muzlatadi va so'rov qaytariladi —
        # hujjat shunday deydi, va bu bizga kerak: xatoni tuzatib,
        # takroriy so'rovda to'lovni qabul qilamiz.
        raise HTTPException(status_code=500, detail="internal error")

    return {"success": True, "message": f"Qabul qilindi: {status}"}


@router.post("/rahmat/webhook")
async def rahmat_webhook(request: Request, db: Session = Depends(get_db)) -> Dict[str, Any]:
    """
    Holat o'zgarishi: draft / progress / success / error / revert / hold.

    Imzo: sha1({uuid}{invoice_id}{amount}{secret}).

    Nega callback yetmaydi: callback FAQAT muvaffaqiyatli to'lovda keladi.
    Rad etilgan yoki qaytarilgan to'lov haqida bizga hech kim aytmasa,
    tranzaksiya abadiy 'pending' da qolib ketardi, qaytarilgan pul esa
    balansda turib qolardi.
    """
    data = await _json_body(request)

    uuid = data.get("uuid")
    invoice_id = data.get("invoice_id")
    amount = _int_or_none(data.get("amount"))

    if amount is None or not uuid:
        return {"success": False, "message": "uuid yoki amount yo'q"}

    if not rahmat_service.verify_webhook_sign(
        uuid=uuid,
        invoice_id=invoice_id,
        amount_tiyin=amount,
        sign=data.get("sign"),
    ):
        logger.warning("Rahmat webhook: imzo mos kelmadi, uuid=%s", uuid)
        return {"success": False, "message": "Imzo mos kelmadi"}

    transaction = rahmat_payment.find_transaction(db, uuid=uuid, invoice_id=invoice_id)
    if transaction is None:
        # 2xx qaytaramiz: tranzaksiya bizda yo'q bo'lsa, so'rovni 5 marta
        # qaytarishdan foyda yo'q.
        logger.warning("Rahmat webhook: tranzaksiya topilmadi, uuid=%s", uuid)
        return {"success": True, "message": "Tranzaksiya topilmadi"}

    try:
        status = rahmat_payment.apply_gateway_state(
            db,
            transaction,
            gateway_status=data.get("status"),
            amount_tiyin=amount,
            uuid=uuid,
            card_pan=data.get("card_pan"),
            ps=data.get("ps"),
            billing_id=data.get("billing_id"),
            receipt_url=data.get("receipt_url"),
            payment_time=data.get("payment_time"),
        )
    except ValueError as exc:
        logger.error("Rahmat webhook: %s (uuid=%s)", exc, uuid)
        return {"success": False, "message": "Summa mos kelmadi"}

    return {"success": True, "status": status}
