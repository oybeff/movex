"""
Nizolar (Figma «Admin panel» 07 — N1…N3) va ilovadagi nizo ekrani.

Nizo — order_problems qatori; endi hamma turdagi buyurtma uchun
(equipment | freight | material) va uni mijoz ham, ijrochi ham ochadi.
Muloqot — dispute_messages (uch tomonlama + ichki izoh).

QAROR (resolve) — pul shu yerda harakatlanadi, lekin YANGI pul mantig'i
yo'q: hamma yo'l mavjud funksiyalar orqali.
  client    — buyurtma bekor: admin_order_service.cancel (faqat muzlatish yechiladi)
  performer — buyurtma yakunlanadi: update_order / freight.finish / deliver_order
  partial   — qaytariladigan qism (R) muzlatishdan yechiladi va buyurtma
              summasidan ayiriladi, keyin odatdagidek yakunlanadi:
              mijoz (summa − R) to'laydi, ijrochi (summa − R − komissiya) oladi.
              Faqat Go wallet: karta holdini qisman yechib bo'lmaydi, naqd
              pul tizimda yo'q.
  close     — pul qimirlamaydi.
"""
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import List, Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.media import is_own_media
from app.models.admin_action import AdminAction
from app.models.balance import Balance, BalanceTransaction
from app.models.catalog import FreightOrder
from app.models.equipment import Equipment
from app.models.material import MaterialOrder
from app.models.order import Order
from app.models.order_problem import (
    CLIENT_REASONS, PERFORMER_REASONS, PROBLEM_KINDS, DisputeMessage, OrderProblem,
)
from app.models.user import User
from app.schemas.order import OrderUpdate
from app.services import (
    admin_order_service, freight_service, material_service, notification_service, order_flow_service,
    order_service, pricing_service,
)

DECISIONS = ("client", "partial", "performer", "close")
VISIBILITY = ("all", "client", "performer", "internal")
#: Yakunlangan buyurtma bo'yicha nizo shu muddat ichida ochiladi
AFTER_DONE = timedelta(days=3)


def _dec(v) -> Decimal:
    return Decimal(str(v)) if v is not None else Decimal("0")


def _now():
    return datetime.now(timezone.utc)


# =================================================================== buyurtma tomonlari

def order_info(db: Session, kind: str, order_id: int) -> dict:
    """
    client_id, performer_ids (materialda sotuvchi va haydovchi), active,
    closed_at, payment, amount.
    """
    if kind == "equipment":
        o = db.query(Order).filter(Order.id == order_id).first()
        if o is None:
            raise HTTPException(404, "Buyurtma topilmadi")
        eq = db.query(Equipment).filter(Equipment.id == o.equipment_id).first()
        return {"order": o, "client_id": o.user_id, "performer_ids": [eq.owner_id] if eq else [],
                "status": o.status, "active": o.status in ("pending", "confirmed"),
                "done": o.status == "completed", "closed_at": o.finished_at or o.updated_at,
                "payment": o.payment_method or "balance", "amount": _dec(o.total_amount)}
    if kind == "freight":
        o = db.query(FreightOrder).filter(FreightOrder.id == order_id).first()
        if o is None:
            raise HTTPException(404, "Buyurtma topilmadi")
        return {"order": o, "client_id": o.client_id, "performer_ids": [o.driver_id] if o.driver_id else [],
                "status": o.status, "active": o.status not in ("done", "cancelled"),
                "done": o.status == "done", "closed_at": o.finished_at or o.updated_at,
                "payment": o.payment_method, "amount": _dec(o.price)}
    if kind == "material":
        o = db.query(MaterialOrder).filter(MaterialOrder.id == order_id).first()
        if o is None:
            raise HTTPException(404, "Buyurtma topilmadi")
        perf = [o.seller_id] + ([o.driver_id] if o.driver_id else [])
        return {"order": o, "client_id": o.buyer_id, "performer_ids": perf,
                "status": o.status, "active": o.status in ("pending", "confirmed"),
                "done": o.status == "delivered", "closed_at": o.updated_at,
                "payment": "balance", "amount": _dec(o.goods_amount)}
    raise HTTPException(400, "Noma'lum buyurtma turi")


def _role(info: dict, user_id: int) -> Optional[str]:
    if user_id == info["client_id"]:
        return "client"
    if user_id in info["performer_ids"]:
        return "performer"
    return None


# =================================================================== ilova: ochish va ko'rish

def _check_photos(photos) -> list:
    photos = list(photos or [])
    if len(photos) > 3:
        raise HTTPException(400, "3 tagacha rasm")
    for url in photos:
        if not (is_own_media(url) and url.startswith("/static/problems/")):
            raise HTTPException(400, "Rasm manzili noto'g'ri")
    return photos


def open_dispute(db: Session, user: User, kind: str, order_id: int, reason: str,
                 comment: Optional[str], photos) -> OrderProblem:
    if kind not in PROBLEM_KINDS:
        raise HTTPException(400, "Noma'lum buyurtma turi")
    info = order_info(db, kind, order_id)
    role = _role(info, user.id)
    if role is None:
        raise HTTPException(403, "Bu buyurtmaga ruxsat yo'q")
    if reason not in (CLIENT_REASONS if role == "client" else PERFORMER_REASONS):
        raise HTTPException(400, "Sabab noto'g'ri")
    photos = _check_photos(photos)
    if not info["active"]:
        if not info["done"]:
            raise HTTPException(409, "Bekor qilingan buyurtma bo'yicha nizo ochib bo'lmaydi")
        closed = info["closed_at"]
        if closed is not None and closed < _now() - AFTER_DONE:
            raise HTTPException(409, "Yakunlanganiga 3 kundan oshdi — Yordam chatiga yozing")
    existing = (db.query(OrderProblem)
                .filter(OrderProblem.kind == kind, OrderProblem.order_id == order_id,
                        OrderProblem.user_id == user.id, OrderProblem.status == "open").first())
    if existing:
        return existing

    if kind == "equipment" and role == "client" and info["status"] == "confirmed":
        # B5 — avtotasdiqni to'xtatish ham shu funksiyada
        p = order_flow_service.report_problem(db, order_id, user, reason, comment, photos)
    else:
        p = OrderProblem(kind=kind, order_id=order_id, user_id=user.id, opened_role=role, reason=reason,
                         comment=(comment or "").strip()[:1000] or None, photos=photos or None)
        db.add(p)
        db.commit()
        db.refresh(p)
    p.kind = kind
    p.opened_role = role
    db.commit()
    db.refresh(p)
    return p


def _visible(m: DisputeMessage, role: str, user_id: int) -> bool:
    return m.author_id == user_id or m.visibility == "all" or m.visibility == role


def _problem_for(db: Session, user: User, problem_id: int):
    p = db.query(OrderProblem).filter(OrderProblem.id == problem_id).first()
    if p is None:
        raise HTTPException(404, "Nizo topilmadi")
    info = order_info(db, p.kind, p.order_id)
    role = _role(info, user.id)
    if role is None:
        raise HTTPException(404, "Nizo topilmadi")
    return p, info, role


def read(db: Session, user: User, problem_id: int) -> dict:
    p, info, role = _problem_for(db, user, problem_id)
    msgs = (db.query(DisputeMessage).filter(DisputeMessage.problem_id == p.id)
            .order_by(DisputeMessage.created_at).all())
    authors = {u.id: u.full_name for u in db.query(User).filter(
        User.id.in_({m.author_id for m in msgs if m.author_id} | {p.user_id}))}
    return {
        **_summary(p, role),
        "comment": p.comment, "photos": p.photos or [],
        "opened_by_name": authors.get(p.user_id),
        "messages": [{
            "id": m.id, "mine": m.author_id == user.id, "author_role": m.author_role,
            "author_name": "MoveX GO" if m.author_role == "admin" else authors.get(m.author_id),
            "text": m.text, "photos": m.photos or [], "created_at": m.created_at,
        } for m in msgs if m.visibility != "internal" and _visible(m, role, user.id)],
    }


def _summary(p: OrderProblem, role: str) -> dict:
    return {
        "id": p.id, "kind": p.kind, "order_id": p.order_id, "reason": p.reason, "status": p.status,
        "my_role": role, "opened_by_me": None, "resolution": p.resolution,
        "refund_amount": p.refund_amount, "created_at": p.created_at, "resolved_at": p.resolved_at,
    }


def list_mine(db: Session, user: User) -> List[dict]:
    """Foydalanuvchi ochgan yoki tomon bo'lgan nizolar (oxirgi 50 ta)."""
    rows = db.query(OrderProblem).order_by(OrderProblem.created_at.desc()).limit(500).all()
    out = []
    for p in rows:
        if p.user_id == user.id:
            role = p.opened_role
        else:
            try:
                role = _role(order_info(db, p.kind, p.order_id), user.id)
            except HTTPException:
                role = None
        if role:
            s = _summary(p, role)
            s["opened_by_me"] = p.user_id == user.id
            out.append(s)
        if len(out) >= 50:
            break
    return out


def post_message(db: Session, user: User, problem_id: int, text: Optional[str], photos) -> dict:
    p, info, role = _problem_for(db, user, problem_id)
    if p.status != "open":
        raise HTTPException(409, "Nizo yopilgan")
    text = (text or "").strip()[:2000]
    photos = _check_photos(photos)
    if not text and not photos:
        raise HTTPException(400, "Xabar bo'sh")
    m = DisputeMessage(problem_id=p.id, author_id=user.id, author_role=role, visibility="all",
                       text=text or None, photos=photos or None)
    db.add(m)
    db.commit()
    return {"id": m.id}


# =================================================================== admin

def _notify(db: Session, user_ids, type_: str, key: str, p: OrderProblem) -> None:
    for uid in {u for u in user_ids if u}:
        try:
            notification_service.create_localized(
                db, uid, type_, f"{key}.title", f"{key}.body", None, None, None,
                order_number=p.order_id, dispute_id=p.id)
        except Exception:  # noqa: BLE001
            db.rollback()


def _log(db: Session, admin_id: int, action: str, p: OrderProblem, payload: dict) -> None:
    db.add(AdminAction(admin_id=admin_id, action=action, entity="dispute", entity_id=p.id, payload=payload))
    db.commit()


def admin_message(db: Session, admin_id: int, problem_id: int, text: str, visibility: str) -> dict:
    admin_order_service._admin(db, admin_id)
    if visibility not in VISIBILITY:
        raise HTTPException(400, "Kimga yuborilishini tanlang")
    text = (text or "").strip()[:2000]
    if not text:
        raise HTTPException(400, "Xabar bo'sh")
    p = db.query(OrderProblem).filter(OrderProblem.id == problem_id).first()
    if p is None:
        raise HTTPException(404, "Nizo topilmadi")
    info = order_info(db, p.kind, p.order_id)
    db.add(DisputeMessage(problem_id=p.id, author_id=admin_id, author_role="admin",
                          visibility=visibility, text=text))
    if p.assigned_admin_id is None:
        p.assigned_admin_id = admin_id
    if visibility != "internal" and p.first_response_at is None:
        p.first_response_at = _now()
    db.commit()
    if visibility != "internal":
        to = []
        if visibility in ("all", "client"):
            to.append(info["client_id"])
        if visibility in ("all", "performer"):
            to += info["performer_ids"]
        _notify(db, to, "dispute_message", "dispute_message", p)
    return {"ok": True}


def assign(db: Session, admin_id: int, problem_id: int, to_admin_id: int) -> dict:
    admin_order_service._admin(db, admin_id)
    admin_order_service._admin(db, to_admin_id)
    p = db.query(OrderProblem).filter(OrderProblem.id == problem_id).first()
    if p is None:
        raise HTTPException(404, "Nizo topilmadi")
    p.assigned_admin_id = to_admin_id
    db.commit()
    _log(db, admin_id, "dispute_assign", p, {"to_admin": to_admin_id})
    return {"ok": True}


def decision_options(db: Session, p: OrderProblem) -> dict:
    """Qaysi qarorlar mumkin va nega (panel shuni ko'rsatadi)."""
    info = order_info(db, p.kind, p.order_id)
    o = info["order"]
    opts = {"close": None}
    if not info["active"]:
        why = "Buyurtma allaqachon yopilgan — faqat nizoni yopish (pul qimirlamaydi)"
        opts.update({"client": why, "performer": why, "partial": why})
        return {"options": opts, "amount": info["amount"], "payment": info["payment"]}
    opts["client"] = None
    # Ijrochi foydasiga — buyurtma yakunlanishi mumkin bo'lishi kerak
    perf_why = None
    if p.kind == "equipment" and o.status != "confirmed":
        perf_why = "Ega hali buyurtmani tasdiqlamagan"
    if p.kind == "freight" and o.status not in ("loaded", "arrived"):
        perf_why = "Yuk hali ortilmagan"
    if p.kind == "material" and (o.status != "confirmed" or (
            o.dispatch == "driver" and o.delivery_status not in ("picked_up", "arrived"))):
        perf_why = "Tovar hali yo'lga chiqmagan"
    opts["performer"] = perf_why
    part_why = perf_why
    if part_why is None and info["payment"] != "balance":
        part_why = ("Karta holdini qisman yechib bo'lmaydi" if info["payment"] == "card"
                    else "Naqd to'lov — pul tizimda yo'q")
    opts["partial"] = part_why
    return {"options": opts, "amount": info["amount"], "payment": info["payment"]}


def resolve(db: Session, admin_id: int, problem_id: int, decision: str,
            refund_amount: Optional[Decimal] = None, note: Optional[str] = None) -> dict:
    admin = admin_order_service._admin(db, admin_id)
    if decision not in DECISIONS:
        raise HTTPException(400, "Qarorni tanlang")
    p = db.query(OrderProblem).filter(OrderProblem.id == problem_id).with_for_update().first()
    if p is None:
        raise HTTPException(404, "Nizo topilmadi")
    if p.status != "open":
        raise HTTPException(409, "Nizo allaqachon hal qilingan")
    opts = decision_options(db, p)
    why = opts["options"].get(decision)
    if why:
        raise HTTPException(409, why)
    info = order_info(db, p.kind, p.order_id)
    o = info["order"]
    refund = Decimal("0")

    if decision == "client":
        r = admin_order_service.cancel(db, p.kind, p.order_id, admin_id, "dispute", note, notify=False)
        refund = _dec(r.get("released"))
    elif decision == "performer":
        _complete(db, p.kind, o, admin)
    elif decision == "partial":
        refund = _dec(refund_amount).quantize(Decimal("1"))
        if refund <= 0 or refund >= info["amount"]:
            raise HTTPException(400, "Qaytariladigan summa 0 dan katta va buyurtma summasidan kichik bo'lsin")
        _shrink(db, p.kind, o, refund)
        _complete(db, p.kind, o, admin)

    p = db.query(OrderProblem).filter(OrderProblem.id == problem_id).first()
    p.status = "resolved"
    p.resolution = decision
    p.refund_amount = refund if decision in ("client", "partial") else None
    p.resolved_at = _now()
    p.resolved_by = admin_id
    if p.assigned_admin_id is None:
        p.assigned_admin_id = admin_id
    if p.first_response_at is None:
        p.first_response_at = p.resolved_at
    if p.kind == "equipment":
        eo = db.query(Order).filter(Order.id == p.order_id).first()
        if eo is not None and eo.status == "confirmed":
            eo.problem_reported_at = None
    db.add(DisputeMessage(problem_id=p.id, author_id=admin_id, author_role="admin", visibility="all",
                          text=_decision_text(decision, refund)))
    db.commit()
    _log(db, admin_id, "dispute_resolve", p, {"decision": decision, "refund": str(refund), "note": note,
                                              "kind": p.kind, "order_id": p.order_id})
    _notify(db, [info["client_id"]] + info["performer_ids"], "dispute_resolved", "dispute_resolved", p)
    return {"id": p.id, "status": p.status, "resolution": decision, "refund": refund}


def _decision_text(decision: str, refund: Decimal) -> str:
    amount = f"{int(refund):,}".replace(",", " ")
    return {
        "client": f"Qaror: mijoz foydasiga. Buyurtma bekor qilindi, {amount} so'm qaytarildi.",
        "partial": f"Qaror: qisman. Mijozga {amount} so'm qaytarildi, qolgani ijrochiga o'tdi.",
        "performer": "Qaror: ijrochi foydasiga. Buyurtma yakunlandi.",
        "close": "Nizo yopildi. Pul harakatlanmadi.",
    }[decision]


def _complete(db: Session, kind: str, o, admin: User) -> None:
    if kind == "equipment":
        order_service.update_order(db, o.id, OrderUpdate(status="completed"), o.user_id)
    elif kind == "freight":
        client = db.query(User).filter(User.id == o.client_id).first()
        freight_service.finish(db, client, o.id)
    else:
        material_service.deliver_order(db, o.id, admin)


def _shrink(db: Session, kind: str, o, refund: Decimal) -> None:
    """Qisman qaror: R muzlatishdan yechiladi va buyurtma summasidan ayiriladi. Commit — shu yerda."""
    client_id = {"equipment": getattr(o, "user_id", None), "freight": getattr(o, "client_id", None),
                 "material": getattr(o, "buyer_id", None)}[kind]
    bal = db.query(Balance).filter(Balance.user_id == client_id).with_for_update().first()
    if bal is None or _dec(o.frozen_amount) < refund:
        raise HTTPException(409, "Muzlatilgan summa qaytarishga yetmaydi")
    cur = _dec(bal.frozen_balance)
    bal.frozen_balance = cur - refund if cur >= refund else Decimal("0")
    o.frozen_amount = _dec(o.frozen_amount) - refund
    if kind == "equipment":
        o.total_amount = _dec(o.total_amount) - refund
        o.commission = min(_dec(o.commission), _dec(o.total_amount))
    elif kind == "freight":
        o.price = _dec(o.price) - refund
        o.driver_fee = _dec(o.driver_fee if o.driver_fee is not None else o.price + refund) - refund
        o.driver_commission = min(_dec(o.driver_commission), _dec(o.driver_fee))
    else:
        o.goods_amount = _dec(o.goods_amount) - refund
        o.total_amount = _dec(o.total_amount) - refund
        o.commission = min(_dec(o.commission), _dec(o.goods_amount))
    db.add(BalanceTransaction(user_id=client_id, amount=refund, type="refund", status="completed",
                              description=f"Nizo bo'yicha qaytarildi — buyurtma #{o.id}"))
    db.commit()
