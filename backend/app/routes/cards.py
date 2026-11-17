"""Привязанные карты клиента (K1–K6). Номера карт к нам не попадают."""
from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session

from app.dependencies import get_current_user, get_db
from app.services import card_service

router = APIRouter()


@router.get("/")
def my_cards(db: Session = Depends(get_db), user=Depends(get_current_user)):
    return card_service.list_cards(db, user)


@router.post("/bind")
def bind_start(db: Session = Depends(get_db), user=Depends(get_current_user)):
    """Ссылка на форму Multicard — приложение открывает её в WebView."""
    return card_service.start_bind(db, user)


@router.get("/bind/done", response_class=HTMLResponse)
def bind_done():
    # Сюда Multicard возвращает WebView после ввода карты; приложение
    # перехватывает этот адрес и закрывает окно само.
    return "<html><body style='font-family:sans-serif;text-align:center;padding-top:40vh'>✓</body></html>"


@router.get("/bind/fail", response_class=HTMLResponse)
def bind_fail():
    return "<html><body style='font-family:sans-serif;text-align:center;padding-top:40vh'>✕</body></html>"


@router.get("/bind/{session_id}")
def bind_status(session_id: str, db: Session = Depends(get_db), user=Depends(get_current_user)):
    """Чем кончилась привязка. card=null — ещё не добавлена."""
    card = card_service.sync_session(db, session_id, user)
    return {"card": card_service.card_out(card) if card else None}


@router.post("/callback")
async def bind_callback(request: Request, db: Session = Depends(get_db)):
    """
    Колбэк Multicard после привязки. Подписи у него нет, поэтому тело
    служит только подсказкой: карту сохраняем по ответу самого Multicard.
    Всегда 200 — иначе Multicard будет повторять ещё 5 раз.
    """
    try:
        body = await request.json()
        sid = str(body.get("payer_id") or "")
        if sid:
            card_service.sync_session(db, sid)
    except Exception:  # noqa: BLE001
        pass
    return {"success": True}


@router.delete("/{card_id}")
def delete_card(card_id: int, db: Session = Depends(get_db), user=Depends(get_current_user)):
    card_service.delete_card(db, user, card_id)
    return {"ok": True}


@router.put("/{card_id}/default")
def make_default(card_id: int, db: Session = Depends(get_db), user=Depends(get_current_user)):
    card_service.set_default(db, user, card_id)
    return {"ok": True}
