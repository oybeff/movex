"""
Foydalanuvchi o'z hisobini o'chirishi.

Google Play talabi: ilovada hisob ochish mumkin bo'lsa, uni o'chirishni
ham ilovaning o'zidan boshlash mumkin bo'lishi kerak. Ilgari buni faqat
admin qila olardi (DELETE /users/{id}).

QATTIQ O'CHIRISH EMAS, ANONIMLASHTIRISH. `users` ga bog'langan jadvallarda
ON DELETE CASCADE turibdi: hisob o'chirilsa, u bilan birga ikkinchi
tomonning buyurtmalari, chati va pul harakati yozuvlari ham yo'qolardi.
Shuning uchun:

- ism va telefon o'chiriladi, kirish darhol yopiladi (is_blocked — eski
  token ham o'sha zahoti ishlamay qoladi, get_current_user tekshiradi);
- telefon bo'shaydi: shu raqam bilan keyin yangidan ro'yxatdan o'tish mumkin;
- texnika katalogdan olinadi, ochiq e'lon va zayavkalar yopiladi, kutayotgan
  takliflar qaytariladi, suratlar diskdan o'chiriladi;
- buyurtmalar va pul yozuvlari qoladi — ular ikkinchi tomonniki ham, va
  buxgalteriya hisobi uchun kerak (maxfiylik siyosatida shunday yozilgan).

PUL BOR EKAN — O'CHIRIB BO'LMAYDI. Yechish mumkin bo'lgan summa, muzlatilgan
summa (eskrou yoki pul yechish arizasi) yoki tugallanmagan buyurtma bo'lsa
rad etiladi: avval pulni yechib olsin yoki bitimni yakunlasin. Sovg'a
(bonus_balance) bunga kirmaydi — uni baribir yechib bo'lmaydi, hisob bilan
birga yo'qoladi.
"""
import secrets
from decimal import Decimal
from typing import List

from fastapi import HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.core import media
from app.core.messages import t
from app.core.security import hash_password
from app.models.balance import Balance
from app.models.equipment import Equipment, EquipmentPhoto
from app.models.equipment_request import EquipmentRequest, RequestOffer
from app.models.listing import Listing, ListingOffer, ListingPhoto, ListingReaction
from app.models.material import MaterialOrder, MaterialPhoto, MaterialProduct
from app.models.notification import DeviceToken, Notification
from app.models.order import Order
from app.models.payout_request import PayoutRequest
from app.models.user import User
from app.services.balance_service import withdrawable_balance
from datetime import datetime

ACTIVE_ORDER = ("pending", "confirmed")
ACTIVE_MATERIAL_ORDER = ("pending", "confirmed")
ACTIVE_LISTING = ("taken", "confirmed")


def blockers(db: Session, user: User, lock: bool = False) -> List[str]:
    """Nega hozir o'chirib bo'lmaydi — xabar kalitlari ro'yxati."""
    reasons = []

    if user.role == "admin":
        return ["account_delete.admin"]

    q = db.query(Balance).filter(Balance.user_id == user.id)
    if lock:
        # Parallel pul yechish arizasi bilan poyga bo'lmasin
        q = q.with_for_update()
    balance = q.first()
    if balance is not None:
        if withdrawable_balance(balance) > 0:
            reasons.append("account_delete.has_money")
        if Decimal(str(balance.frozen_balance or 0)) > 0:
            reasons.append("account_delete.frozen")

    pending_payout = (
        db.query(PayoutRequest.id)
        .filter(PayoutRequest.user_id == user.id, PayoutRequest.status == "pending")
        .first()
    )
    if pending_payout and "account_delete.frozen" not in reasons:
        reasons.append("account_delete.frozen")

    own_equipment = db.query(Equipment.id).filter(Equipment.owner_id == user.id)
    active_order = (
        db.query(Order.id)
        .filter(
            Order.status.in_(ACTIVE_ORDER),
            or_(Order.user_id == user.id, Order.equipment_id.in_(own_equipment)),
        )
        .first()
    )
    active_material = (
        db.query(MaterialOrder.id)
        .filter(
            MaterialOrder.status.in_(ACTIVE_MATERIAL_ORDER),
            or_(MaterialOrder.buyer_id == user.id, MaterialOrder.seller_id == user.id),
        )
        .first()
    )
    active_listing = (
        db.query(Listing.id)
        .filter(
            Listing.status.in_(ACTIVE_LISTING),
            or_(Listing.client_id == user.id, Listing.taken_by == user.id),
        )
        .first()
    )
    if active_order or active_material or active_listing:
        reasons.append("account_delete.active_deals")

    return reasons


def _drop_photo(db: Session, photo) -> None:
    media.delete_by_url(photo.url)
    db.delete(photo)


def delete_account(db: Session, user: User) -> None:
    reasons = blockers(db, user, lock=True)
    if reasons:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail=" ".join(t(key, user.language) for key in reasons),
        )

    now = datetime.utcnow()

    # --- texnika: katalogdan olinadi, suratlar o'chadi ---
    equipment = (
        db.query(Equipment)
        .filter(Equipment.owner_id == user.id, Equipment.deleted_at.is_(None))
        .all()
    )
    for eq in equipment:
        for photo in list(eq.photos):
            _drop_photo(db, photo)
        if eq.photo_url:
            media.delete_by_url(eq.photo_url)
            eq.photo_url = None
        eq.deleted_at = now

    db.query(RequestOffer).filter(
        RequestOffer.owner_id == user.id, RequestOffer.status == "pending"
    ).update({"status": "withdrawn"}, synchronize_session=False)
    db.query(EquipmentRequest).filter(
        EquipmentRequest.client_id == user.id, EquipmentRequest.status == "open"
    ).update({"status": "cancelled"}, synchronize_session=False)

    # --- e'lonlar ---
    for listing in db.query(Listing).filter(Listing.client_id == user.id).all():
        for photo in db.query(ListingPhoto).filter(ListingPhoto.listing_id == listing.id).all():
            _drop_photo(db, photo)
        if listing.status == "open":
            listing.status = "cancelled"
    db.query(ListingOffer).filter(
        ListingOffer.user_id == user.id, ListingOffer.status == "pending"
    ).update({"status": "withdrawn"}, synchronize_session=False)
    db.query(ListingReaction).filter(ListingReaction.user_id == user.id).delete(
        synchronize_session=False
    )

    # --- stroymateriallar: buyurtmasi borini yashiramiz, yo'g'ini o'chiramiz ---
    for product in db.query(MaterialProduct).filter(MaterialProduct.owner_id == user.id).all():
        for photo in db.query(MaterialPhoto).filter(MaterialPhoto.product_id == product.id).all():
            _drop_photo(db, photo)
        has_orders = (
            db.query(MaterialOrder.id).filter(MaterialOrder.product_id == product.id).first()
        )
        if has_orders:
            product.status = "rejected"
        else:
            db.delete(product)

    # --- faqat shu odamga tegishli narsalar ---
    db.query(Notification).filter(Notification.user_id == user.id).delete(
        synchronize_session=False
    )
    db.query(DeviceToken).filter(DeviceToken.user_id == user.id).delete(
        synchronize_session=False
    )

    # --- shaxsiy ma'lumot ---
    user.full_name = t("account_delete.deleted_name", "uz")
    user.phone = f"deleted-{user.id}"
    user.email = None
    user.password_hash = hash_password(secrets.token_urlsafe(24))
    user.search_latitude = None
    user.search_longitude = None
    user.is_blocked = True
    user.blocked_reason = t("account_delete.blocked_reason", user.language)

    db.commit()
