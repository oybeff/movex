"""
PHP admin panel → P5 (Figma «Admin panel» 00, 08): SMS kod va push xabarlar.

Faqat X-Admin-Secret bilan. Kirish oqimi (parol, urinishlar, blok, kod
xeshi) PHP panelning o'zida — bu yerda faqat SMS ni Eskiz orqali yuborish:
Eskiz tokeni va tasdiqlangan shablon backendda.
"""
import asyncio
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.internal_auth import require_internal_admin
from app.db.session import get_db
from app.services import push_campaign_service as pcs

logger = logging.getLogger(__name__)
router = APIRouter(dependencies=[Depends(require_internal_admin)])


class _SmsCodeIn(BaseModel):
    phone: str = Field(pattern=r"^998\d{9}$")
    code: str = Field(pattern=r"^\d{4,6}$")


@router.post("/internal/sms-code")
def sms_code(data: _SmsCodeIn, db: Session = Depends(get_db)):
    """
    Admin 2FA / parolni tiklash kodi. Matn — ilovaga kirish kodi bilan BIR
    XIL tasdiqlangan shablon (Eskiz boshqasini rad etadi).
    Sinov rejimida (OTP_TEST_MODE, production emas) SMS ketmaydi, kod
    javobda qaytadi — u faqat PHP serverga keladi, brauzerga emas.
    """
    if settings.OTP_TEST_MODE and (settings.APP_ENV or "development") != "production":
        return {"sent": False, "test_code": data.code}
    from app.services.eskiz_service import EskizService

    try:
        res = asyncio.run(EskizService(db).send_otp(data.phone, data.code, "uz"))
        ok = bool(res) and res.get("success", True) is not False
        return {"sent": ok, "detail": None if ok else str(res)[:200]}
    except Exception as e:  # noqa: BLE001
        logger.warning("Admin SMS failed: %s", e)
        raise HTTPException(502, "SMS yuborilmadi")


class _PushIn(BaseModel):
    admin_id: int
    title_uz: str = Field(default="", max_length=200)
    body_uz: str = Field(default="", max_length=1000)
    title_ru: Optional[str] = Field(default=None, max_length=200)
    body_ru: Optional[str] = Field(default=None, max_length=1000)
    audience: dict = {}
    mode: str = Field(default="draft", pattern="^(draft|now|schedule)$")
    scheduled_at: Optional[str] = None
    phone: Optional[str] = None


class _AudienceIn(BaseModel):
    audience: dict = {}


class _AdminIn(BaseModel):
    admin_id: int


@router.post("/internal/push/audience")
def push_audience(data: _AudienceIn, db: Session = Depends(get_db)):
    return pcs.audience_stats(db, data.audience)


@router.post("/internal/push/campaigns")
def push_create(data: _PushIn, db: Session = Depends(get_db)):
    return pcs.create(db, data.admin_id, data.model_dump())


@router.post("/internal/push/test")
def push_test(data: _PushIn, db: Session = Depends(get_db)):
    return pcs.test_send(db, data.admin_id, data.model_dump())


@router.post("/internal/push/{cid}/cancel")
def push_cancel(cid: int, data: _AdminIn, db: Session = Depends(get_db)):
    return pcs.cancel(db, data.admin_id, cid)
