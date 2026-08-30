from sqlalchemy.orm import Session
from app.models.user import User
from app.schemas.user import UserCreate, UserUpdate
from app.services import auth_service


def create_user(db: Session, user: UserCreate):
    """Yangi foydalanuvchi yaratish"""
    hashed_password = auth_service.get_password_hash(user.password)
    db_user = User(full_name=user.full_name, email=user.email, phone=user.phone, hashed_password=hashed_password)
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user


def get_user(db: Session, user_id: int):
    """Bitta foydalanuvchini olish"""
    return db.query(User).filter(User.id == user_id).first()


def get_users(db: Session, skip: int = 0, limit: int = 100):
    """Barcha foydalanuvchilarni olish"""
    return db.query(User).offset(skip).limit(limit).all()


def update_user(db: Session, user_id: int, user: UserUpdate):
    """Foydalanuvchini yangilash"""
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        return None
    for key, value in user.dict(exclude_unset=True).items():
        setattr(db_user, key, value)
    db.commit()
    db.refresh(db_user)
    return db_user


def delete_user(db: Session, user_id: int):
    """Foydalanuvchini o'chirish"""
    db_user = db.query(User).filter(User.id == user_id).first()
    if db_user:
        db.delete(db_user)
        db.commit()
    return db_user
