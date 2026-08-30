from sqlalchemy.orm import Session
from app.models.balance import Balance, BalanceTransaction
from app.schemas.balance import BalanceTransactionCreate, BalanceTransactionUpdate
from fastapi import HTTPException
from decimal import Decimal


def get_or_create_balance(db: Session, user_id: int):
    """Foydalanuvchi balansini olish yoki yaratish"""
    balance = db.query(Balance).filter(Balance.user_id == user_id).first()
    if not balance:
        balance = Balance(user_id=user_id, balance=Decimal('0.0'), frozen_balance=Decimal('0.0'))
        db.add(balance)
        db.commit()
        db.refresh(balance)
    return balance


def get_balance(db: Session, user_id: int):
    """Foydalanuvchi balansini olish"""
    return get_or_create_balance(db, user_id)


def update_balance(db: Session, user_id: int, amount: float):
    """Balansni yangilash"""
    balance = get_or_create_balance(db, user_id)
    balance.balance += Decimal(str(amount))

    # Balans manfiy bo'lmasligi kerak
    if balance.balance < 0:
        raise HTTPException(status_code=400, detail="Insufficient balance")

    db.commit()
    db.refresh(balance)
    return balance


def create_transaction(
    db: Session,
    user_id: int,
    amount: float,
    transaction_type: str,
    payment_method: str = None,
    description: str = None,
    status: str = "pending",
    phone_number: str = None
):
    """Yangi tranzaksiya yaratish"""
    from app.utils.phone_utils import format_phone_number, validate_uzbek_phone

    # Telefon raqamni formatlash va validatsiya
    formatted_phone = None
    if phone_number:
        try:
            formatted_phone = format_phone_number(phone_number)
            if not validate_uzbek_phone(formatted_phone):
                raise HTTPException(status_code=400, detail="Invalid phone number")
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Invalid phone number: {str(e)}")

    transaction = BalanceTransaction(
        user_id=user_id,
        amount=Decimal(str(amount)),
        type=transaction_type,
        status=status,
        payment_method=payment_method,
        description=description,
        phone_number=formatted_phone
    )
    db.add(transaction)
    db.commit()
    db.refresh(transaction)
    return transaction


def top_up_balance(
    db: Session,
    user_id: int,
    transaction_data: BalanceTransactionCreate
):
    """
    Hisob to'ldirish

    Click to'lov uchun: Transaction yaratish va pending holatda qoldirish
    Boshqa to'lov usullari uchun: To'g'ridan-to'g'ri completed qilish
    """
    import os

    # Validatsiya
    if transaction_data.amount < 10000 or transaction_data.amount > 10000000:
        raise HTTPException(
            status_code=400,
            detail="Amount must be between 10,000 and 10,000,000"
        )

    # Tranzaksiya yaratish
    transaction = create_transaction(
        db=db,
        user_id=user_id,
        amount=transaction_data.amount,
        transaction_type="topup",
        payment_method=transaction_data.payment_method,
        description=f"Hisob to'ldirish - {transaction_data.payment_method}",
        status="pending",
        phone_number=transaction_data.phone_number
    )

    # Agar Click to'lov bo'lsa, pending holatda qoldiramiz
    # Click callback orqali completed qilinadi
    if transaction_data.payment_method == "click":
        db.commit()
        db.refresh(transaction)
        return transaction

    # Boshqa to'lov usullari uchun to'g'ridan-to'g'ri completed qilish
    transaction.status = "completed"

    # Balansni yangilash
    update_balance(db, user_id, transaction_data.amount)

    db.commit()
    db.refresh(transaction)

    return transaction


def generate_click_payment_url(transaction_id: int, amount: float, return_url: str = None) -> str:
    """
    Click to'lov URL'ini yaratish

    Format: https://my.click.uz/services/pay?service_id=SERVICE_ID&merchant_id=MERCHANT_ID&amount=AMOUNT&transaction_param=TRANSACTION_ID&return_url=RETURN_URL
    """
    import os

    service_id = os.getenv("CLICK_SERVICE_ID", "")
    merchant_id = os.getenv("CLICK_MERCHANT_ID", "")

    # Return URL - mobil ilovaga qaytish uchun
    if not return_url:
        return_url = os.getenv("CLICK_RETURN_URL", "movexgo://payment/success")

    # Click to'lov URL'i
    payment_url = (
        f"https://my.click.uz/services/pay?"
        f"service_id={service_id}&"
        f"merchant_id={merchant_id}&"
        f"amount={amount}&"
        f"transaction_param={transaction_id}&"
        f"return_url={return_url}"
    )

    return payment_url


def get_transaction(db: Session, transaction_id: int, user_id: int):
    """Bitta tranzaksiyani olish"""
    transaction = db.query(BalanceTransaction).filter(
        BalanceTransaction.id == transaction_id,
        BalanceTransaction.user_id == user_id
    ).first()
    return transaction


def get_transactions(db: Session, user_id: int, skip: int = 0, limit: int = 100):
    """Foydalanuvchi tranzaksiyalarini olish"""
    transactions = db.query(BalanceTransaction).filter(
        BalanceTransaction.user_id == user_id
    ).order_by(
        BalanceTransaction.created_at.desc()
    ).offset(skip).limit(limit).all()
    return transactions


def update_transaction(
    db: Session,
    transaction_id: int,
    user_id: int,
    transaction_update: BalanceTransactionUpdate
):
    """Tranzaksiyani yangilash"""
    transaction = get_transaction(db, transaction_id, user_id)
    if not transaction:
        return None
    
    for key, value in transaction_update.dict(exclude_unset=True).items():
        setattr(transaction, key, value)
    
    db.commit()
    db.refresh(transaction)
    return transaction


def process_payment_from_balance(db: Session, user_id: int, amount: float, description: str = None):
    """
    Balansdan to'lov qilish
    Buyurtma to'lovi uchun ishlatiladi
    """
    # Balansni tekshirish
    balance = get_balance(db, user_id)
    if balance.balance < amount:
        raise HTTPException(status_code=400, detail="Insufficient balance")
    
    # Tranzaksiya yaratish
    transaction = create_transaction(
        db=db,
        user_id=user_id,
        amount=amount,
        transaction_type="payment",
        payment_method="balance",
        description=description or "To'lov balansdan",
        status="completed"
    )
    
    # Balansni kamaytirish
    update_balance(db, user_id, -amount)
    
    return transaction

