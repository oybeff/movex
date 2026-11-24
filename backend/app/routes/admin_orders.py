"""
PHP admin panel → buyurtmalar ustidan amallar (Figma «Admin panel» 02).
Faqat X-Admin-Secret bilan; pul mantig'i admin_order_service'da.
"""
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.internal_auth import require_internal_admin
from app.db.session import get_db
from app.services import admin_order_service

router = APIRouter(dependencies=[Depends(require_internal_admin)])

class _CancelIn(BaseModel):
    admin_id: int
    reason: str = Field(max_length=30)
    note: Optional[str] = Field(default=None, max_length=1000)
    notify: bool = True


class _ReassignIn(BaseModel):
    admin_id: int
    user_id: Optional[int] = None
    equipment_id: Optional[int] = None
    note: Optional[str] = Field(default=None, max_length=1000)


@router.post("/internal/{kind}/{order_id}/cancel")
def cancel(kind: str, order_id: int, data: _CancelIn, db: Session = Depends(get_db)):
    return admin_order_service.cancel(db, kind, order_id, data.admin_id, data.reason, data.note, data.notify)


@router.get("/internal/{kind}/{order_id}/candidates")
def candidates(kind: str, order_id: int, db: Session = Depends(get_db)):
    return admin_order_service.candidates(db, kind, order_id)


@router.post("/internal/{kind}/{order_id}/reassign")
def reassign(kind: str, order_id: int, data: _ReassignIn, db: Session = Depends(get_db)):
    return admin_order_service.reassign(db, kind, order_id, data.admin_id, data.user_id,
                                        data.equipment_id, data.note)


# ------------------------------------------------------------------ nizolar (07)

class _DisputeMsgIn(BaseModel):
    admin_id: int
    text: str = Field(max_length=2000)
    visibility: str = Field(default="all", pattern="^(all|client|performer|internal)$")


class _DisputeResolveIn(BaseModel):
    admin_id: int
    decision: str = Field(pattern="^(client|partial|performer|close)$")
    refund_amount: Optional[float] = None
    note: Optional[str] = Field(default=None, max_length=1000)


class _AssignIn(BaseModel):
    admin_id: int
    to_admin_id: int


@router.get("/internal/disputes/{problem_id}/options")
def dispute_options(problem_id: int, db: Session = Depends(get_db)):
    from fastapi import HTTPException

    from app.models.order_problem import OrderProblem
    from app.services import dispute_service
    p = db.query(OrderProblem).filter(OrderProblem.id == problem_id).first()
    if p is None:
        raise HTTPException(404, "Nizo topilmadi")
    return dispute_service.decision_options(db, p)


@router.post("/internal/disputes/{problem_id}/message")
def dispute_message(problem_id: int, data: _DisputeMsgIn, db: Session = Depends(get_db)):
    from app.services import dispute_service
    return dispute_service.admin_message(db, data.admin_id, problem_id, data.text, data.visibility)


@router.post("/internal/disputes/{problem_id}/assign")
def dispute_assign(problem_id: int, data: _AssignIn, db: Session = Depends(get_db)):
    from app.services import dispute_service
    return dispute_service.assign(db, data.admin_id, problem_id, data.to_admin_id)


@router.post("/internal/disputes/{problem_id}/resolve")
def dispute_resolve(problem_id: int, data: _DisputeResolveIn, db: Session = Depends(get_db)):
    from decimal import Decimal

    from app.services import dispute_service
    amount = Decimal(str(data.refund_amount)) if data.refund_amount is not None else None
    return dispute_service.resolve(db, data.admin_id, problem_id, data.decision, amount, data.note)


# ------------------------------------------------------------------ yordam chati (N5)

class _SupportReplyIn(BaseModel):
    admin_id: int
    text: str = Field(max_length=2000)


class _AdminIn(BaseModel):
    admin_id: int


@router.post("/internal/support/{thread_id}/reply")
def support_reply(thread_id: int, data: _SupportReplyIn, db: Session = Depends(get_db)):
    from app.services import support_service
    return support_service.admin_reply(db, data.admin_id, thread_id, data.text)


@router.post("/internal/support/{thread_id}/close")
def support_close(thread_id: int, data: _AdminIn, db: Session = Depends(get_db)):
    from app.services import support_service
    return support_service.admin_close(db, data.admin_id, thread_id)


# ------------------------------------------------------------------ sharhlar (N4)

class _ReviewIn(BaseModel):
    admin_id: int
    hide: bool
    reason: Optional[str] = Field(default=None, max_length=30)


@router.post("/internal/reviews/{review_id}/moderate")
def review_moderate(review_id: int, data: _ReviewIn, db: Session = Depends(get_db)):
    from app.services import review_service
    return review_service.moderate(db, data.admin_id, review_id, data.hide, data.reason)
