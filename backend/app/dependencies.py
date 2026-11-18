# app/core/dependencies.py
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from jose import jwt, JWTError
from app.db.session import get_db
from app.models import User
from app.core.config import settings

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=["HS256"])
        # sub в JWT — строка. Без int() сравнение integer = varchar
        # прощал только psycopg2; psycopg 3 отвечал 500 на всех роутах,
        # которые берут пользователя отсюда.
        user_id = int(payload.get("sub"))
    except (JWTError, TypeError, ValueError):
        raise credentials_exception

    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise credentials_exception
    # Та же проверка, что в routes/auth.get_current_user. Без неё
    # заблокированный (и удалённый — у него тоже is_blocked) человек
    # продолжал работать с заказами, картами, чатом, балансом и платежами:
    # отказ приходил только от роутов, которые берут пользователя из auth.
    if getattr(user, "is_blocked", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(user.blocked_reason
                    or "Hisobingiz bloklangan. Administrator bilan bog'laning."),
            headers={"X-Account-Blocked": "1"},
        )
    return user

def get_current_active_user(current_user: User = Depends(get_current_user)) -> User:
    # Если у тебя будут актив/неактив, сюда можно добавить проверку
    return current_user
