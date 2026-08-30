from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from typing import List, Dict, Any
from app.schemas import balance as balance_schema
from app.services import balance_service
from app.services.click_service import ClickService
from app.dependencies import get_db, get_current_user

router = APIRouter()


@router.get("/me", response_model=balance_schema.BalanceRead)
def get_my_balance(
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    """Joriy foydalanuvchi balansini olish"""
    balance = balance_service.get_balance(db, current_user.id)
    return balance


@router.post("/topup", response_model=balance_schema.BalanceTopUpResponse)
def top_up_balance(
    transaction_data: balance_schema.BalanceTransactionCreate,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    """
    Hisob to'ldirish

    Click to'lov uchun: Transaction yaratish va to'lov URL'ini qaytarish
    Boshqa to'lov usullari uchun: To'g'ridan-to'g'ri balansni yangilash
    """
    transaction = balance_service.top_up_balance(db, current_user.id, transaction_data)

    # Response yaratish
    response = {
        "transaction_id": transaction.id,
        "amount": float(transaction.amount),
        "payment_method": transaction.payment_method,
        "status": transaction.status,
        "payment_url": None
    }

    # Har qanday tashqi to'lov tizimi uchun to'lov havolasi
    response["payment_url"] = balance_service.generate_payment_url(
        payment_method=transaction.payment_method,
        transaction_id=transaction.id,
        amount=float(transaction.amount),
    )

    return response


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


# ============================================
# Click to'lov tizimi callback endpoint'lari
# ============================================

@router.post("/click/prepare")
async def click_prepare(request: Request, db: Session = Depends(get_db)) -> Dict[str, Any]:
    """
    Click Prepare - To'lovni tayyorlash

    Click bu endpoint'ga quyidagi ma'lumotlarni yuboradi:
    - click_trans_id: Click transaction ID
    - service_id: Service ID
    - click_paydoc_id: Click paydoc ID
    - merchant_trans_id: Bizning transaction ID
    - amount: To'lov summasi
    - action: 0 (prepare) yoki 1 (complete)
    - error: Xato kodi
    - error_note: Xato matni
    - sign_time: Vaqt
    - sign_string: Signature
    """
    try:
        # Form data'ni olish
        form_data = await request.form()
        data = dict(form_data)

        # Click service orqali prepare qilish
        result = ClickService.prepare(
            db=db,
            click_trans_id=int(data.get('click_trans_id', 0)),
            merchant_trans_id=int(data.get('merchant_trans_id', 0)),
            amount=float(data.get('amount', 0)),
            action=int(data.get('action', 0)),
            sign_time=data.get('sign_time', ''),
            sign_string=data.get('sign_string', ''),
            error=int(data.get('error', 0)),
            error_note=data.get('error_note', 'Success')
        )

        return result

    except Exception as e:
        return {
            "error": -8,
            "error_note": f"Error in request from click: {str(e)}"
        }


@router.post("/click/complete")
async def click_complete(request: Request, db: Session = Depends(get_db)) -> Dict[str, Any]:
    """
    Click Complete - To'lovni yakunlash va balansni yangilash

    Click bu endpoint'ga prepare'dagi kabi ma'lumotlarni yuboradi
    """
    try:
        # Form data'ni olish
        form_data = await request.form()
        data = dict(form_data)

        # Click service orqali complete qilish
        result = ClickService.complete(
            db=db,
            click_trans_id=int(data.get('click_trans_id', 0)),
            merchant_trans_id=int(data.get('merchant_trans_id', 0)),
            amount=float(data.get('amount', 0)),
            action=int(data.get('action', 1)),
            sign_time=data.get('sign_time', ''),
            sign_string=data.get('sign_string', ''),
            error=int(data.get('error', 0)),
            error_note=data.get('error_note', 'Success')
        )

        return result

    except Exception as e:
        return {
            "error": -8,
            "error_note": f"Error in request from click: {str(e)}"
        }

