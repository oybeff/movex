from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime, date
from app.schemas import order as order_schema
from app.models import order as order_model
from app.services import order_service, pricing_service
from app.models.equipment import Equipment
from app.dependencies import get_db, get_current_user
from app.core.access import assert_order_access
from app.core.roles import role_checker

router = APIRouter()

@router.post("/", response_model=order_schema.OrderRead)
def create_order(order: order_schema.OrderCreate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return order_service.create_order(db, order, current_user.id)


# DIQQAT: "/{order_id}" dan OLDIN turishi shart
@router.post("/price-preview", response_model=order_schema.OrderPricePreview)
def preview_order_price(
    request: order_schema.OrderPriceRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    Buyurtma narxini oldindan hisoblab beradi — buyurtma yaratmasdan.

    Ilgari narx IKKI joyda hisoblanardi: mobil ilova ekranda ko'rsatish
    uchun, server esa yechib olish uchun. Formulalar bir-biridan biroz
    farq qilsa (masalan, ilova kunlik narxni butun songa keltirsa),
    foydalanuvchi ekranda bir summani ko'rib, hisobidan boshqasi yechilardi.

    Endi ilova shu yerdan olingan raqamni ko'rsatadi — hisob bitta joyda.
    """
    equipment = db.query(Equipment).filter(
        Equipment.id == request.equipment_id,
        Equipment.deleted_at.is_(None),
    ).first()
    if not equipment:
        raise HTTPException(status_code=404, detail="Texnika topilmadi")

    try:
        price = pricing_service.calculate_order_price(
            db=db,
            equipment=equipment,
            start_date=request.start_date,
            end_date=request.end_date,
            delivery_latitude=request.delivery_latitude,
            delivery_longitude=request.delivery_longitude,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    return order_schema.OrderPricePreview(
        days=price.days,
        subtotal=float(price.subtotal),
        commission=float(price.commission),
        delivery_distance=float(price.delivery_distance) if price.delivery_distance is not None else None,
        delivery_fee=float(price.delivery_fee),
        total=float(price.total),
    )

@router.get("/", response_model=list[order_schema.OrderRead])
def get_orders(skip: int = 0, limit: int = 100, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """
    Faqat O'ZIGA tegishli buyurtmalar: mijoz sifatida bergan yoki
    o'z texnikasiga kelgan. Admin hammasini ko'radi.

    Ilgari bu yerda butun tizimdagi barcha buyurtmalar qaytarilardi —
    summalari va yetkazib berish manzillari bilan birga.
    """
    return order_service.get_orders(db, skip, limit, current_user)

@router.get("/{order_id}", response_model=order_schema.OrderRead)
def get_order(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    db_order = order_service.get_order(db, order_id)
    if not db_order:
        raise HTTPException(status_code=404, detail="Order not found")
    assert_order_access(db, db_order, current_user)
    return db_order

@router.put("/{order_id}", response_model=order_schema.OrderRead)
def update_order(order_id: int, order: order_schema.OrderUpdate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """
    Buyurtma statusini o'zgartirish

    - pending -> confirmed: Egasi tasdiqladi (faqat equipment egasi)
    - pending -> rejected: Egasi rad etdi (faqat equipment egasi)
    - pending -> cancelled: Client bekor qildi (faqat buyurtma egasi)
    - confirmed -> completed: Ish yakunlandi
    """
    return order_service.update_order(db, order_id, order, current_user.id)


@router.delete("/{order_id}", response_model=dict)
def delete_order(order_id: int, db: Session = Depends(get_db), current_user=Depends(role_checker(["admin"]))):
    """
    Buyurtmani o'chirish — faqat admin.

    Ilgari buni har qanday foydalanuvchi qila olardi, hatto begona
    buyurtmani ham. Bundan tashqari muzlatilgan pul hisobda abadiy
    qolib ketardi — endi o'chirishdan oldin qaytariladi.
    """
    deleted = order_service.delete_order(db, order_id)
    if deleted is None:
        raise HTTPException(status_code=404, detail="Order not found")
    return {"message": "Order deleted successfully"}


@router.get("/statistics/summary", response_model=dict)
def get_order_statistics(
    start_date: Optional[date] = Query(None, description="Boshlanish sanasi (YYYY-MM-DD)"),
    end_date: Optional[date] = Query(None, description="Tugash sanasi (YYYY-MM-DD)"),
    status: Optional[str] = Query(None, description="Buyurtma holati filter"),
    equipment_id: Optional[int] = Query(None, description="Texnika ID filter"),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    """
    Buyurtmalar statistikasini olish (faqat owner uchun)

    Returns:
    - total_orders: Jami buyurtmalar soni
    - total_income: Jami daromad
    - orders_by_status: Status bo'yicha buyurtmalar
    - orders_by_date: Sana bo'yicha buyurtmalar
    - orders_by_equipment: Texnika bo'yicha buyurtmalar
    """
    return order_service.get_order_statistics(
        db=db,
        owner_id=current_user.id,
        start_date=start_date,
        end_date=end_date,
        status=status,
        equipment_id=equipment_id
    )
