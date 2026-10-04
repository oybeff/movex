import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from fastapi.security import OAuth2PasswordRequestForm
from datetime import timedelta

from app.db.session import get_db
from app.models.user import User
from app.schemas.user import UserCreate, UserRead
from app.schemas.otp import OTPSendRequest, OTPSendResponse, OTPVerifyRequest, OTPVerifyResponse
from app.core.security import hash_password, verify_password, create_access_token
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
@router.post("/register", response_model=OTPVerifyResponse)
def register(user_in: UserCreate, db: Session = Depends(get_db)):
    """
    Ro'yxatdan o'tish: raqam SMS kodi bilan tasdiqlangan bo'lishi shart.

    Javobda DARHOL kirish tokeni qaytadi. Ilgari bu yerda foydalanuvchi
    qaytardi va ilova odamni qaytadan kirish ekraniga olib borardi —
    ya'ni SMS IKKI MARTA so'ralardi. Endi kod bir marta keladi: raqamni
    tasdiqlash, ism-familiya, so'ng PIN kod.
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

    # Token shu yerda beriladi — qayta SMS so'ramaslik uchun.
    return _issue_login(new_user)

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
