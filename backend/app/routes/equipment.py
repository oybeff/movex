# app/routes/equipment.py
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Query
from sqlalchemy.orm import Session, selectinload
from typing import List, Optional, Tuple
from app.db.session import get_db
from app.models.equipment import Equipment, EquipmentPhoto
from app.models.order import Order
from app.models.user import User
from app.schemas.equipment import EquipmentCreate, EquipmentRead, EquipmentUpdate, EquipmentPhotoRead
from app.routes.auth import get_current_user
from app.core.roles import role_checker
from app.core.equipment_types import EQUIPMENT_TYPES, normalize_type
import os
from datetime import date, datetime

router = APIRouter()

MEDIA_DIR = "media/equipment"
os.makedirs(MEDIA_DIR, exist_ok=True)

def paginate(query, page: int, limit: int) -> Tuple[List[Equipment], int]:
    total = query.count()
    items = query.offset((page-1)*limit).limit(limit).all()
    return items, total

@router.post("/", response_model=EquipmentRead)
def create_equipment(
    equipment_in: EquipmentCreate,
    db: Session = Depends(get_db),
    current_user = Depends(role_checker(["owner","admin"]))
):
    # owner_id берём из текущего пользователя
    data = equipment_in.dict()
    # Turni kodga keltiramiz: eski mobil ilovalar hali erkin matn yuboradi.
    data["type"] = normalize_type(data.get("type"))
    eq = Equipment(**data, owner_id=current_user.id)
    db.add(eq)
    db.commit()
    db.refresh(eq)
    return eq

@router.get("/", response_model=List[EquipmentRead])
def list_equipment(
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user),
    owner_only: bool = Query(False),
    type: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    search: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100)
):
    # selectinload: rasmlar bitta qo'shimcha so'rov bilan yuklanadi.
    # Ilgari har bir texnika uchun alohida so'rov ketardi — 100 ta
    # texnika = 101 ta so'rov (N+1).
    q = (
        db.query(Equipment)
        .options(selectinload(Equipment.photos))
        .filter(Equipment.deleted_at.is_(None))
    )

    if owner_only and current_user.role == "owner":
        q = q.filter(Equipment.owner_id == current_user.id)

    if type:
        # Tur endi ma'lumotnomadagi kod, shuning uchun aniq moslik
        q = q.filter(Equipment.type == normalize_type(type))
    if status:
        q = q.filter(Equipment.status == status)
    if search:
        like = f"%{search}%"
        q = q.filter((Equipment.model.ilike(like)) | (Equipment.description.ilike(like)))

    items, total = paginate(q.order_by(Equipment.created_at.desc()), page, limit)
    return items

# DIQQAT: bu route "/{equipment_id}" dan OLDIN turishi shart, aks holda
# FastAPI "types" so'zini equipment_id deb o'qishga urinadi.
@router.get("/types")
def list_equipment_types():
    """
    Texnika turlari ma'lumotnomasi. Mobil ilova va adminka shu ro'yxatdan
    foydalanadi — turlar erkin matn emas, qat'iy kodlar.
    """
    return EQUIPMENT_TYPES

@router.get("/{equipment_id}", response_model=EquipmentRead)
def get_equipment(
    equipment_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    eq = db.query(Equipment).filter(Equipment.id == equipment_id, Equipment.deleted_at.is_(None)).first()
    if not eq:
        raise HTTPException(404, "Equipment not found")
    return eq

@router.put("/{equipment_id}", response_model=EquipmentRead)
def update_equipment(
    equipment_id: int,
    equipment_in: EquipmentUpdate,
    db: Session = Depends(get_db),
    current_user = Depends(role_checker(["owner","admin"]))
):
    eq = db.query(Equipment).filter(Equipment.id == equipment_id, Equipment.deleted_at.is_(None)).first()
    if not eq:
        raise HTTPException(404, "Equipment not found")

    # Владелец — только свою технику
    if current_user.role == "owner" and eq.owner_id != current_user.id:
        raise HTTPException(403, "Forbidden")

    for field, value in equipment_in.dict(exclude_unset=True).items():
        if field == "type":
            value = normalize_type(value)
        setattr(eq, field, value)

    db.commit()
    db.refresh(eq)
    return eq

@router.delete("/{equipment_id}")
def delete_equipment(
    equipment_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(role_checker(["owner","admin"]))
):
    eq = db.query(Equipment).filter(Equipment.id == equipment_id, Equipment.deleted_at.is_(None)).first()
    if not eq:
        raise HTTPException(404, "Equipment not found")

    if current_user.role == "owner" and eq.owner_id != current_user.id:
        raise HTTPException(403, "Forbidden")

    eq.deleted_at = datetime.utcnow()
    db.commit()
    return {"detail": "Equipment soft-deleted"}

@router.post("/{equipment_id}/photos", response_model=EquipmentPhotoRead)
def upload_equipment_photo(
    equipment_id: int,
    file: UploadFile = File(...),
    is_primary: bool = Form(False),
    db: Session = Depends(get_db),
    current_user = Depends(role_checker(["owner","admin"]))
):
    eq = db.query(Equipment).filter(Equipment.id == equipment_id, Equipment.deleted_at.is_(None)).first()
    if not eq:
        raise HTTPException(404, "Equipment not found")

    if current_user.role == "owner" and eq.owner_id != current_user.id:
        raise HTTPException(403, "Forbidden")

    # сохраняем файл локально (для прода лучше S3/YA Object Storage)
    ext = os.path.splitext(file.filename)[1].lower()
    fname = f"{equipment_id}_{datetime.utcnow().timestamp()}{ext}"
    path = os.path.join(MEDIA_DIR, fname)
    with open(path, "wb") as f:
        f.write(file.file.read())

    url = f"/static/equipment/{fname}"  # Настрой статику в FastAPI (StaticFiles)

    photo = EquipmentPhoto(equipment_id=equipment_id, url=url, is_primary=is_primary)
    if is_primary:
        # сбросить прежние primary
        db.query(EquipmentPhoto        ).filter(
            EquipmentPhoto.equipment_id == equipment_id,
            EquipmentPhoto.is_primary == True
        ).update({"is_primary": False})

    db.add(photo)
    db.commit()
    db.refresh(photo)
    return photo


@router.get("/{equipment_id}/active_order")
def get_active_order(
    equipment_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    """
    Texnikaning hozir bajarilayotgan buyurtmasi.

    Ilgari bu endpoint hech qachon ishlamasdi: u `status == "active"` bo'yicha
    qidirardi, lekin bunday holat tizimda umuman yo'q (pending, confirmed,
    rejected, cancelled, completed). Ustiga javobda order.title va
    order.client_name qaytarilardi — Order modelida bunday maydonlar yo'q,
    ya'ni moslik topilganda 500 xato bo'lardi.

    Endi "faol" degani: tasdiqlangan buyurtma, bugungi sana uning
    oralig'iga tushadi.
    """
    eq = db.query(Equipment).filter(
        Equipment.id == equipment_id,
        Equipment.deleted_at.is_(None)
    ).first()
    if not eq:
        raise HTTPException(404, "Equipment not found")

    # Kim ijaraga olganini faqat texnika egasi va admin ko'radi
    if current_user.role != "admin" and eq.owner_id != current_user.id:
        raise HTTPException(403, "Forbidden")

    today = date.today()
    order = (
        db.query(Order)
        .filter(
            Order.equipment_id == equipment_id,
            Order.status == "confirmed",
            Order.start_date <= today,
            Order.end_date >= today,
        )
        .order_by(Order.start_date)
        .first()
    )

    if not order:
        return {"currentOrder": None}

    client = db.query(User).filter(User.id == order.user_id).first()

    return {
        "currentOrder": {
            "id": order.id,
            "status": order.status,
            "start_date": order.start_date.isoformat(),
            "end_date": order.end_date.isoformat(),
            "total_amount": float(order.total_amount),
            "client": {
                "id": client.id if client else None,
                "full_name": client.full_name if client else None,
                "phone": client.phone if client else None,
            },
        }
    }


@router.get("/{equipment_id}/photos", response_model=List[EquipmentPhotoRead])
def list_equipment_photos(
    equipment_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    eq = db.query(Equipment).filter(Equipment.id == equipment_id, Equipment.deleted_at.is_(None)).first()
    if not eq:
        raise HTTPException(404, "Equipment not found")

    return eq.photos

@router.delete("/photos/{photo_id}")
def delete_equipment_photo(
    photo_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(role_checker(["owner","admin"]))
):
    photo = db.query(EquipmentPhoto).filter(EquipmentPhoto.id == photo_id).first()
    if not photo:
        raise HTTPException(404, "Photo not found")

    eq = db.query(Equipment).filter(Equipment.id == photo.equipment_id).first()
    if not eq:
        raise HTTPException(404, "Equipment not found")

    if current_user.role == "owner" and eq.owner_id != current_user.id:
        raise HTTPException(403, "Forbidden")

    # удалить файл с диска
    if photo.url.startswith("/static/equipment/"):
        fname = photo.url.replace("/static/equipment/", "")
        path = os.path.join(MEDIA_DIR, fname)
        if os.path.exists(path):
            os.remove(path)

    db.delete(photo)
    db.commit()
    return {"detail": "Photo deleted"}


@router.get("/{equipment_id}/booked-dates")
def get_booked_dates(
    equipment_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    """
    Texnikaning barcha band sanalarini olish

    Returns:
    - status: texnikaning hozirgi holati
    - booked_ranges: band bo'lgan sana oraliqlari
    """
    # Texnikani topish
    eq = db.query(Equipment).filter(
        Equipment.id == equipment_id,
        Equipment.deleted_at.is_(None)
    ).first()

    if not eq:
        raise HTTPException(404, "Texnika topilmadi")

    # Faol buyurtmalarni olish
    active_orders = db.query(Order).filter(
        Order.equipment_id == equipment_id,
        Order.status.in_(["pending", "confirmed"])
    ).order_by(Order.start_date).all()

    booked_ranges = [
        {
            "start_date": order.start_date.isoformat(),
            "end_date": order.end_date.isoformat(),
            "order_id": order.id,
            "status": order.status
        }
        for order in active_orders
    ]

    return {
        "equipment_id": equipment_id,
        "equipment_status": eq.status,
        "booked_ranges": booked_ranges
    }


@router.get("/{equipment_id}/availability")
def check_equipment_availability(
    equipment_id: int,
    start_date: str = Query(..., description="Boshlanish sanasi (YYYY-MM-DD)"),
    end_date: str = Query(..., description="Tugash sanasi (YYYY-MM-DD)"),
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user)
):
    """
    Texnikaning ma'lum sana oralig'ida bo'shligini tekshirish

    Returns:
    - available: true/false - texnika bu sanada bo'shmi
    - status: texnikaning hozirgi holati (available, busy, maintenance)
    - conflicting_orders: agar band bo'lsa, qaysi buyurtmalar bilan to'qnashayotgani
    """
    from datetime import datetime

    # Texnikani topish
    eq = db.query(Equipment).filter(
        Equipment.id == equipment_id,
        Equipment.deleted_at.is_(None)
    ).first()

    if not eq:
        raise HTTPException(404, "Texnika topilmadi")

    # Sanalarni parse qilish
    try:
        start = datetime.strptime(start_date, "%Y-%m-%d").date()
        end = datetime.strptime(end_date, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(400, "Noto'g'ri sana formati. YYYY-MM-DD formatida bo'lishi kerak")

    if end < start:
        raise HTTPException(400, "Tugash sanasi boshlanish sanasidan kichik bo'lishi mumkin emas")

    # 1. Texnikaning hozirgi holatini tekshirish
    if eq.status in ['busy', 'maintenance']:
        return {
            "available": False,
            "status": eq.status,
            "reason": f"Texnika hozirda {eq.status} holatida",
            "conflicting_orders": []
        }

    # 2. Sana oralig'ida faol buyurtmalar borligini tekshirish
    # Overlap logic: (start1 <= end2) AND (end1 >= start2)
    conflicting_orders = db.query(Order).filter(
        Order.equipment_id == equipment_id,
        Order.status.in_(["pending", "confirmed"]),
        Order.start_date <= end,
        Order.end_date >= start
    ).all()

    if conflicting_orders:
        return {
            "available": False,
            "status": eq.status,
            "reason": "Bu sana oralig'ida boshqa buyurtmalar mavjud",
            "conflicting_orders": [
                {
                    "order_id": order.id,
                    "start_date": order.start_date.isoformat(),
                    "end_date": order.end_date.isoformat(),
                    "status": order.status
                }
                for order in conflicting_orders
            ]
        }

    # 3. Texnika bo'sh
    return {
        "available": True,
        "status": eq.status,
        "reason": "Texnika bu sana oralig'ida bo'sh",
        "conflicting_orders": []
    }


@router.patch("/{equipment_id}/status")
def update_equipment_status(
    equipment_id: int,
    status: str = Query(..., description="Yangi holat: available, busy, maintenance"),
    db: Session = Depends(get_db),
    current_user = Depends(role_checker(["owner","admin"]))
):
    """
    Texnika holatini o'zgartirish (Owner tomonidan qo'lda)

    Shartlar:
    - Faqat owner o'z texnikasini o'zgartira oladi
    - Ruxsat etilgan holatlar: available, busy, maintenance

    Eslatma:
    - Owner texnikani istalgan vaqtda busy yoki maintenance holatiga o'tkazishi mumkin
    - Bu holat buyurtmalardan mustaqil (owner qo'lda boshqaradi)
    """
    # Texnikani topish
    eq = db.query(Equipment).filter(
        Equipment.id == equipment_id,
        Equipment.deleted_at.is_(None)
    ).first()

    if not eq:
        raise HTTPException(404, "Texnika topilmadi")

    # Owner tekshiruvi
    if current_user.role == "owner" and eq.owner_id != current_user.id:
        raise HTTPException(403, "Sizning texnikangiz emas")

    # Status validatsiyasi
    valid_statuses = ["available", "busy", "maintenance"]
    if status not in valid_statuses:
        raise HTTPException(400, f"Noto'g'ri holat. Ruxsat etilgan: {', '.join(valid_statuses)}")

    # Holatni o'zgartirish (faol buyurtma tekshiruvini olib tashladik)
    eq.status = status

    # available flag'ni ham yangilash
    eq.available = (status == "available")

    db.commit()
    db.refresh(eq)

    return {
        "message": "Texnika holati muvaffaqiyatli o'zgartirildi",
        "equipment_id": equipment_id,
        "new_status": status
    }

