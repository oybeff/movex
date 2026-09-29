import logging
import secrets

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from sqlalchemy.orm import Session
from fastapi.security import OAuth2PasswordRequestForm
from datetime import timedelta

from app.db.session import get_db
from app.models.user import User
from app.schemas.user import UserCreate, UserRead
from app.schemas.otp import OTPSendRequest, OTPSendResponse, OTPVerifyRequest, OTPVerifyResponse
from app.core.security import hash_password, verify_password, create_access_token
from app.services import telegram_auth_service
from app.core.config import settings
from app.services.otp_service import OTPService
from sqlalchemy import or_
# ========================
# Роутер
# ========================
router = APIRouter()

logger = logging.getLogger(__name__)

# ========================
# OAuth2 для получения текущего пользователя
# ========================
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from app.utils.phone_utils import to_db_phone

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id: int = int(payload.get("sub"))
        if user_id is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    except (JWTError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")

    # Bloklangan hisob TOKEN BILAN HAM ishlamaydi.
    #
    # Faqat kirish paytida tekshirish yetarli emas: token 30 kun yashaydi,
    # ya'ni bloklashdan oldin kirgan odam yana bir oy ishlayverardi.
    if getattr(user, "is_blocked", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(user.blocked_reason
                    or "Hisobingiz bloklangan. Administrator bilan bog'laning."),
        )

    return user

# ========================
# Регистрация пользователя (только телефон + OTP)
# ========================
@router.post("/register", response_model=UserRead)
def register(user_in: UserCreate, db: Session = Depends(get_db)):
    """
    Register new user with phone number only (no email/password needed)
    Phone must be verified via OTP first
    """
    # Telefon raqam majburiy
    if not user_in.phone:
        raise HTTPException(status_code=400, detail="Telefon raqam majburiy")

    # Clean phone number
    clean_phone = to_db_phone(user_in.phone)

    # Check if phone is verified
    otp_service = OTPService(db)
    if not otp_service.is_phone_verified(clean_phone):
        raise HTTPException(status_code=400, detail="Telefon raqam tasdiqlanmagan. Iltimos, avval OTP kodni tasdiqlang.")

    # Check if user already exists by phone
    existing_user = db.query(User).filter(User.phone == clean_phone).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Bu telefon raqam allaqachon ro'yxatdan o'tgan")

    # Generate random password (user won't need it, only OTP login)
    import secrets
    random_password = secrets.token_urlsafe(16)
    hashed_pwd = hash_password(random_password)

    new_user = User(
        full_name=user_in.full_name,
        email=None,  # Email not used
        phone=clean_phone,
        password_hash=hashed_pwd,
        role=user_in.role
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    # Yangi texnika egasiga ro'yxatdan o'tganlik uchun sovg'a.
    #
    # Miqdor adminkadan boshqariladi. Sovg'a berilmasa ham ro'yxatdan o'tish
    # buzilmaydi — xato ichida yutiladi.
    from app.services import balance_service
    balance_service.grant_signup_bonus(db, new_user)

    return new_user

# ========================
# DEPRECATED: Login endpoint (use OTP verification instead)
# ========================
# This endpoint is kept for backward compatibility only
# New users should use /send-otp and /verify-otp flow
@router.post("/login")
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    """
    DEPRECATED: Use OTP verification flow instead
    This endpoint is kept only for backward compatibility
    """
    raise HTTPException(
        status_code=400,
        detail="Bu endpoint ishlatilmaydi. Iltimos, OTP orqali kiring: /send-otp va /verify-otp"
    )

# ========================
# OTP yuborish (telefon raqamga)
# ========================
@router.post("/send-otp", response_model=OTPSendResponse)
async def send_otp(request: OTPSendRequest, db: Session = Depends(get_db)):
    """
    Send OTP code to phone number
    """
    otp_service = OTPService(db)
    result = await otp_service.send_otp(request.phone, request.language)

    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["message"])

    return OTPSendResponse(
        success=True,
        message=result["message"],
        expires_in=result.get("expires_in", 300)
    )

# ========================
# OTP tekshirish va login
# ========================
@router.post("/verify-otp", response_model=OTPVerifyResponse)
def verify_otp(request: OTPVerifyRequest, db: Session = Depends(get_db)):
    """
    Verify OTP code and login user
    """
    otp_service = OTPService(db)
    result = otp_service.verify_otp(request.phone, request.otp_code)

    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["message"])

    # Clean phone number
    clean_phone = to_db_phone(request.phone)

    # Hisob bor-yo'qligi, bloklanganlik va token — hammasi bitta joyda,
    # Telegram orqali kirish bilan umumiy.
    return _login_by_phone(db, clean_phone)


def _issue_login(user) -> OTPVerifyResponse:
    """
    Kirish tokenini beradi.

    Alohida funksiya ataylab: kirish endi IKKI yo'l bilan bo'ladi —
    SMS kodi va Telegram. Token berish mantig'i ikki joyda takrorlansa,
    ular ertami-kechmi ajralib qoladi: masalan bloklangan hisob
    tekshiruvi bittasida qolib, ikkinchisida yo'qolib ketardi.
    """
    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": str(user.id)},
        expires_delta=access_token_expires
    )

    return OTPVerifyResponse(
        success=True,
        message="Muvaffaqiyatli kirdingiz",
        access_token=access_token,
        token_type="bearer",
        user_id=user.id,
        role=user.role
    )


def _login_by_phone(db: Session, clean_phone: str) -> OTPVerifyResponse:
    """Raqam tasdiqlangandan keyingi umumiy qism: hisob bormi, bloklanganmi."""
    user = db.query(User).filter(User.phone == clean_phone).first()

    if not user:
        # Hisob hali yo'q — ro'yxatdan o'tish oqimi
        return OTPVerifyResponse(
            success=True,
            message="Telefon raqam tasdiqlandi. Ro'yxatdan o'tishni davom ettiring.",
            access_token=None,
            token_type=None,
            user_id=None,
            role=None,
        )

    if getattr(user, "is_blocked", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(user.blocked_reason
                    or "Hisobingiz bloklangan. Administrator bilan bog'laning."),
        )

    try:
        from datetime import datetime, timezone
        user.last_login_at = datetime.now(timezone.utc)
        db.commit()
    except Exception:
        db.rollback()

    return _issue_login(user)


# ------------------------------------------------ Telegram orqali kirish

@router.post("/telegram/start")
def telegram_login_start(db: Session = Depends(get_db)):
    """
    Kirish havolasini beradi: t.me/<bot>?start=<token>.

    Nega havola kerak. Telegram boti odamga BIRINCHI bo'lib yoza olmaydi
    va uni telefon raqami bo'yicha topa olmaydi — bunday API yo'q.
    Shuning uchun birinchi aloqani odamning o'zi boshlaydi.
    """
    if not telegram_auth_service.is_configured():
        raise HTTPException(400, "Telegram orqali kirish sozlanmagan")
    return telegram_auth_service.create_login_request(db)


@router.get("/telegram/status")
def telegram_login_status(token: str, db: Session = Depends(get_db)):
    """Ilova shu yerni so'rab turadi, javob kutayotganda."""
    return telegram_auth_service.check_login_request(db, token)


@router.post("/telegram/complete", response_model=OTPVerifyResponse)
def telegram_login_complete(token: str, db: Session = Depends(get_db)):
    """
    Tasdiqlangan so'rov bo'yicha kirish.

    Raqam Telegramning O'ZIDAN kelgan (contact xabari), ya'ni u
    tasdiqlangan — SMS kodidan kam ishonchli emas.
    """
    phone = telegram_auth_service.consume_login_request(db, token)
    if phone is None:
        raise HTTPException(400, "Kirish tasdiqlanmagan yoki muddati o'tgan")
    return _login_by_phone(db, phone)


@router.post("/telegram/webhook", include_in_schema=False)
async def telegram_webhook(
    request: Request,
    db: Session = Depends(get_db),
    x_telegram_bot_api_secret_token: str | None = Header(default=None),
):
    """
    Telegram yangiliklarini QABUL QILADI — so'rab turishning o'rniga.

    Nega prodda aynan shu kerak. telegram_poller ilova ishga tushganda
    boshlanadi, ilova esa uvicorn'da bir NECHA jarayonda ishlaydi
    (--workers 2). Ya'ni bitta botni ikki joydan so'raymiz, Telegram esa
    409 qaytaradi va kirish gohida ishlaydi, gohida yo'q. Vebhukda
    bunday muammo yo'q: yangilikni Telegram o'zi yuboradi, qaysi
    jarayon qabul qilsa — o'sha ishlaydi.

    Manzil TELEGRAM_WEBHOOK_SECRET bilan yopilgan. So'z ko'rsatilmagan
    bo'lsa manzil umuman yo'q (404): ochiq qoldirilsa, uni bilgan har
    kim soxta "contact" yuborib, BEGONA raqamdan kirishni tasdiqlagan
    bo'lardi — parol ham, kod ham so'ralmaydi.
    """
    secret = settings.TELEGRAM_WEBHOOK_SECRET
    if not secret:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not Found")
    if not secrets.compare_digest(x_telegram_bot_api_secret_token or "", secret):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Forbidden")

    try:
        update = await request.json()
    except Exception:  # noqa: BLE001 — Telegramdan buzuq tana kelishi mumkin
        return {"ok": True}

    # Xato bo'lsa ham 200 qaytaramiz. 200 dan boshqa javobda Telegram
    # AYNAN SHU yangilikni qayta-qayta yuboraveradi va navbat to'xtaydi:
    # bitta buzuq xabar butun kirishni o'ldiradi.
    try:
        await telegram_auth_service.handle_update(db, update)
    except Exception as exc:  # noqa: BLE001
        logger.exception("Telegram yangiligi qayta ishlanmadi: %s", exc)
        db.rollback()
    return {"ok": True}
