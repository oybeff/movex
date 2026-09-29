"""
Pul yechish arizalari.

Texnika egasi ariza beradi, pul kartaga MULTICARD orqali o'tadi
(POST /payment/credit). Ilgari o'tkazmani admin bank ilovasida qo'lda
bajarardi va keyin "to'landi" deb belgilardi — ya'ni tizim pulning
haqiqatan ketganini bilmasdi.

Kim boshlaydi: standart holda admin (adminkadagi tugma), `payout_auto_enabled`
yoqilgan bo'lsa — ariza berilishi bilanoq tizim o'zi.
"""
from typing import List, Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.roles import role_checker
from app.db.session import get_db
from app.routes.auth import get_current_user
from app.schemas.payout import (
    PayoutRequestCreate,
    PayoutRequestRead,
    PayoutRequestResolve,
    PayoutSettingsRead,
)
from app.services import payout_service

router = APIRouter()


def _to_read(request) -> PayoutRequestRead:
    """Karta raqami ochiq qaytmasligi uchun qo'lda yig'amiz."""
    return PayoutRequestRead(
        id=request.id,
        user_id=request.user_id,
        amount=float(request.amount),
        commission=float(request.commission or 0),
        # Eski arizalarda ustun bo'sh bo'lishi mumkin emas, lekin
        # ehtiyot uchun: komissiyasiz ariza = to'liq summa kartaga.
        payout_amount=float(request.payout_amount or request.amount),
        status=request.status,
        card_masked=request.card_masked,
        card_holder=request.card_holder,
        comment=request.comment,
        admin_comment=request.admin_comment,
        rahmat_status=request.rahmat_status,
        rahmat_receipt_url=request.rahmat_receipt_url,
        rahmat_error=request.rahmat_error,
        processed_at=request.processed_at,
        created_at=request.created_at,
    )


def _require_internal_admin(secret: Optional[str] = Header(None, alias="X-Admin-Secret")):
    """
    PHP adminkasi uchun ichki kirish.

    Panel bazaga to'g'ridan-to'g'ri yozib pul harakatlantirmasligi kerak:
    kartaga o'tkazish endi shlyuzga murojaat qiladi, ya'ni mantiq BITTA
    joyda — payout_service da — turishi shart. Ilgari payouts.php shu
    mantiqni takrorlardi va ikkisi ajralib ketishi mumkin edi.

    Maxfiy so'z bo'sh bo'lsa manzil YO'Q (404): imzosiz manzil orqali
    istalgan odam chet kartaga pul jo'natishni buyurgan bo'lardi.
    """
    if not settings.ADMIN_INTERNAL_SECRET:
        raise HTTPException(status_code=404, detail="Not Found")
    from hmac import compare_digest

    if not secret or not compare_digest(str(secret), settings.ADMIN_INTERNAL_SECRET):
        raise HTTPException(status_code=403, detail="Forbidden")
    return True


@router.get("/settings", response_model=PayoutSettingsRead)
def payout_settings(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    """
    Pul yechish shartlari: ushlanma va eng kam summa.

    Ilova buni ariza berishdan oldin so'raydi va ekranda ko'rsatadi —
    ega qancha ushlanishini va kartaga qancha tushishini oldindan biladi.

    E'tibor: bu yo'l "/{request_id}" ko'rinishidagi yo'llardan OLDIN
    e'lon qilinishi shart, aks holda FastAPI "settings" so'zini son deb
    o'qishga urinadi.
    """
    return PayoutSettingsRead(
        mode=payout_service.get_commission_mode(db),
        fixed=float(payout_service.get_commission_fixed(db)),
        percent=float(payout_service.get_commission_percent(db)),
        min_amount=float(payout_service.MIN_PAYOUT_SUM),
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
def pay_payout(
    request_id: int,
    data: PayoutRequestResolve = PayoutRequestResolve(),
    db: Session = Depends(get_db),
    current_user=Depends(role_checker(["admin"])),
):
    """
    Kartaga o'tkazish. Balansdan yechish FAQAT shlyuz tasdiqlaganidan keyin.

    Manzil nomi ("paid") o'zgarmadi: uni adminka ham, testlar ham
    ishlatadi, va harakatning ma'nosi o'sha — ariza to'landi.
    """
    return _to_read(payout_service.pay(db, request_id, current_user.id, data.admin_comment))


@router.post("/{request_id}/sync", response_model=PayoutRequestRead)
def sync_payout(
    request_id: int,
    db: Session = Depends(get_db),
    current_user=Depends(role_checker(["admin"])),
):
    """
    O'tkazma holatini shlyuzdan so'rab aniqlash.

    ERROR_UNKNOWN yoki timeoutdan keyin so'rovni QAYTARISH man etilgan —
    hujjat holatni so'rashni talab qiladi, aks holda bir arizaga pul ikki
    marta ketardi.
    """
    request = payout_service.get_request(db, request_id)
    return _to_read(payout_service.sync_with_gateway(db, request))


@router.post("/internal/{request_id}/pay", response_model=PayoutRequestRead)
def internal_pay_payout(
    request_id: int,
    data: PayoutRequestResolve = PayoutRequestResolve(),
    db: Session = Depends(get_db),
    _=Depends(_require_internal_admin),
):
    """PHP adminkasi uchun: o'tkazishni boshlash."""
    return _to_read(payout_service.pay(db, request_id, data.admin_id, data.admin_comment))


@router.post("/internal/{request_id}/reject", response_model=PayoutRequestRead)
def internal_reject_payout(
    request_id: int,
    data: PayoutRequestResolve = PayoutRequestResolve(),
    db: Session = Depends(get_db),
    _=Depends(_require_internal_admin),
):
    """PHP adminkasi uchun: rad etish. Pul egasida qoladi."""
    return _to_read(payout_service.reject(db, request_id, data.admin_id, data.admin_comment))


@router.post("/internal/{request_id}/sync", response_model=PayoutRequestRead)
def internal_sync_payout(
    request_id: int,
    db: Session = Depends(get_db),
    _=Depends(_require_internal_admin),
):
    """PHP adminkasi uchun: holatni shlyuzdan so'rash."""
    request = payout_service.get_request(db, request_id)
    return _to_read(payout_service.sync_with_gateway(db, request))


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
