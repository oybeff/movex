"""
Проверка водителя по документам (MoveX GO Driver, макет 00).

Водителю: свой статус, загрузка фото документа, просмотр своего фото.
Админке (PHP, X-Admin-Secret): очередь на проверку, фото, одобрить/отклонить.
Фото отдаются только так — в публичной /static их нет.
"""
from typing import Optional

from datetime import date

from fastapi import APIRouter, Depends, File, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.internal_auth import require_internal_admin
from app.db.session import get_db
from app.models.driver_document import DriverDocument
from app.models.user import User
from app.routes.auth import get_current_user
from app.services import driver_service

router = APIRouter()


@router.get("/settings")
def driver_settings(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Числа для экранов водителя: компенсация E1/E7 и сколько ждать клиента."""
    from app.services import compensation_service

    return {
        "compensation_amount": float(compensation_service.amount_setting(db)),
        "no_show_wait_minutes": compensation_service.NO_SHOW_WAIT_MINUTES,
    }


@router.get("/me")
def my_verification(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Статус проверки и документы (без файлов): R5, E5, V1–V3."""
    return driver_service.summary(db, current_user)


@router.post("/me/documents/{kind}")
def upload_document(
    kind: str,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return driver_service.upload(db, current_user, kind, file)


@router.get("/me/documents/{kind}/file")
def my_document_file(kind: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return FileResponse(driver_service.file_of(db, current_user.id, kind=kind), headers={"Cache-Control": "private, no-store"})


# ------------------------------------------------------------- админка

class _ReviewIn(BaseModel):
    approve: bool
    reason: Optional[str] = Field(None, max_length=500)
    #: Prava / texpasport muddati (Admin P4)
    expires_on: Optional[date] = None
    admin_id: Optional[int] = None


@router.get("/internal/queue", dependencies=[Depends(require_internal_admin)])
def queue(db: Session = Depends(get_db)):
    """Водители с документами: сначала те, у кого есть непроверенные."""
    rows = (
        db.query(DriverDocument, User)
        .join(User, User.id == DriverDocument.user_id)
        .order_by(DriverDocument.updated_at.desc())
        .all()
    )
    by_user: dict[int, dict] = {}
    for doc, user in rows:
        item = by_user.setdefault(user.id, {
            "user_id": user.id, "full_name": user.full_name, "phone": user.phone, "documents": [],
        })
        item["documents"].append({
            "id": doc.id, "kind": doc.kind, "status": doc.status,
            "reject_reason": doc.reject_reason, "updated_at": doc.updated_at,
        })
    out = []
    for item in by_user.values():
        docs = [d for d, _ in rows if d.user_id == item["user_id"]]
        item["status"] = driver_service.status_of(docs)
        out.append(item)
    out.sort(key=lambda i: (i["status"] != "pending", i["status"] != "rejected"))
    return out


@router.get("/internal/documents/{doc_id}/file", dependencies=[Depends(require_internal_admin)])
def document_file(doc_id: int, db: Session = Depends(get_db)):
    return FileResponse(driver_service.file_of(db, None, doc_id=doc_id), headers={"Cache-Control": "private, no-store"})


@router.post("/internal/documents/{doc_id}/review", dependencies=[Depends(require_internal_admin)])
def review_document(doc_id: int, data: _ReviewIn, db: Session = Depends(get_db)):
    doc = driver_service.review(db, doc_id, data.approve, data.reason, data.expires_on, data.admin_id)
    return {"id": doc.id, "status": doc.status, "reject_reason": doc.reject_reason, "expires_on": doc.expires_on}


# ------------------------------------------- доставка стройматериалов
# (23.11.2026) — водитель грузовой машины: профиль, опрос, входящие,
# принять, «Tovarni oldim», «Yetib keldim», отказ до погрузки.

from fastapi import HTTPException  # noqa: E402

from app.schemas.material import DeliveryHeartbeat, DeliveryProfileIn  # noqa: E402
from app.services import delivery_service  # noqa: E402


def _driver(user: User) -> User:
    if user.role not in ("owner", "admin"):
        raise HTTPException(403, "Faqat haydovchilar uchun")
    return user


def _read(db: Session, order):
    from app.routes.materials import _order_to_read

    return _order_to_read(db, order)


@router.get("/delivery/categories")
def delivery_categories(lang: str = "uz", db: Session = Depends(get_db),
                        current_user: User = Depends(get_current_user)):
    """10 категорий из ТЗ: что водитель может возить и в чём меряется минимум."""
    ru = lang == "ru"
    return [
        {"code": c.code, "name": c.name_ru if ru else c.name_uz, "unit": c.unit}
        for c in delivery_service.categories(db)
    ]


@router.get("/delivery/profile")
def delivery_profile(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return delivery_service.profile_dict(db, _driver(current_user))


@router.put("/delivery/profile")
def save_delivery_profile(data: DeliveryProfileIn, db: Session = Depends(get_db),
                          current_user: User = Depends(get_current_user)):
    return delivery_service.save_profile(db, _driver(current_user), data)


@router.post("/delivery/heartbeat")
def delivery_heartbeat(data: DeliveryHeartbeat, db: Session = Depends(get_db),
                       current_user: User = Depends(get_current_user)):
    """Раз в 10 с, пока водитель онлайн: точка GPS. online=false — ушёл."""
    delivery_service.heartbeat(db, _driver(current_user), data.online, data.latitude, data.longitude)
    return {"ok": True}


@router.get("/delivery/incoming")
def delivery_incoming(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return delivery_service.incoming(db, _driver(current_user))


@router.get("/delivery/orders")
def delivery_orders(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return [_read(db, o) for o in delivery_service.my_deliveries(db, _driver(current_user))]


@router.post("/delivery/orders/{order_id}/accept")
def delivery_accept(order_id: int, db: Session = Depends(get_db),
                    current_user: User = Depends(get_current_user)):
    return _read(db, delivery_service.accept(db, _driver(current_user), order_id))


@router.post("/delivery/orders/{order_id}/picked-up")
def delivery_picked_up(order_id: int, db: Session = Depends(get_db),
                       current_user: User = Depends(get_current_user)):
    return _read(db, delivery_service.picked_up(db, _driver(current_user), order_id))


@router.post("/delivery/orders/{order_id}/arrived")
def delivery_arrived(order_id: int, db: Session = Depends(get_db),
                     current_user: User = Depends(get_current_user)):
    return _read(db, delivery_service.arrived(db, _driver(current_user), order_id))


@router.post("/delivery/orders/{order_id}/cancel")
def delivery_cancel(order_id: int, db: Session = Depends(get_db),
                    current_user: User = Depends(get_current_user)):
    return _read(db, delivery_service.driver_cancel(db, _driver(current_user), order_id))


# ---------------------------------------- «Yuk tashish» (24.11.2026)

from app.services import freight_service  # noqa: E402


@router.get("/freight/incoming")
def freight_incoming(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return freight_service.incoming(db, _driver(current_user))


@router.get("/freight/orders")
def freight_driver_orders(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    me = _driver(current_user)
    return [freight_service.read(db, o, me) for o in freight_service.driver_orders(db, me)]


@router.post("/freight/orders/{order_id}/{step}")
def freight_step(order_id: int, step: str, db: Session = Depends(get_db),
                 current_user: User = Depends(get_current_user)):
    me = _driver(current_user)
    actions = {
        "accept": freight_service.accept,
        "loaded": freight_service.loaded,
        "arrived": freight_service.arrived,
        "cancel": freight_service.driver_cancel,
    }
    if step not in actions:
        raise HTTPException(404, "Not Found")
    return freight_service.read(db, actions[step](db, me, order_id), me)
