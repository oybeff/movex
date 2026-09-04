"""
Qurilish materiallari: /materials/*

Ijaradan farqi — tovar sotib olinadi, ijaraga olinmaydi. Narxni SERVER
sanaydi; so'rovdan kelgan summa umuman o'qilmaydi.

DIQQAT: aniq yo'llar parametrli yo'ldan OLDIN turishi shart.
/materials/types, /materials/vehicles, /materials/products/mine —
/materials/products/{product_id} dan yuqorida. Loyihada shu xato uch
marta bo'lgan.
"""
from typing import List, Optional

from fastapi import APIRouter, Depends, File, Query, UploadFile
from sqlalchemy.orm import Session

from app.core import delivery_vehicles, material_types, media
from app.core.account_state import assert_not_frozen
from app.core.roles import role_checker
from app.db.session import get_db
from app.models.material import MaterialOrder, MaterialProduct
from app.models.user import User
from app.routes.auth import get_current_user
from app.schemas.material import (
    DeliveryVehicleRead,
    MaterialModerate,
    MaterialOrderCreate,
    MaterialOrderRead,
    MaterialProductCreate,
    MaterialProductRead,
    MaterialProductUpdate,
    MaterialQuoteRead,
    MaterialQuoteRequest,
    MaterialTypeRead,
)
from app.services import material_service, pricing_service

router = APIRouter()


def _as_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _product_to_read(db: Session, product: MaterialProduct, viewer: User) -> MaterialProductRead:
    data = MaterialProductRead.model_validate(product)

    owner = db.query(User).filter(User.id == product.owner_id).first()
    data.owner_name = owner.full_name if owner else None

    v_lat, v_lon = _as_float(viewer.search_latitude), _as_float(viewer.search_longitude)
    p_lat, p_lon = _as_float(product.latitude), _as_float(product.longitude)
    if None not in (v_lat, v_lon, p_lat, p_lon):
        data.distance_km = float(pricing_service.distance_km(v_lat, v_lon, p_lat, p_lon))

    return data


def _order_to_read(db: Session, order: MaterialOrder) -> MaterialOrderRead:
    data = MaterialOrderRead.model_validate(order)

    product = (
        db.query(MaterialProduct).filter(MaterialProduct.id == order.product_id).first()
    )
    if product is not None:
        data.product_title = product.title
        data.material_type = product.material_type

    buyer = db.query(User).filter(User.id == order.buyer_id).first()
    seller = db.query(User).filter(User.id == order.seller_id).first()
    data.buyer_name = buyer.full_name if buyer else None
    data.seller_name = seller.full_name if seller else None
    return data


# ------------------------------------------------- ma'lumotnomalar avval

@router.get("/types", response_model=List[MaterialTypeRead])
def material_type_list():
    """
    Material turlari. Nomi ilovada tarjimadan olinadi — bu yerda faqat
    kod va standart qiymatlar, texnika turlaridagi bilan bir xil qoida.
    """
    return [
        MaterialTypeRead(
            code=code,
            default_unit=material_types.TYPES[code].unit,
            default_unit_weight_kg=material_types.TYPES[code].unit_weight_kg,
        )
        for code in material_types.CODES
    ]


@router.get("/vehicles", response_model=List[DeliveryVehicleRead])
def vehicle_list():
    """Yetkazadigan mashinalar va ularning sig'imi."""
    return [
        DeliveryVehicleRead(code=v.code, capacity_kg=v.capacity_kg)
        for v in delivery_vehicles.VEHICLES
    ]


# ---------------------------------------------------------------- tovarlar

@router.get("/products/mine", response_model=List[MaterialProductRead])
def my_products(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    Sotuvchining o'z tovarlari — moderatsiyada turganlari bilan.

    Yo'l "/products/{product_id}" dan OLDIN turishi shart.
    """
    items = material_service.list_own_products(db, current_user)
    return [_product_to_read(db, item, current_user) for item in items]


@router.post("/products/photos")
def upload_product_photo(
    file: UploadFile = File(...),
    current_user=Depends(get_current_user),
):
    """Rasm tovar yaratilishidan OLDIN yuklanadi — e'lonlardagi kabi."""
    assert_not_frozen(current_user)
    return {"url": media.save_upload(file, "materials")}


@router.get("/products", response_model=List[MaterialProductRead])
def catalog(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    material_type: Optional[str] = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
):
    """Katalog — faqat tasdiqlangan tovarlar."""
    items = material_service.list_catalog(db, material_type, skip, limit)
    return [_product_to_read(db, item, current_user) for item in items]


@router.post("/products", response_model=MaterialProductRead)
def create_product(
    data: MaterialProductCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    Tovar qo'shish.

    ROL TEKSHIRILMAYDI: material sotuvchi texnika egasi bo'lishi shart
    emas. Cheklov moderatsiyada — tovar admin tasdiqlagunicha katalogda
    ko'rinmaydi.
    """
    product = material_service.create_product(db, current_user, data)
    return _product_to_read(db, product, current_user)


@router.get("/products/{product_id}", response_model=MaterialProductRead)
def product_detail(
    product_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    product = material_service.get_product(db, product_id, current_user)
    return _product_to_read(db, product, current_user)


@router.put("/products/{product_id}", response_model=MaterialProductRead)
def update_product(
    product_id: int,
    data: MaterialProductUpdate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Tahrirlangan tovar QAYTA moderatsiyaga tushadi."""
    product = material_service.update_product(db, product_id, current_user, data)
    return _product_to_read(db, product, current_user)


@router.delete("/products/{product_id}")
def delete_product(
    product_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    material_service.delete_product(db, product_id, current_user)
    return {"status": "ok"}


@router.post("/products/{product_id}/moderate", response_model=MaterialProductRead)
def moderate_product(
    product_id: int,
    data: MaterialModerate,
    db: Session = Depends(get_db),
    current_user=Depends(role_checker(["admin"])),
):
    """Tasdiqlash yoki rad etish — faqat admin."""
    product = material_service.moderate(db, product_id, data.approve, data.comment)
    return _product_to_read(db, product, current_user)


# ------------------------------------------------------------------ hisob

@router.post("/quote", response_model=MaterialQuoteRead)
def quote(
    data: MaterialQuoteRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    Ekrandagi jonli hisob: miqdor → og'irlik → mashina → reyslar →
    yetkazib berish → jami. Buyurtma yaratilmaydi.

    Buyurtma berilganda AYNAN shu funksiya qayta chaqiriladi, shuning
    uchun ekrandagi summa bilan balansdan yechilgani doim bir xil.
    """
    product = material_service.get_product(db, data.product_id, current_user)
    result = material_service.calculate(
        db,
        product,
        data.quantity,
        data.delivery_latitude,
        data.delivery_longitude,
        data.vehicle_code,
    )
    return MaterialQuoteRead(
        quantity=result.quantity,
        unit=product.unit,
        price_per_unit=result.price_per_unit,
        goods_amount=result.goods_amount,
        weight_kg=result.weight_kg,
        vehicle_code=result.vehicle_code,
        vehicle_capacity_kg=result.vehicle_capacity_kg,
        trips=result.trips,
        delivery_distance_km=result.distance_km,
        delivery_fee=result.delivery_fee,
        total=result.total,
    )


# ------------------------------------------------------------ buyurtmalar

@router.get("/orders", response_model=List[MaterialOrderRead])
def my_orders(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    as_seller: bool = Query(False, description="sotuvchi sifatida"),
):
    items = material_service.list_orders(db, current_user, as_seller)
    return [_order_to_read(db, item) for item in items]


@router.post("/orders", response_model=MaterialOrderRead)
def create_order(
    data: MaterialOrderCreate,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Buyurtma: summa serverda sanaladi va balansda muzlatiladi."""
    order = material_service.create_order(db, current_user, data)
    return _order_to_read(db, order)


@router.post("/orders/{order_id}/confirm", response_model=MaterialOrderRead)
def confirm_order(
    order_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Sotuvchi qabul qiladi. Pul hali qimirlamaydi."""
    return _order_to_read(db, material_service.confirm_order(db, order_id, current_user))


@router.post("/orders/{order_id}/deliver", response_model=MaterialOrderRead)
def deliver_order(
    order_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    Yetkazildi — pul shu yerda harakat qiladi.

    Tugmani XARIDOR bosadi: sotuvchi o'zi bosa olganida, yetkazmasdan
    turib pulni olib qo'ya olardi.
    """
    return _order_to_read(db, material_service.deliver_order(db, order_id, current_user))


@router.post("/orders/{order_id}/cancel", response_model=MaterialOrderRead)
def cancel_order(
    order_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Xaridor bekor qiladi — muzlatish olib tashlanadi."""
    return _order_to_read(
        db, material_service.cancel_order(db, order_id, current_user, reject=False)
    )


@router.post("/orders/{order_id}/reject", response_model=MaterialOrderRead)
def reject_order(
    order_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """Sotuvchi rad etadi — muzlatish olib tashlanadi."""
    return _order_to_read(
        db, material_service.cancel_order(db, order_id, current_user, reject=True)
    )
