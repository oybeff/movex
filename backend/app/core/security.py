from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
from passlib.context import CryptContext
from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Хэшируем пароль
def hash_password(password: str) -> str:
    return pwd_context.hash(password)

# Проверка пароля
def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

# Создание JWT токена
def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    """
    Kirish tokeni.

    ACCESS_TOKEN_EXPIRE_MINUTES = 0 bo'lsa, tokenga MUDDAT QO'YILMAYDI: odam
    bir marta kiradi va ilova uni boshqa so'ramaydi. Telefonni himoya qilish
    endi ilovaning o'zida — PIN kod va barmoq izi / yuz.

    Nega shunday. Ilgari muddat bir kun edi: odam ertasiga ilovani ochsa,
    yana kod so'ralardi. Foydalanuvchi buni "har safar qaytadan kirish" deb
    tushunardi.

    Bloklangan hisob baribir DARHOL uziladi — buni get_current_user
    tekshiradi, muddat bunga aloqador emas.
    """
    to_encode = data.copy()
    if expires_delta:
        to_encode.update({"exp": datetime.utcnow() + expires_delta})
    elif settings.ACCESS_TOKEN_EXPIRE_MINUTES > 0:
        to_encode.update({
            "exp": datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
        })
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return encoded_jwt

# Декодирование JWT
def decode_access_token(token: str):
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        return payload
    except JWTError:
        return None
