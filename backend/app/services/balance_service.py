from sqlalchemy.orm import Session
from app.models.balance import Balance, BalanceTransaction
from app.schemas.balance import BalanceTransactionCreate, BalanceTransactionUpdate
from app.services import payment_providers
from app.core.messages import t
from fastapi import HTTPException
import logging
from decimal import Decimal

# Ruxsat etilgan usullar ro'yxati payment_providers da turadi — yangi tizim
# qo'shilganda faqat o'sha faylni tahrirlash kifoya.
SELF_SERVICE_PAYMENT_METHODS = payment_providers.SELF_SERVICE_PAYMENT_METHODS


def _user_language(db: Session, user_id: int):
    """
    Izoh kimga ko'rinsa — o'sha odamning tili.

    "Amallar tarixi"dagi satr bazaga tayyor holda yoziladi, shuning uchun til
    yozish paytida hal bo'ladi. Ilgari bu yerda f-satr turardi va ruscha
    interfeysda "Hisob to'ldirish - click" chiqardi.
    """
    from app.models.user import User
    user = db.query(User).filter(User.id == user_id).first()
    return user.language if user else None


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
    Hisob to'ldirish.

    Tranzaksiya HAR DOIM 'pending' holatda yaratiladi. Balans faqat to'lov
    tizimidan tasdiq kelganda to'ldiriladi (Click uchun — /balance/click/complete).

    Ilgari 'click'dan boshqa har qanday usul balansni darhol to'ldirar edi,
    hech qanday to'lovni tekshirmasdan: bitta so'rov bilan 10 000 000 so'm
    olish mumkin edi. Shuning uchun tasdiqlanmagan usullar endi rad etiladi.
    """
    # Validatsiya
    if transaction_data.amount < 10000 or transaction_data.amount > 10000000:
        raise HTTPException(
            status_code=400,
            detail="Amount must be between 10,000 and 10,000,000"
        )

    if transaction_data.payment_method not in SELF_SERVICE_PAYMENT_METHODS:
        raise HTTPException(
            status_code=400,
            detail=(
                "Bu to'lov usuli hozircha mavjud emas. "
                f"Mavjud usullar: {', '.join(sorted(SELF_SERVICE_PAYMENT_METHODS))}"
            )
        )

    # Tranzaksiya yaratish — 'pending', to'lov tizimi tasdiqlagunicha
    transaction = create_transaction(
        db=db,
        user_id=user_id,
        amount=transaction_data.amount,
        transaction_type="topup",
        payment_method=transaction_data.payment_method,
        description=t("tx.topup", _user_language(db, user_id),
                      method=transaction_data.payment_method),
        status="pending",
        phone_number=transaction_data.phone_number
    )

    db.commit()
    db.refresh(transaction)

    return transaction


def generate_payment_url(payment_method: str, transaction_id: int, amount: float) -> str:
    """
    Tanlangan to'lov tizimining to'lov sahifasiga havola.

    Kalitlar sozlanmagan bo'lsa, ishlamaydigan havola qaytarish o'rniga aniq
    xato beramiz: aks holda mijoz to'lov tizimining bo'sh sahifasiga tushardi.
    """
    provider = payment_providers.get(payment_method)
    if provider is None:
        raise HTTPException(
            status_code=400,
            detail=f"Noma'lum to'lov usuli: {payment_method}"
        )

    if not provider.is_configured():
        raise HTTPException(
            status_code=503,
            detail=f"{provider.title} to'lov tizimi sozlanmagan. Administratorga murojaat qiling."
        )

    return provider.build_checkout_url(transaction_id, amount)


def generate_click_payment_url(transaction_id: int, amount: float) -> str:
    """Eski nom — mos kelishi uchun qoldirilgan."""
    return generate_payment_url("click", transaction_id, amount)


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


# process_payment_from_balance() olib tashlandi.
#
# U hech qayerdan chaqirilmasdi va chaqirilganda 500 xato berardi:
# payment_method sifatida "balance" yozardi, lekin jadval cheklovi bunday
# qiymatni qabul qilmaydi (faqat click, payme, uzum, card, cash yoki NULL).
#
# Buyurtma uchun pul harakati order_service da, escrow mantig'i bilan
# birga turadi — ikkinchi, yashirin yo'l kerak emas.



# --- Ro'yxatdan o'tganlik uchun bonus ---------------------------------------
#
# Yangi texnika egasi ro'yxatdan o'tganda hisobiga sovg'a tushadi.
#
# Miqdor va yoqilganligi KODDA emas, app_settings da: komissiya bilan bir xil
# yondashuv, adminkadan o'zgartiriladi. Aks holda summani o'zgartirish uchun
# har safar yangi versiya chiqarish kerak bo'lardi.
SIGNUP_BONUS_ENABLED_KEY = "signup_bonus_enabled"
SIGNUP_BONUS_AMOUNT_KEY = "signup_bonus_amount"
DEFAULT_SIGNUP_BONUS = Decimal("50000")

#: Tranzaksiya turi. Alohida tur ataylab: adminkada va tarixda sovg'a
#: to'ldirishdan ajralib turishi kerak, aks holda pul qayerdan kelgani
#: ko'rinmaydi.
TX_TYPE_BONUS = "bonus"


def _settings_value(db: Session, key: str):
    from app.models.app_settings import AppSettings
    row = db.query(AppSettings).filter(AppSettings.key == key).first()
    return None if row is None or row.value is None else str(row.value)


def is_signup_bonus_enabled(db: Session) -> bool:
    """Sovg'a yoqilganmi. Sozlama yo'q bo'lsa — yoqilgan."""
    raw = _settings_value(db, SIGNUP_BONUS_ENABLED_KEY)
    if raw is None:
        return True
    return str(raw).strip().lower() in ("1", "true", "yes", "on")


def get_signup_bonus_amount(db: Session) -> Decimal:
    """Sovg'a miqdori. Xato yoki manfiy qiymat — standart 50 000."""
    raw = _settings_value(db, SIGNUP_BONUS_AMOUNT_KEY)
    if raw is None:
        return DEFAULT_SIGNUP_BONUS
    try:
        amount = Decimal(raw)
    except (ArithmeticError, TypeError, ValueError):
        return DEFAULT_SIGNUP_BONUS
    return amount if amount >= 0 else DEFAULT_SIGNUP_BONUS


def grant_signup_bonus(db: Session, user):
    """
    Yangi texnika egasiga sovg'a beradi. Faqat 'owner' uchun.

    Ro'yxatdan o'tish shu funksiya bilan buzilmasligi kerak: sovg'a berilmasa
    ham odam ilovaga kirishi shart, shuning uchun xato jim yutiladi va
    ro'yxatdan o'tish davom etadi.
    """
    if getattr(user, "role", None) != "owner":
        return None
    if not is_signup_bonus_enabled(db):
        return None

    amount = get_signup_bonus_amount(db)
    if amount <= 0:
        return None

    try:
        update_balance(db, user.id, amount)
        # Sovg'aning yechib bo'lmaydigan qismini belgilaymiz.
        balance = get_or_create_balance(db, user.id)
        balance.bonus_balance = Decimal(str(balance.bonus_balance or 0)) + Decimal(str(amount))
        db.commit()
        return create_transaction(
            db,
            user_id=user.id,
            amount=amount,
            transaction_type=TX_TYPE_BONUS,
            description=t("tx.signup_bonus", _user_language(db, user.id)),
            status="completed",
        )
    except Exception:
        # Xato yutiladi, lekin JIM emas: aynan jim `except` tufayli
        # 'bonus' turi CHECK cheklovidan o'tmayotgani ko'rinmay qolgandi —
        # balans to'lgan, tranzaksiya esa yozilmagan edi.
        logging.getLogger(__name__).exception(
            "ro'yxatdan o'tganlik sovg'asi berilmadi: user_id=%s", getattr(user, "id", None)
        )
        db.rollback()
        return None


def withdrawable_balance(balance) -> Decimal:
    """
    Kartaga yechish mumkin bo'lgan summa.

    Sovg'a bunga KIRMAYDI: uni ilova ichida ishlatish mumkin, yechib
    bo'lmaydi. Aks holda har bir yangi SIM kartadan 50 000 chiqib ketardi.
    """
    total = Decimal(str(balance.balance or 0))
    frozen = Decimal(str(balance.frozen_balance or 0))
    bonus = Decimal(str(balance.bonus_balance or 0))
    available = total - frozen - bonus
    return available if available > 0 else Decimal("0")
