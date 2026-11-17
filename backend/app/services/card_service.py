"""
Привязанные карты и оплата тарифного заказа картой (макеты K1–K6, E7).

Схема денег — «заморозить при заказе, списать после работы»:

    create_request(card) ─ POST /payment/hold ─ PUT /payment/hold/{uuid}
        ├─ холд active → заявка open, владельцы её видят
        └─ нужен SMS → заявка awaiting_payment, клиент вводит код (confirm_otp)
    заказ завершён ─ PUT /payment/hold/{uuid}/charge → владельцу на баланс
    отмена / истечение ─ DELETE /payment/hold/{uuid}

Номер карты к нам не попадает: клиент вводит его на странице Multicard
(WebView), сервер получает только токен и маску.

Колбэку привязки НЕ верим на слово: у него нет подписи, поэтому по нему
мы лишь узнаём session_id и сами спрашиваем Multicard
(GET /payment/card/bind/{session_id}).
"""
import logging
from decimal import Decimal
from typing import Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.card import CardBindSession, CardPayment, UserCard
from app.models.user import User
from app.services import rahmat_service
from app.services.rahmat_service import RahmatError

log = logging.getLogger(__name__)

#: Холд живёт 3 суток: заказ на сегодня или завтра успевает закончиться.
HOLD_EXPIRY_MINUTES = 3 * 24 * 60
MAX_CARDS = 5


def _base() -> str:
    return (settings.RAHMAT_CALLBACK_BASE_URL or "").rstrip("/")


def card_out(c: UserCard) -> dict:
    return dict(id=c.id, pan=c.pan, ps=c.ps, holder_name=c.holder_name, is_default=c.is_default)


def list_cards(db: Session, user: User) -> list:
    rows = (
        db.query(UserCard)
        .filter(UserCard.user_id == user.id, UserCard.status == "active")
        .order_by(UserCard.is_default.desc(), UserCard.id)
        .all()
    )
    return [card_out(c) for c in rows]


def own_card(db: Session, user: User, card_id: int) -> UserCard:
    c = db.query(UserCard).filter(UserCard.id == card_id).first()
    if c is None or c.user_id != user.id or c.status != "active":
        raise HTTPException(404, "Karta topilmadi")
    return c


# --------------------------------------------------------------- привязка

def start_bind(db: Session, user: User) -> dict:
    """K2: ссылка на форму Multicard. Открывается в WebView приложения."""
    count = (
        db.query(UserCard).filter(UserCard.user_id == user.id, UserCard.status == "active").count()
    )
    if count >= MAX_CARDS:
        raise HTTPException(400, f"{MAX_CARDS} tadan ortiq karta qo'shib bo'lmaydi")
    try:
        data = rahmat_service._request("POST", "/payment/card/bind", {
            "redirect_url": f"{_base()}/cards/bind/done",
            "redirect_decline_url": f"{_base()}/cards/bind/fail",
            "store_id": int(settings.RAHMAT_STORE_ID),
            "callback_url": f"{_base()}/cards/callback",
            "phone": user.phone,
        })
    except RahmatError as exc:
        log.warning("card bind start failed: %s", exc)
        raise HTTPException(502, "Karta qo'shish sahifasini ochib bo'lmadi. Keyinroq urinib ko'ring")
    db.add(CardBindSession(session_id=data["session_id"], user_id=user.id))
    db.commit()
    return {"session_id": data["session_id"], "form_url": data["form_url"]}


def sync_session(db: Session, session_id: str, user: Optional[User] = None) -> Optional[UserCard]:
    """
    Спросить Multicard, чем кончилась привязка, и сохранить карту.
    Повторный вызов карту не дублирует (токен уникален).
    """
    s = db.query(CardBindSession).filter(CardBindSession.session_id == session_id).first()
    if s is None or (user is not None and s.user_id != user.id):
        raise HTTPException(404, "Sessiya topilmadi")
    if s.card_id is not None:
        return db.query(UserCard).filter(UserCard.id == s.card_id).first()
    try:
        d = rahmat_service._request("GET", f"/payment/card/bind/{session_id}")
    except RahmatError as exc:
        log.info("bind status %s: %s", session_id, exc)
        return None
    if d.get("status") != "active" or not d.get("card_token"):
        return None
    card = db.query(UserCard).filter(UserCard.token == d["card_token"]).first()
    if card is None:
        has_default = (
            db.query(UserCard)
            .filter(UserCard.user_id == s.user_id, UserCard.status == "active", UserCard.is_default.is_(True))
            .first()
        )
        card = UserCard(
            user_id=s.user_id,
            token=d["card_token"],
            pan=(d.get("card_pan") or "")[:20],
            ps=d.get("ps"),
            holder_name=(d.get("holder_name") or "")[:100] or None,
            is_default=has_default is None,
        )
        db.add(card)
        db.flush()
    elif card.user_id != s.user_id:
        # Та же карта уже у другого аккаунта — токен один на карту
        raise HTTPException(409, "Bu karta boshqa akkauntga bog'langan")
    else:
        card.status = "active"
    s.card_id = card.id
    db.commit()
    db.refresh(card)
    return card


def delete_card(db: Session, user: User, card_id: int) -> None:
    card = own_card(db, user, card_id)
    busy = (
        db.query(CardPayment)
        .filter(CardPayment.card_id == card.id, CardPayment.status.in_(("draft", "active", "unknown")))
        .first()
    )
    if busy:
        raise HTTPException(409, "Bu karta faol buyurtmada ishlatilmoqda")
    try:
        rahmat_service._request("DELETE", f"/payment/card/{card.token}")
    except RahmatError as exc:
        # Карта могла уже исчезнуть у Multicard — у нас всё равно убираем
        log.info("card delete %s: %s", card.id, exc)
    card.status = "deleted"
    was_default = card.is_default
    card.is_default = False
    if was_default:
        nxt = (
            db.query(UserCard)
            .filter(UserCard.user_id == user.id, UserCard.status == "active", UserCard.id != card.id)
            .order_by(UserCard.id).first()
        )
        if nxt:
            nxt.is_default = True
    db.commit()


def set_default(db: Session, user: User, card_id: int) -> None:
    card = own_card(db, user, card_id)
    db.query(UserCard).filter(UserCard.user_id == user.id).update({"is_default": False})
    card.is_default = True
    db.commit()


# ------------------------------------------------------------------- холд

def _tiyin(amount) -> int:
    return rahmat_service.to_tiyin(amount)


def create_hold(db: Session, user: User, card: UserCard, amount: Decimal, request_id: Optional[int]) -> CardPayment:
    """
    Холд под заявку. Сначала пробуем подтвердить без кода (безакцептное
    списание у привязанной карты), не вышло — status draft, нужен SMS.
    Commit делает вызывающий.
    """
    cp = CardPayment(user_id=user.id, card_id=card.id, request_id=request_id, amount=amount, status="draft")
    db.add(cp)
    try:
        d = rahmat_service._request("POST", "/payment/hold", {
            "card": {"token": card.token},
            "amount": _tiyin(amount),
            "store_id": int(settings.RAHMAT_STORE_ID),
            "invoice_id": f"req-{request_id}",
            "expiry": HOLD_EXPIRY_MINUTES,
        })
    except RahmatError as exc:
        cp.status = "failed"
        cp.error = f"{exc.code}: {exc}"[:500]
        return cp
    cp.uuid = (d.get("payment") or {}).get("uuid")
    try:
        c = rahmat_service._request("PUT", f"/payment/hold/{cp.uuid}", {})
        if c.get("status") == "active":
            cp.status = "active"
    except RahmatError as exc:
        # Нужен код из SMS — остаётся draft
        cp.error = f"{exc.code}: {exc}"[:500]
    return cp


def confirm_hold_otp(cp: CardPayment, otp: str) -> bool:
    try:
        c = rahmat_service._request("PUT", f"/payment/hold/{cp.uuid}", {"otp": otp})
    except RahmatError as exc:
        cp.error = f"{exc.code}: {exc}"[:500]
        return False
    if c.get("status") == "active":
        cp.status = "active"
        cp.error = None
        return True
    return False


def cancel_hold(cp: Optional[CardPayment]) -> None:
    """Снять холд (отмена, истечение). Ошибка не мешает отмене заказа."""
    if cp is None or cp.status not in ("draft", "active", "unknown") or not cp.uuid:
        return
    try:
        rahmat_service._request("DELETE", f"/payment/hold/{cp.uuid}")
        cp.status = "cancelled"
    except RahmatError as exc:
        # Холд мог уже истечь — деньги вернутся на карту сами
        log.warning("hold cancel %s: %s", cp.uuid, exc)
        cp.status = "cancelled"
        cp.error = f"{exc.code}: {exc}"[:500]


def charge_hold(cp: CardPayment) -> str:
    """
    Списать холд после работы. Возвращает 'charged', 'failed' (холд
    пропал — истёк или снят банком; нужен E7) или 'unknown' (шлюз не
    ответил — повторять нельзя, только спрашивать статус).
    """
    try:
        d = rahmat_service._request("PUT", f"/payment/hold/{cp.uuid}/charge", {})
    except RahmatError as exc:
        cp.error = f"{exc.code}: {exc}"[:500]
        if exc.code in ("ERROR_DEBIT_UNKNOWN", "ERROR_CALLBACK_TIMEOUT") or exc.is_unknown:
            cp.status = "unknown"
        else:
            cp.status = "failed"
        return cp.status
    cp.status = "charged" if d.get("status") == "success" else "unknown"
    return cp.status


def sync_unknown(cp: CardPayment) -> str:
    """Для 'unknown': узнать у шлюза, списалось ли."""
    try:
        d = rahmat_service._request("GET", f"/payment/hold/{cp.uuid}")
    except RahmatError:
        return cp.status
    hs, ps = d.get("status"), (d.get("payment") or {}).get("status")
    if hs == "charged" or ps == "success":
        cp.status = "charged"
    elif hs in ("canceled", "cancelled") or ps in ("error", "revert"):
        cp.status = "failed"
    return cp.status


def pay_now(db: Session, user: User, card: UserCard, amount: Decimal, order_id: int) -> CardPayment:
    """
    E7 «Boshqa karta tanlash» / «Qayta urinish»: холд на всю сумму и сразу
    списание. Отдельного метода прямого платежа по токену не берём —
    холд+charge уже проверен на шлюзе и даёт тот же результат.
    """
    cp = CardPayment(user_id=user.id, card_id=card.id, order_id=order_id, amount=amount, status="draft")
    db.add(cp)
    try:
        d = rahmat_service._request("POST", "/payment/hold", {
            "card": {"token": card.token},
            "amount": _tiyin(amount),
            "store_id": int(settings.RAHMAT_STORE_ID),
            "invoice_id": f"order-{order_id}",
            "expiry": 60,
        })
        cp.uuid = (d.get("payment") or {}).get("uuid")
        c = rahmat_service._request("PUT", f"/payment/hold/{cp.uuid}", {})
        if c.get("status") != "active":
            cp.status = "failed"
            return cp
        cp.status = "active"
    except RahmatError as exc:
        cp.status = "failed"
        cp.error = f"{exc.code}: {exc}"[:500]
        return cp
    charge_hold(cp)
    return cp
