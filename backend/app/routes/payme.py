"""
Payme (Paycom) Merchant API uchun yagona endpoint.

Payme kabinetida shu manzil ko'rsatiladi: https://<domen>/payments/payme

Payme JSON-RPC 2.0 so'rovlarini POST bilan yuboradi. Xatolar HTTP 200 bilan,
javob tanasidagi `error` obyektida qaytariladi — protokol shuni talab qiladi,
shuning uchun bu yerda HTTPException ishlatilmaydi.
"""
import logging
from typing import Any, Dict

from fastapi import APIRouter, Depends, Header, Request
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.services.payme_service import (
    ERR_INTERNAL,
    ERR_INVALID_REQUEST,
    ERR_PARSE,
    PaymeError,
    PaymeService,
    _msg,
)

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("/payme")
async def payme_endpoint(
    request: Request,
    authorization: str = Header(default=None),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """Payme'dan keladigan barcha metodlar shu yerdan o'tadi."""
    request_id: Any = None

    try:
        try:
            body = await request.json()
        except Exception:
            raise PaymeError(
                ERR_PARSE,
                _msg("Ошибка разбора JSON", "JSON o'qib bo'lmadi", "JSON parse error"),
            )

        if not isinstance(body, dict):
            raise PaymeError(
                ERR_INVALID_REQUEST,
                _msg("Неверный запрос", "So'rov noto'g'ri", "Invalid request"),
            )

        request_id = body.get("id")
        method = body.get("method")
        params = body.get("params") or {}

        if not isinstance(method, str):
            raise PaymeError(
                ERR_INVALID_REQUEST,
                _msg("Метод не указан", "Metod ko'rsatilmagan", "Method is missing"),
            )

        PaymeService.check_auth(authorization)
        result = PaymeService.handle(db, method, params)
        return {"result": result, "id": request_id}

    except PaymeError as exc:
        # Kutilgan protokol xatosi — jurnalga faqat qisqacha yozamiz
        logger.info("Payme xatosi %s: %s", exc.code, exc.message.get("ru"))
        return exc.to_response(request_id)

    except Exception:
        # Kutilmagan xato ham protokol formatida qaytishi kerak, aks holda
        # Payme javobni tushunmaydi va to'lovni "noaniq" holatda qoldiradi.
        logger.exception("Payme: kutilmagan xato")
        db.rollback()
        return PaymeError(
            ERR_INTERNAL,
            _msg("Внутренняя ошибка", "Ichki xatolik", "Internal error"),
        ).to_response(request_id)
