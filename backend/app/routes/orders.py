from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime, date
from app.schemas import order as order_schema
from app.models import order as order_model
from pydantic import BaseModel, Field
from app.services import order_flow_service, order_service, pricing_service
from app.models.equipment import Equipment
from app.dependencies import get_db, get_current_user
from app.core.access import assert_order_access
from app.core.media import save_upload
from app.core.roles import role_checker
from app.core.internal_auth import require_internal_admin

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

# DIQQAT: "/{order_id}" dan OLDIN
@router.get("/client-cards")
def client_cards(lang: str = "uz", db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """M1–M3: «Buyurtmalarim» — заказы и ищущие заявки клиента одним списком."""
    return order_flow_service.client_cards(db, current_user, "ru" if lang == "ru" else "uz")


@router.post("/problem-photo")
def upload_problem_photo(file: UploadFile = File(...), current_user=Depends(get_current_user)):
    """B5: rasm alohida yuklanadi, manzili jalobaga qo'shib yuboriladi."""
    return {"url": save_upload(file, "problems")}


@router.get("/", response_model=list[order_schema.OrderRead])
def get_orders(skip: int = 0, limit: int = 100, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """
    Faqat O'ZIGA tegishli buyurtmalar: mijoz sifatida bergan yoki
    o'z texnikasiga kelgan. Admin hammasini ko'radi.

    Ilgari bu yerda butun tizimdagi barcha buyurtmalar qaytarilardi —
    summalari va yetkazib berish manzillari bilan birga.
    """
    orders = order_service.get_orders(db, skip, limit, current_user)
    return [order_flow_service.auto_confirm(db, o) for o in orders]

@router.get("/{order_id}", response_model=order_schema.OrderRead)
def get_order(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    db_order = order_service.get_order(db, order_id)
    if not db_order:
        raise HTTPException(status_code=404, detail="Order not found")
    assert_order_access(db, db_order, current_user)
    return order_flow_service.auto_confirm(db, db_order)

# ------------------------------------------- ход тарифного заказа (макет)

class _ExtendIn(BaseModel):
    hours: int = Field(ge=1, le=12)


@router.get("/{order_id}/executor")
def order_executor(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Карточка исполнителя для клиента: имя, рейтинг, машина, госномер, ETA."""
    db_order = order_service.get_order(db, order_id)
    if not db_order:
        raise HTTPException(status_code=404, detail="Order not found")
    assert_order_access(db, db_order, current_user)
    return order_flow_service.executor(db, db_order)


@router.post("/{order_id}/depart", response_model=order_schema.OrderRead)
def order_depart(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Владелец: «Ketdik»."""
    return order_flow_service.depart(db, order_id, current_user)


@router.post("/{order_id}/arrive", response_model=order_schema.OrderRead)
def order_arrive(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Владелец: «Yetib keldim»."""
    return order_flow_service.arrive(db, order_id, current_user)


@router.post("/{order_id}/start", response_model=order_schema.OrderRead)
def order_start(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Владелец: «Boshlash» — у клиента пошёл таймер."""
    return order_flow_service.start(db, order_id, current_user)


@router.post("/{order_id}/no-show", response_model=order_schema.OrderRead)
def order_no_show(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Владелец: E7 «Mijoz kelmadi» — отмена, после 15 минут ожидания с компенсацией."""
    return order_flow_service.no_show(db, order_id, current_user)


class ClientRatingIn(BaseModel):
    rating: int = Field(..., ge=1, le=5)
    tags: list[str] = Field(default_factory=list, max_length=8)


@router.post("/{order_id}/rate-client")
def order_rate_client(order_id: int, payload: ClientRatingIn, db: Session = Depends(get_db),
                      current_user=Depends(get_current_user)):
    """Владелец: D6 «Mijozni baholang»."""
    return order_flow_service.rate_client(db, order_id, current_user, payload.rating, payload.tags)


@router.get("/{order_id}/client-rating")
def order_client_rating(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Средняя оценка клиента этого заказа и оценка, поставленная в нём."""
    from app.models.client_rating import ClientRating

    db_order = order_service.get_order(db, order_id)
    if not db_order:
        raise HTTPException(status_code=404, detail="Order not found")
    assert_order_access(db, db_order, current_user)
    mine = db.query(ClientRating).filter(ClientRating.order_id == order_id).first()
    return {
        **order_flow_service.client_rating_summary(db, db_order.user_id),
        "mine": {"rating": mine.rating, "tags": (mine.tags or "").split(",") if mine.tags else []} if mine else None,
    }


@router.post("/{order_id}/finish", response_model=order_schema.OrderRead)
def order_finish(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Владелец: «Yakunlash». Деньги двигает подтверждение клиента."""
    return order_flow_service.finish(db, order_id, current_user)


@router.post("/{order_id}/extend", response_model=order_schema.OrderRead)
def order_extend(order_id: int, data: _ExtendIn, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Клиент: запрос «Vaqtni uzaytirish» на N часов. Деньги — после согласия владельца."""
    return order_flow_service.request_extend(db, order_id, current_user, data.hours)


@router.post("/{order_id}/extend/approve", response_model=order_schema.OrderRead)
def order_extend_approve(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return order_flow_service.approve_extend(db, order_id, current_user)


@router.post("/{order_id}/extend/decline", response_model=order_schema.OrderRead)
def order_extend_decline(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return order_flow_service.decline_extend(db, order_id, current_user)


class _DelayIn(BaseModel):
    minutes: int = Field(ge=1, le=600)
    reason: Optional[str] = Field(None, max_length=300)


@router.post("/{order_id}/delay", response_model=order_schema.OrderRead)
def order_delay(order_id: int, data: _DelayIn, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Владелец: «опаздываю на N минут» — у клиента баннер B2."""
    return order_flow_service.report_delay(db, order_id, current_user, data.minutes, data.reason)


class _CardIn(BaseModel):
    card_id: int


@router.post("/{order_id}/pay-card", response_model=order_schema.OrderRead)
def order_pay_card(order_id: int, data: _CardIn, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """E7: списать с (другой) карты, если холд не прошёл."""
    return order_flow_service.pay_with_card(db, order_id, current_user, data.card_id)


@router.post("/{order_id}/pay-cash", response_model=order_schema.OrderRead)
def order_pay_cash(order_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """E7: «Naqd to'lash» — клиент платит владельцу в руки."""
    return order_flow_service.switch_to_cash(db, order_id, current_user)


class _ProblemIn(BaseModel):
    reason: str
    comment: Optional[str] = Field(None, max_length=1000)
    photos: list[str] = Field(default_factory=list, max_length=3)


@router.post("/{order_id}/problem")
def order_problem(order_id: int, data: _ProblemIn, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Клиент: «Muammo haqida xabar» (B5). Останавливает автоподтверждение."""
    p = order_flow_service.report_problem(db, order_id, current_user, data.reason, data.comment, data.photos)
    return {"id": p.id, "status": p.status}


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


# ------------------------------------------------- разбор жалоб из админки

class _ProblemResolveIn(BaseModel):
    #: complete — работа принята, деньги владельцу (как подтверждение клиентом);
    #: cancel — заказ отменён, деньги клиенту (холд снят / заморозка снята);
    #: close — разобрались вне сервиса, деньги не двигаем.
    action: str = Field(pattern="^(complete|cancel|close)$")


@router.post("/internal/problems/{problem_id}/resolve")
def internal_resolve_problem(
    problem_id: int,
    data: _ProblemResolveIn,
    db: Session = Depends(get_db),
    _=Depends(require_internal_admin),
):
    """
    PHP-админка (problems.php). Деньги двигает тот же update_order, что и
    у клиента: своей копии логики у панели нет, как и у выплат.
    """
    from app.models.order_problem import OrderProblem
    p = db.query(OrderProblem).filter(OrderProblem.id == problem_id).first()
    if p is None:
        raise HTTPException(404, "Shikoyat topilmadi")
    if p.status != "open":
        raise HTTPException(409, "Shikoyat allaqachon ko'rib chiqilgan")
    order = db.query(order_model.Order).filter(order_model.Order.id == p.order_id).first()
    if data.action in ("complete", "cancel"):
        if order is None or order.status != "confirmed":
            raise HTTPException(409, "Buyurtma faol emas — faqat yopish mumkin")
        new = "completed" if data.action == "complete" else "cancelled"
        # От имени клиента — он сторона заказа; кто отменил, правим ниже
        order_service.update_order(db, order.id, order_schema.OrderUpdate(status=new), order.user_id)
        if new == "cancelled":
            db.refresh(order)
            order.cancelled_by = "admin"
    p.status = "resolved"
    db.commit()
    return {"id": p.id, "status": p.status, "order_status": order.status if order else None}
