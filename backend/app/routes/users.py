from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from app.db.session import get_db
from app.models.user import User
from app.schemas.user import UserCreate, UserRead, UserUpdate
from app.routes.auth import get_current_user
from app.core.access import assert_can_view_user, assert_self_or_admin
from app.core.roles import role_checker
from app.core.security import hash_password

router = APIRouter()

@router.post("/", response_model=UserRead)
def create_user(user_in: UserCreate, db: Session = Depends(get_db), current_user: User = Depends(role_checker(["admin"]))):
    """
    Foydalanuvchi yaratish — faqat admin.

    Oddiy ro'yxatdan o'tish /auth/register orqali, OTP tasdig'i bilan
    boradi. Bu yerda esa ilgari har qanday foydalanuvchi o'ziga xohlagan
    rolda, jumladan 'admin' rolida, hisob yarata olardi.
    """
    existing = db.query(User).filter(User.phone == user_in.phone).first()
    if existing:
        raise HTTPException(status_code=400, detail="Bu telefon raqam allaqachon ro'yxatdan o'tgan")

    hashed_pwd = hash_password(user_in.password)
    new_user = User(
        full_name=user_in.full_name,
        email=user_in.email,
        phone=user_in.phone,
        password_hash=hashed_pwd,
        role=user_in.role
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return new_user

@router.get("/me", response_model=UserRead)
def get_current_user_info(current_user: User = Depends(get_current_user)):
    """Joriy foydalanuvchi ma'lumotlarini olish"""
    return current_user


@router.put("/me", response_model=UserRead)
def update_current_user(
    user_in: UserUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Joriy foydalanuvchi ma'lumotlarini yangilash"""
    data = user_in.dict(exclude_unset=True)

    # Telefon raqam boshqa hisobda band bo'lmasin — aks holda commit
    # unique cheklovga urilib, 500 xato qaytarardi
    new_phone = data.get("phone")
    if new_phone and new_phone != current_user.phone:
        taken = db.query(User).filter(User.phone == new_phone, User.id != current_user.id).first()
        if taken:
            raise HTTPException(status_code=400, detail="Bu telefon raqam band")

    for field, value in data.items():
        if field == "password":
            setattr(current_user, "password_hash", hash_password(value))
        else:
            setattr(current_user, field, value)

    db.commit()
    db.refresh(current_user)
    return current_user


@router.get("/", response_model=List[UserRead])
def list_users(db: Session = Depends(get_db), current_user: User = Depends(role_checker(["admin"]))):
    """
    Barcha foydalanuvchilar — faqat admin.
    Ilgari har qanday foydalanuvchi butun bazani, telefon raqamlari bilan
    birga, yuklab olishi mumkin edi.
    """
    return db.query(User).all()

@router.get("/{user_id}", response_model=UserRead)
def get_user(user_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """
    Profil: o'ziniki, admin uchun har kimniki, yoki bitta buyurtma
    bo'yicha kontragentniki — mijoz va texnika egasi bir-biriga
    qo'ng'iroq qila olishi kerak.
    """
    assert_can_view_user(db, current_user, user_id)
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")
    return user

@router.put("/{user_id}", response_model=UserRead)
def update_user(user_id: int, user_in: UserUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """
    O'z profilini tahrirlash yoki admin.

    Ilgari bu yerda hech qanday tekshiruv yo'q edi: istalgan foydalanuvchi
    boshqasining telefon raqamini yoki parolini o'zgartirib, hisobini
    egallab olishi mumkin edi.
    """
    assert_self_or_admin(current_user, user_id)

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")

    data = user_in.dict(exclude_unset=True)

    # Telefon raqam boshqa hisobda band bo'lmasin
    new_phone = data.get("phone")
    if new_phone and new_phone != user.phone:
        taken = db.query(User).filter(User.phone == new_phone, User.id != user_id).first()
        if taken:
            raise HTTPException(status_code=400, detail="Bu telefon raqam band")

    for field, value in data.items():
        if field == "password":
            setattr(user, "password_hash", hash_password(value))
        else:
            setattr(user, field, value)

    db.commit()
    db.refresh(user)
    return user

@router.delete("/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db), current_user: User = Depends(role_checker(["admin"]))):
    """
    Foydalanuvchini o'chirish — faqat admin.

    Ilgari buni har kim qila olardi: bir so'rov bilan istalgan hisobni,
    jumladan adminnikini ham, texnikasi va buyurtmalari bilan birga
    o'chirib yuborish mumkin edi (ON DELETE CASCADE).
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")

    if user.id == current_user.id:
        raise HTTPException(status_code=400, detail="O'zingizni o'chira olmaysiz")

    if user.role == "admin":
        admins_left = db.query(User).filter(User.role == "admin", User.id != user_id).count()
        if admins_left == 0:
            raise HTTPException(status_code=400, detail="Oxirgi adminni o'chirib bo'lmaydi")

    db.delete(user)
    db.commit()
    return {"detail": "User deleted"}
