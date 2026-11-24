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
