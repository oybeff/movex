from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from typing import List

from app.db.session import get_db
from app.models.user import User
from app.schemas.user import UserCreate, UserRead, UserUpdate
from app.routes.auth import get_current_user
from app.core.access import assert_can_view_user, assert_self_or_admin
from app.core.roles import role_checker
from app.core.messages import t
from app.core.security import hash_password
from app.services import account_deletion_service
from app.utils.phone_utils import to_db_phone
from app.core.media import delete_by_url, save_upload
from app.models.user_address import ADDRESS_KINDS, UserAddress

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
    # Raqam bazadagi YAGONA ko'rinishga keltiriladi: 998901234567.
    # Ilgari u qanday yozilgan bo'lsa shundayligicha saqlanardi, va
    # profilga "+998901234567" deb yozgan odam O'Z hisobiga kira olmay
    # qolardi — kirish "+" siz qidiradi. Bandlik tekshiruvi ham shu
    # sababdan ishlamasdi: "+998..." va "998..." boshqa satr deb
    # hisoblanardi, ya'ni begona raqamni egallab olsa bo'lardi.
    new_phone = data.get("phone")
    if new_phone:
        new_phone = to_db_phone(new_phone)
        data["phone"] = new_phone
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


@router.post("/me/avatar", response_model=UserRead)
def upload_avatar(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Pr2 «Rasmni o'zgartirish». Старое фото удаляется с диска."""
    url = save_upload(file, "avatars")
    old = current_user.avatar_url
    current_user.avatar_url = url
    db.commit()
    db.refresh(current_user)
    if old:
        delete_by_url(old)
    return current_user


# ------------------------------------------------ Pr4 · Saqlangan manzillar

MAX_ADDRESSES = 20


class AddressIn(BaseModel):
    kind: str = "other"
    title: str = Field(min_length=1, max_length=60)
    address: str = Field(min_length=1, max_length=500)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


def _address_out(a: UserAddress) -> dict:
    return dict(id=a.id, kind=a.kind, title=a.title, address=a.address,
                latitude=float(a.latitude), longitude=float(a.longitude))


def _check_kind(kind: str) -> None:
    if kind not in ADDRESS_KINDS:
        raise HTTPException(400, "Manzil turi noto'g'ri")


@router.get("/me/addresses")
def list_addresses(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    rows = (
        db.query(UserAddress).filter(UserAddress.user_id == current_user.id)
        .order_by(UserAddress.id).all()
    )
    return [_address_out(a) for a in rows]


@router.post("/me/addresses")
def add_address(data: AddressIn, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    _check_kind(data.kind)
    count = db.query(UserAddress).filter(UserAddress.user_id == current_user.id).count()
    if count >= MAX_ADDRESSES:
        raise HTTPException(400, f"{MAX_ADDRESSES} tadan ortiq manzil saqlab bo'lmaydi")
    a = UserAddress(user_id=current_user.id, **data.dict())
    db.add(a)
    db.commit()
    db.refresh(a)
    return _address_out(a)


def _own_address(db: Session, user: User, address_id: int) -> UserAddress:
    a = db.query(UserAddress).filter(UserAddress.id == address_id).first()
    # Чужой адрес — как несуществующий: id не подсказывают, что он есть
    if a is None or a.user_id != user.id:
        raise HTTPException(404, "Manzil topilmadi")
    return a


@router.put("/me/addresses/{address_id}")
def update_address(address_id: int, data: AddressIn, db: Session = Depends(get_db),
                   current_user: User = Depends(get_current_user)):
    _check_kind(data.kind)
    a = _own_address(db, current_user, address_id)
    for k, v in data.dict().items():
        setattr(a, k, v)
    db.commit()
    db.refresh(a)
    return _address_out(a)


@router.delete("/me/addresses/{address_id}")
def delete_address(address_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    a = _own_address(db, current_user, address_id)
    db.delete(a)
    db.commit()
    return {"ok": True}


@router.get("/me/deletion-check")
def account_deletion_check(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Hisobni hozir o'chirish mumkinmi. Ilova tasdiqlash oynasidan OLDIN
    so'raydi: odam "o'chirish"ni bosib, keyin "pulingiz bor" deb rad
    javobini olmasin.
    """
    reasons = account_deletion_service.blockers(db, current_user)
    return {
        "can_delete": not reasons,
        "reasons": [t(key, current_user.language) for key in reasons],
    }


@router.delete("/me")
def delete_current_user(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    O'z hisobini o'chirish (Google Play talabi). Anonimlashtirish — qarang:
    app/services/account_deletion_service.py. Pul yoki tugallanmagan bitim
    bo'lsa 409.
    """
    lang = current_user.language
    account_deletion_service.delete_account(db, current_user)
    return {"detail": t("account_delete.done", lang)}


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


# ============================================================ Admin P4 (panel)
from typing import Optional  # noqa: E402

from app.core.internal_auth import require_internal_admin  # noqa: E402
from app.services import user_admin_service  # noqa: E402


class _BlockIn(BaseModel):
    admin_id: Optional[int] = None
    reason: str = Field(max_length=20)
    duration: str = Field(max_length=10)
    note: Optional[str] = Field(default=None, max_length=1000)
    sms_text: Optional[str] = Field(default=None, max_length=300)
    cancel_active: bool = False
    send_sms: bool = False


class _AdminIn(BaseModel):
    admin_id: Optional[int] = None


class _UnblockIn(BaseModel):
    admin_id: Optional[int] = None
    send_sms: bool = False


class _MessageIn(BaseModel):
    admin_id: Optional[int] = None
    text: str = Field(min_length=1, max_length=1000)
    sms: bool = False


@router.get("/internal/{user_id}/active-orders")
def internal_active_orders(user_id: int, db: Session = Depends(get_db), _a=Depends(require_internal_admin)):
    """C3/H4: bloklashdan oldin — faol buyurtmalar (mijoz yoki ijrochi sifatida)."""
    return user_admin_service.active_orders(db, user_id)


@router.post("/internal/{user_id}/block")
def internal_block(user_id: int, data: _BlockIn, db: Session = Depends(get_db),
                   _a=Depends(require_internal_admin)):
    return user_admin_service.block(db, user_id, data.admin_id, data.reason, data.duration,
                                    data.note, data.sms_text, data.cancel_active, data.send_sms)


@router.post("/internal/{user_id}/unblock")
def internal_unblock(user_id: int, data: _UnblockIn, db: Session = Depends(get_db),
                     _a=Depends(require_internal_admin)):
    return user_admin_service.unblock(db, user_id, data.admin_id, data.send_sms)


@router.post("/internal/{user_id}/message")
def internal_message(user_id: int, data: _MessageIn, db: Session = Depends(get_db),
                     _a=Depends(require_internal_admin)):
    return user_admin_service.message(db, user_id, data.admin_id, data.text, data.sms)
