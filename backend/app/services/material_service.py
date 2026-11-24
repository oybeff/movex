"""
Qurilish materiallari: katalog, moderatsiya, buyurtma va pul.

NARXNI FAQAT SERVER HISOBLAYDI. So'rov tanasidan kelgan summa umuman
o'qilmaydi — bu loyihada allaqachon bo'lgan xato: mijoz o'z narxini
yuborardi va server ishonardi, ekskavator bir oyga 1 000 so'mga ketardi.
Bu yerda ham xuddi shunday: xaridor faqat NIMA va QANCHA kerakligini
aytadi, qolganini server sanaydi.

Pul harakati ijaradagi bilan bir xil:
    buyurtma berilganda — summa xaridor balansida MUZLATILADI;
    yetkazilganda      — balansdan yechiladi va sotuvchiga o'tadi;
    bekor/rad qilinganda — faqat muzlatish olib tashlanadi.

Ikkinchi va uchinchi holatni chalkashtirish — pul chop etish demakdir.

Ulushni SOTUVCHI to'laydi: xaridor tovar va yetkazib berish uchun
to'laydi, platforma ulushi esa sotuvchining puliga tushmasdan qoladi.
Ijaradagi qoida bilan bir xil, boshqacha qilishning sababi yo'q.
"""
from app.core.messages import insufficient_funds
import logging
from decimal import Decimal, ROUND_HALF_UP
from typing import List, Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session, selectinload

from app.core import delivery_vehicles, material_types, media
from app.core.account_state import assert_not_frozen
from app.models.balance import Balance, BalanceTransaction
from app.models.material import MAX_MATERIAL_PHOTOS, MaterialOrder, MaterialPhoto, MaterialProduct
from app.models.user import User
from app.services import delivery_service, notification_service, pricing_service
from app.services.balance_service import get_or_create_balance

logger = logging.getLogger(__name__)


def _round(value: Decimal) -> Decimal:
    return value.quantize(Decimal("1"), rounding=ROUND_HALF_UP)


def _dec(value, default: str = "0") -> Decimal:
    if value is None:
        return Decimal(default)
    return Decimal(str(value))


# ----------------------------------------------------------------- hisob

class Quote:
    """
    Buyurtmaning hisob-kitobi. Bazaga yozilmaydi — ilova ekranda shuni
    ko'rsatadi, buyurtma berilganda esa AYNAN shu funksiya qayta
    chaqiriladi. Ikki xil formula bo'lsa, ekranda bir summa, balansdan
    boshqasi ketardi.
    """

    def __init__(
        self,
        quantity: Decimal,
        price_per_unit: Decimal,
        goods_amount: Decimal,
        weight_kg: Decimal,
        vehicle_code: str,
        vehicle_capacity_kg: int,
        trips: int,
        distance_km: Optional[Decimal],
        delivery_fee: Decimal,
        commission: Decimal,
        total: Decimal,
    ):
        self.quantity = quantity
        self.price_per_unit = price_per_unit
        self.goods_amount = goods_amount
        self.weight_kg = weight_kg
        self.vehicle_code = vehicle_code
        self.vehicle_name: Optional[str] = None
        self.vehicle_capacity_kg = vehicle_capacity_kg
        self.trips = trips
        self.distance_km = distance_km
        self.delivery_fee = delivery_fee
        self.commission = commission
        self.total = total


def to_units(product: MaterialProduct, quantity, input_unit: Optional[str]) -> Decimal:
    """
    Mijoz miqdorni tovar birligida (m³, dona…) yoki TONNADA yozishi mumkin
    (Sherzodbek 24.11.2026: «1 m3 emas tonnada hisoblanadi»). Tonna —
    tovarning bir birlik og'irligi (unit_weight_kg) orqali birlikka
    aylantiriladi; buyurtma, narx va eng kam miqdor — doim tovar birligida.
    """
    q = _dec(quantity)
    if input_unit in (None, "", "unit") or product.unit == "tonne":
        return q
    if input_unit != "tonne":
        raise HTTPException(400, "Birlik noto'g'ri")
    weight = _dec(product.unit_weight_kg)
    if weight <= 0:
        raise HTTPException(400, "Bu tovarni tonnada buyurtma qilib bo'lmaydi")
    return (q * Decimal("1000") / weight).quantize(Decimal("0.01"))


def calculate(
    db: Session,
    product: MaterialProduct,
    quantity: Decimal,
    delivery_latitude: Optional[float] = None,
    delivery_longitude: Optional[float] = None,
    preferred_vehicle: Optional[str] = None,
) -> Quote:
    """Buyurtmaning to'liq hisobi. Buyurtma yaratishda ham shu ishlatiladi."""
    quantity = _dec(quantity).quantize(Decimal("0.01"))
    if quantity <= 0:
        raise HTTPException(400, "Miqdor noldan katta bo'lishi kerak")

    min_quantity = _dec(product.min_quantity, "1")
    if quantity < min_quantity:
        raise HTTPException(
            400, f"Eng kam buyurtma: {float(min_quantity)} {product.unit}"
        )

    if product.available_quantity is not None:
        available = _dec(product.available_quantity)
        if quantity > available:
            raise HTTPException(
                400, f"Omborda faqat {float(available)} {product.unit} bor"
            )

    price_per_unit = _dec(product.price_per_unit)
    goods_amount = _round(price_per_unit * quantity)

    # Og'irlik → mashina. Foydalanuvchi boshqa mashina tanlagan bo'lsa,
    # uniki ishlatiladi: u yo'lni va joyni bizdan yaxshiroq biladi.
    weight_kg = (_dec(product.unit_weight_kg) * quantity).quantize(Decimal("0.01"))
    plan = delivery_vehicles.choose(
        weight_kg, preferred_vehicle, delivery_vehicles.load(db)
    )

    # Yetkazib berish — texnikadagi formula bilan bir xil: masofa × tarif.
    # Farqi bitta: reyslar soniga ko'paytiriladi.
    distance: Optional[Decimal] = None
    delivery_fee = Decimal("0")

    from_lat, from_lon = _to_float(product.latitude), _to_float(product.longitude)
    if None not in (from_lat, from_lon, delivery_latitude, delivery_longitude):
        distance = pricing_service.distance_km(
            from_lat, from_lon, delivery_latitude, delivery_longitude
        ).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        # Narxni admin mashinaga qo'ygan bo'lsa (vehicles.php) — u:
        # (podacha + km × narx) × reys. Qo'ymagan bo'lsa — eskicha,
        # sotuvchi tovarga yozgan km narxi.
        vehicle = plan.vehicle
        if vehicle.price_per_km is not None:
            delivery_fee = _round(
                (vehicle.base_fee + distance * vehicle.price_per_km) * Decimal(plan.trips)
            )
        elif product.delivery_price_per_km is not None:
            delivery_fee = _round(
                distance * _dec(product.delivery_price_per_km) * Decimal(plan.trips)
            )

    total = goods_amount + delivery_fee

    # Ulush sotuvchidan. Ijaradagi funksiya qayta ishlatiladi — sozlama
    # bitta bo'lsin, aks holda adminkada bitta joyni o'zgartirib, ikkinchisi
    # eski qoida bo'yicha ishlab qolardi.
    commission = pricing_service.calculate_commission(db, goods_amount, total)

    quote = Quote(
        quantity=quantity,
        price_per_unit=price_per_unit,
        goods_amount=goods_amount,
        weight_kg=weight_kg,
        vehicle_code=plan.code,
        vehicle_capacity_kg=plan.capacity_kg,
        trips=plan.trips,
        distance_km=distance,
        delivery_fee=delivery_fee,
        commission=commission,
        total=total,
    )
    quote.vehicle_name = plan.vehicle.name
    return quote


def _to_float(value) -> Optional[float]:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


# --------------------------------------------------------------- tovarlar

def create_product(db: Session, owner: User, data) -> MaterialProduct:
    assert_not_frozen(owner)

    if not material_types.is_valid_type(data.material_type):
        raise HTTPException(400, f"Material turi noto'g'ri: {data.material_type!r}")

    unit = data.unit or material_types.default_unit(data.material_type)
    if not material_types.is_valid_unit(unit):
        raise HTTPException(400, f"O'lchov birligi noto'g'ri: {unit!r}")

    unit_weight = (
        _dec(data.unit_weight_kg)
        if data.unit_weight_kg is not None
        else material_types.default_unit_weight(data.material_type)
    )
    if unit_weight <= 0:
        raise HTTPException(400, "Birlik og'irligi noldan katta bo'lishi kerak")

    photos = list(data.photos or [])
    if len(photos) > MAX_MATERIAL_PHOTOS:
        raise HTTPException(400, f"Rasmlar soni {MAX_MATERIAL_PHOTOS} tadan oshmasin")
    for url in photos:
        # Rasm manzili faqat SHU serverdan — e'lonlardagi bilan bir xil
        # qoida: aks holda begona saytdagi rasmni qo'yish mumkin bo'lardi.
        if not media.is_own_media(url):
            raise HTTPException(400, f"Rasm manzili noto'g'ri: {url[:80]!r}")

    product = MaterialProduct(
        owner_id=owner.id,
        material_type=data.material_type,
        title=(data.title or "").strip()[:150],
        description=(data.description or None),
        unit=unit,
        unit_weight_kg=unit_weight,
        price_per_unit=_dec(data.price_per_unit),
        min_quantity=_dec(data.min_quantity, "1"),
        available_quantity=(
            _dec(data.available_quantity) if data.available_quantity is not None else None
        ),
        delivery_price_per_km=(
            _dec(data.delivery_price_per_km)
            if data.delivery_price_per_km is not None
            else None
        ),
        address=(data.address or None),
        latitude=data.latitude,
        longitude=data.longitude,
        # Yangi tovar HAR DOIM moderatsiyada: katalog xaridor birinchi
        # ko'radigan joy, u yerdagi axlat butun bo'limni o'ldiradi.
        status=MaterialProduct.STATUS_PENDING,
    )
    db.add(product)
    db.flush()

    for url in photos:
        db.add(MaterialPhoto(product_id=product.id, url=url))

    db.commit()
    db.refresh(product)
    return product


def update_product(db: Session, product_id: int, owner: User, data) -> MaterialProduct:
    """
    Tovarni tahrirlash. Narx yoki og'irlik o'zgarsa — QAYTA moderatsiyaga
    tushadi: aks holda tasdiqlangan tovarni keyin istalgan narsaga
    almashtirib qo'yish mumkin bo'lardi.
    """
    product = _own_product(db, product_id, owner)

    if data.title is not None:
        product.title = data.title.strip()[:150]
    if data.description is not None:
        product.description = data.description or None
    if data.price_per_unit is not None:
        product.price_per_unit = _dec(data.price_per_unit)
    if data.unit_weight_kg is not None:
        product.unit_weight_kg = _dec(data.unit_weight_kg)
    if data.min_quantity is not None:
        product.min_quantity = _dec(data.min_quantity, "1")
    if data.available_quantity is not None:
        product.available_quantity = _dec(data.available_quantity)
    if data.delivery_price_per_km is not None:
        product.delivery_price_per_km = _dec(data.delivery_price_per_km)
    if data.address is not None:
        product.address = data.address or None
    if data.latitude is not None:
        product.latitude = data.latitude
    if data.longitude is not None:
        product.longitude = data.longitude

    product.status = MaterialProduct.STATUS_PENDING
    product.moderation_comment = None

    db.commit()
    db.refresh(product)
    return product


def delete_product(db: Session, product_id: int, owner: User) -> None:
    product = _own_product(db, product_id, owner)

    # Buyurtmasi bor tovarni o'chirib bo'lmaydi: pul harakati tarixi
    # qayerdan kelganini ko'rsatolmay qolardi.
    has_orders = (
        db.query(MaterialOrder).filter(MaterialOrder.product_id == product.id).first()
    )
    if has_orders is not None:
        raise HTTPException(
            400, "Bu tovarga buyurtmalar bor, o'chirib bo'lmaydi. Miqdorni 0 qiling"
        )

    db.delete(product)
    db.commit()


def _own_product(db: Session, product_id: int, user: User) -> MaterialProduct:
    product = (
        db.query(MaterialProduct).filter(MaterialProduct.id == product_id).first()
    )
    if product is None:
        raise HTTPException(404, "Tovar topilmadi")
    if product.owner_id != user.id and user.role != "admin":
        raise HTTPException(403, "Bu tovar sizniki emas")
    return product


def moderate(db: Session, product_id: int, approve: bool, comment: Optional[str] = None):
    """Admin tasdiqlaydi yoki rad etadi."""
    product = (
        db.query(MaterialProduct).filter(MaterialProduct.id == product_id).first()
    )
    if product is None:
        raise HTTPException(404, "Tovar topilmadi")

    product.status = (
        MaterialProduct.STATUS_APPROVED if approve else MaterialProduct.STATUS_REJECTED
    )
    product.moderation_comment = comment or None
    db.commit()
    db.refresh(product)

    notification_service.create_localized(
        db, product.owner_id,
        "material_moderated",
        "material_approved.title" if approve else "material_rejected.title",
        "material_approved.body" if approve else "material_rejected.body",
        None, None, None,
        title=product.title,
        reason=comment or "",
    )
    return product


def _with_photos(query):
    return query.options(selectinload(MaterialProduct.photos))


def list_catalog(
    db: Session,
    material_type: Optional[str] = None,
    skip: int = 0,
    limit: int = 50,
) -> List[MaterialProduct]:
    """Katalog — faqat TASDIQLANGAN tovarlar."""
    query = _with_photos(db.query(MaterialProduct)).filter(
        MaterialProduct.status == MaterialProduct.STATUS_APPROVED
    )
    if material_type:
        query = query.filter(MaterialProduct.material_type == material_type)
    return (
        query.order_by(MaterialProduct.created_at.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )


def list_own_products(db: Session, owner: User) -> List[MaterialProduct]:
    """Sotuvchining o'z tovarlari — moderatsiyada turganlari bilan birga."""
    return (
        _with_photos(db.query(MaterialProduct))
        .filter(MaterialProduct.owner_id == owner.id)
        .order_by(MaterialProduct.created_at.desc())
        .all()
    )


def get_product(db: Session, product_id: int, viewer: User) -> MaterialProduct:
    product = (
        _with_photos(db.query(MaterialProduct))
        .filter(MaterialProduct.id == product_id)
        .first()
    )
    if product is None:
        raise HTTPException(404, "Tovar topilmadi")
    # Tasdiqlanmagan tovarni faqat egasi va admin ko'radi.
    if product.status != MaterialProduct.STATUS_APPROVED:
        if viewer.id != product.owner_id and viewer.role != "admin":
            raise HTTPException(404, "Tovar topilmadi")
    return product


# ------------------------------------------------------------ buyurtmalar

def create_order(db: Session, buyer: User, data) -> MaterialOrder:
    """
    Buyurtma va eskrou.

    Summa SERVERDA sanaladi va xaridorning balansida muzlatiladi. Qator
    bloklanadi: bir vaqtda kelgan ikki buyurtma bitta pulni ikki marta
    band qilib qo'ymasligi kerak.
    """
    assert_not_frozen(buyer)

    product = (
        db.query(MaterialProduct)
        .filter(MaterialProduct.id == data.product_id)
        .first()
    )
    if product is None:
        raise HTTPException(404, "Tovar topilmadi")
    if product.status != MaterialProduct.STATUS_APPROVED:
        raise HTTPException(400, "Tovar hozir sotuvda emas")
    if product.owner_id == buyer.id:
        raise HTTPException(400, "O'z tovaringizni sotib ololmaysiz")

    # С 23.11.2026 доставку делает водитель «как такси» (delivery_service),
    # и ему нужна точка: без неё нет ни расстояния, ни цены доставки.
    if data.delivery_latitude is None or data.delivery_longitude is None:
        raise HTTPException(400, "Yetkazib berish manzilini xaritada belgilang")
    delivery_payment = getattr(data, "delivery_payment", None) or "balance"
    if delivery_payment not in ("balance", "cash"):
        raise HTTPException(400, "Yetkazib berish to'lovi: balance yoki cash")

    quote = calculate(
        db,
        product,
        to_units(product, data.quantity, getattr(data, "input_unit", None)),
        data.delivery_latitude,
        data.delivery_longitude,
        data.vehicle_code,
    )
    # Комиссия продавца — только с товара: доставку получает водитель, и
    # с неё своя комиссия (delivery_service).
    seller_commission = pricing_service.calculate_commission(
        db, quote.goods_amount, quote.goods_amount
    )
    # Наличная доставка — водителю в руки, на Go wallet держим только товар.
    to_freeze = quote.goods_amount + (
        quote.delivery_fee if delivery_payment == "balance" else Decimal("0")
    )

    get_or_create_balance(db, buyer.id)
    balance = (
        db.query(Balance)
        .filter(Balance.user_id == buyer.id)
        .with_for_update()
        .one()
    )
    available = _dec(balance.balance) - _dec(balance.frozen_balance)
    if available < to_freeze:
        raise HTTPException(
            400,
            insufficient_funds(db, buyer.id, available, to_freeze),
        )

    balance.frozen_balance = _dec(balance.frozen_balance) + to_freeze

    order = MaterialOrder(
        buyer_id=buyer.id,
        seller_id=product.owner_id,
        product_id=product.id,
        quantity=quote.quantity,
        unit=product.unit,
        price_per_unit=quote.price_per_unit,
        goods_amount=quote.goods_amount,
        weight_kg=quote.weight_kg,
        vehicle_code=quote.vehicle_code,
        trips=quote.trips,
        delivery_distance_km=quote.distance_km,
        delivery_fee=quote.delivery_fee,
        commission=seller_commission,
        total_amount=quote.total,
        frozen_amount=to_freeze,
        dispatch="driver",
        delivery_payment=delivery_payment,
        delivery_status="waiting_seller",
        delivery_address=(data.delivery_address or None),
        delivery_latitude=data.delivery_latitude,
        delivery_longitude=data.delivery_longitude,
        comment=(data.comment or None),
        status=MaterialOrder.STATUS_PENDING,
    )
    db.add(order)
    db.commit()
    db.refresh(order)

    notification_service.create_localized(
        db, product.owner_id, "material_order",
        "material_order.title", "material_order.body",
        None, None, None,
        title=product.title,
        quantity=f"{float(quote.quantity):g}",
    )
    return order


def _load_order(db: Session, order_id: int, user: User) -> MaterialOrder:
    order = db.query(MaterialOrder).filter(MaterialOrder.id == order_id).first()
    if order is None:
        raise HTTPException(404, "Buyurtma topilmadi")
    if user.id not in (order.buyer_id, order.seller_id, order.driver_id) and user.role != "admin":
        raise HTTPException(403, "Bu buyurtmaga ruxsat yo'q")
    return order


def confirm_order(db: Session, order_id: int, seller: User) -> MaterialOrder:
    """Sotuvchi buyurtmani qabul qildi. Pul hali qimirlamaydi."""
    order = _load_order(db, order_id, seller)
    if order.seller_id != seller.id and seller.role != "admin":
        raise HTTPException(403, "Faqat sotuvchi tasdiqlay oladi")
    if order.status != MaterialOrder.STATUS_PENDING:
        raise HTTPException(400, f"Buyurtma holati: {order.status}")

    order.status = MaterialOrder.STATUS_CONFIRMED
    if order.dispatch == "driver":
        # Товар готов — заказ виден водителям (delivery_service.incoming).
        order.delivery_status = "searching"
    db.commit()
    db.refresh(order)

    notification_service.create_localized(
        db, order.buyer_id, "material_confirmed",
        "material_confirmed.title", "material_confirmed.body",
        None, None, None, order_number=order.id,
    )
    return order


def deliver_order(db: Session, order_id: int, user: User) -> MaterialOrder:
    """
    Yetkazildi — PUL SHU YERDA harakat qiladi.

    Xaridorning balansidan summa YECHILADI (nafaqat muzlatish olinadi:
    ikkovini chalkashtirish pul chop etish demak), sotuvchiga ulushdan
    keyingi qismi tushadi.
    """
    order = _load_order(db, order_id, user)
    if order.status != MaterialOrder.STATUS_CONFIRMED:
        raise HTTPException(
            400, "Faqat tasdiqlangan buyurtmani yetkazilgan deb belgilash mumkin"
        )
    # Xaridor tovarni olganini o'zi tasdiqlaydi. Sotuvchi o'zi bosa
    # olganida, u yetkazmasdan turib pulni olib qo'ya olardi.
    if user.id != order.buyer_id and user.role != "admin":
        raise HTTPException(403, "Yetkazilganini xaridor tasdiqlaydi")
    if order.dispatch == "driver":
        return _deliver_by_driver(db, order)

    total = _dec(order.total_amount)
    commission = _dec(order.commission)
    seller_amount = total - commission
    if seller_amount < 0:
        seller_amount = Decimal("0")

    buyer_balance = (
        db.query(Balance)
        .filter(Balance.user_id == order.buyer_id)
        .with_for_update()
        .one()
    )
    if _dec(buyer_balance.balance) < total:
        raise HTTPException(400, "Xaridor balansi buyurtmaga mos kelmaydi")

    frozen = _dec(buyer_balance.frozen_balance)
    buyer_balance.frozen_balance = frozen - total if frozen >= total else Decimal("0")
    buyer_balance.balance = _dec(buyer_balance.balance) - total

    get_or_create_balance(db, order.seller_id)
    seller_balance = (
        db.query(Balance)
        .filter(Balance.user_id == order.seller_id)
        .with_for_update()
        .one()
    )
    seller_balance.balance = _dec(seller_balance.balance) + seller_amount

    db.add(
        BalanceTransaction(
            user_id=order.buyer_id,
            amount=total,
            type="payment",
            status="completed",
            description=f"Material buyurtmasi #{order.id}",
        )
    )
    db.add(
        BalanceTransaction(
            user_id=order.seller_id,
            amount=seller_amount,
            type="income",
            status="completed",
            description=f"Material buyurtmasi #{order.id}",
        )
    )

    order.status = MaterialOrder.STATUS_DELIVERED
    order.frozen_amount = Decimal("0")
    db.commit()
    db.refresh(order)

    notification_service.create_localized(
        db, order.seller_id, "material_delivered",
        "material_delivered.title", "material_delivered.body",
        None, None, None, order_number=order.id,
    )
    return order


def _deliver_by_driver(db: Session, order: MaterialOrder) -> MaterialOrder:
    """
    «Yetkazildi» у заказа, который вёз водитель. Товар — продавцу минус
    комиссия (с товара), доставка — водителю (delivery_service.settle).
    Заморозка клиента снимается ЦЕЛИКОМ, списывается — товар и доставка
    по цене водителя (она не выше заморожённой).
    """
    if order.delivery_status not in ("picked_up", "arrived"):
        raise HTTPException(400, "Haydovchi hali tovarni olib kelmadi")

    goods = _dec(order.goods_amount)
    commission = _dec(order.commission)
    seller_amount = max(goods - commission, Decimal("0"))

    buyer_balance = (
        db.query(Balance).filter(Balance.user_id == order.buyer_id).with_for_update().one()
    )
    frozen_here = _dec(order.frozen_amount)
    frozen = _dec(buyer_balance.frozen_balance)
    buyer_balance.frozen_balance = frozen - frozen_here if frozen >= frozen_here else Decimal("0")
    buyer_balance.balance = _dec(buyer_balance.balance) - goods

    get_or_create_balance(db, order.seller_id)
    seller_balance = (
        db.query(Balance).filter(Balance.user_id == order.seller_id).with_for_update().one()
    )
    seller_balance.balance = _dec(seller_balance.balance) + seller_amount

    delivery_paid = delivery_service.settle(db, order, buyer_balance)

    db.add(BalanceTransaction(
        user_id=order.buyer_id, amount=goods + delivery_paid, type="payment",
        status="completed", description=f"Material buyurtmasi #{order.id}",
    ))
    db.add(BalanceTransaction(
        user_id=order.seller_id, amount=seller_amount, type="income",
        status="completed", description=f"Material buyurtmasi #{order.id}",
    ))

    order.status = MaterialOrder.STATUS_DELIVERED
    order.delivery_status = "done"
    order.frozen_amount = Decimal("0")
    db.commit()
    db.refresh(order)

    notification_service.create_localized(
        db, order.seller_id, "material_delivered",
        "material_delivered.title", "material_delivered.body",
        None, None, None, order_number=order.id,
    )
    return order


def cancel_order(db: Session, order_id: int, user: User, reject: bool = False):
    """
    Bekor qilish yoki rad etish — pul QAYTMAYDI, chunki u hali
    yechilmagan: faqat muzlatish olib tashlanadi.
    """
    order = _load_order(db, order_id, user)
    if order.status in (MaterialOrder.STATUS_DELIVERED,
                        MaterialOrder.STATUS_CANCELLED,
                        MaterialOrder.STATUS_REJECTED):
        raise HTTPException(400, f"Buyurtma allaqachon yopilgan: {order.status}")

    if reject:
        if order.seller_id != user.id and user.role != "admin":
            raise HTTPException(403, "Faqat sotuvchi rad eta oladi")
    else:
        if order.buyer_id != user.id and user.role != "admin":
            raise HTTPException(403, "Faqat xaridor bekor qila oladi")
    # Товар уже в машине водителя — отменить нельзя: он его везёт.
    if order.delivery_status in ("picked_up", "arrived") and user.role != "admin":
        raise HTTPException(400, "Haydovchi tovarni olib bo'ldi — bekor qilib bo'lmaydi")
    driver_to_notify = order.driver_id
    if order.dispatch == "driver":
        delivery_service.release_driver(db, order)
        order.delivery_status = "cancelled"

    frozen = _dec(order.frozen_amount)
    if frozen > 0:
        balance = (
            db.query(Balance)
            .filter(Balance.user_id == order.buyer_id)
            .with_for_update()
            .first()
        )
        if balance is not None:
            current = _dec(balance.frozen_balance)
            balance.frozen_balance = current - frozen if current >= frozen else Decimal("0")

    order.status = (
        MaterialOrder.STATUS_REJECTED if reject else MaterialOrder.STATUS_CANCELLED
    )
    order.frozen_amount = Decimal("0")
    db.commit()
    db.refresh(order)

    other = order.buyer_id if reject else order.seller_id
    notification_service.create_localized(
        db, other, "material_cancelled",
        "material_cancelled.title", "material_cancelled.body",
        None, None, None, order_number=order.id,
    )
    if driver_to_notify:
        notification_service.create_localized(
            db, driver_to_notify, "material_cancelled",
            "material_cancelled.title", "material_cancelled.body",
            None, None, None, order_number=order.id,
        )
    return order


def list_orders(db: Session, user: User, as_seller: bool = False) -> List[MaterialOrder]:
    query = db.query(MaterialOrder)
    if as_seller:
        query = query.filter(MaterialOrder.seller_id == user.id)
    else:
        query = query.filter(MaterialOrder.buyer_id == user.id)
    return query.order_by(MaterialOrder.created_at.desc()).all()
