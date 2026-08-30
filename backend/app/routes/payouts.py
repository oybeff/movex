"""
Pul yechish arizalari.

Texnika egasi ariza beradi, admin ko'rib chiqadi. Pul o'tkazish o'zi
qo'lda bajariladi (karta orqali), tizim faqat hisobni yuritadi.
"""
from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.roles import role_checker
from app.db.session import get_db
from app.routes.auth import get_current_user
from app.schemas.payout import PayoutRequestCreate, PayoutRequestRead, PayoutRequestResolve
from app.services import payout_service

router = APIRouter()


def _to_read(request) -> PayoutRequestRead:
    """Karta raqami ochiq qaytmasligi uchun qo'lda yig'amiz."""
    return PayoutRequestRead(
        id=request.id,
        user_id=request.user_id,
        amount=float(request.amount),
        status=request.status,
        card_masked=request.card_masked,
        card_holder=request.card_holder,
        comment=request.comment,
        admin_comment=request.admin_comment,
        processed_at=request.processed_at,
        created_at=request.created_at,
    )


@router.post("/", response_model=PayoutRequestRead)
def create_payout_request(
    data: PayoutRequestCreate,
    db: Session = Depends(get_db),
    current_user=Depends(role_checker(["owner", "admin"])),
):
    """Pul yechish arizasi. Summa darhol muzlatiladi."""
    return _to_read(payout_service.create_request(db, current_user.id, data))


@router.get("/", response_model=List[PayoutRequestRead])
def my_payout_requests(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """O'z arizalarim."""
    return [_to_read(r) for r in payout_service.list_for_user(db, current_user.id)]


@router.get("/all", response_model=List[PayoutRequestRead])
def all_payout_requests(
    status: Optional[str] = Query(None, description="pending / paid / rejected"),
    skip: int = 0,
    limit: int = Query(100, le=500),
    db: Session = Depends(get_db),
    current_user=Depends(role_checker(["admin"])),
):
    """Barcha arizalar — faqat admin uchun."""
    return [_to_read(r) for r in payout_service.list_all(db, status, skip, limit)]


@router.post("/{request_id}/paid", response_model=PayoutRequestRead)
def mark_payout_paid(
    request_id: int,
    data: PayoutRequestResolve = PayoutRequestResolve(),
    db: Session = Depends(get_db),
    current_user=Depends(role_checker(["admin"])),
):
    """Pul o'tkazildi — balansdan yechamiz."""
    return _to_read(
        payout_service.mark_paid(db, request_id, current_user.id, data.admin_comment)
    )


@router.post("/{request_id}/reject", response_model=PayoutRequestRead)
def reject_payout(
    request_id: int,
    data: PayoutRequestResolve = PayoutRequestResolve(),
    db: Session = Depends(get_db),
    current_user=Depends(role_checker(["admin"])),
):
    """Rad etish — pul egasida qoladi."""
    return _to_read(
        payout_service.reject(db, request_id, current_user.id, data.admin_comment)
    )
