from typing import Optional

from sqlalchemy.orm import Session

from app.models.review import Review
from app.schemas.review import ReviewCreate, ReviewUpdate


def create_review(db: Session, review: ReviewCreate, user_id: int):
    """
    Yangi sharh.

    Muallif tokendan olinadi. Ilgari bu funksiya user_id ni qabul qilmasdi,
    lekin route uni uchinchi argument sifatida uzatardi — natijada har bir
    sharh yaratish 500 xato bilan tugardi.
    """
    db_review = Review(**review.dict(), user_id=user_id)
    db.add(db_review)
    db.commit()
    db.refresh(db_review)
    return db_review


def get_review(db: Session, review_id: int):
    """Bitta sharhni olish"""
    return db.query(Review).filter(Review.id == review_id).first()


def get_reviews(db: Session, skip: int = 0, limit: int = 100, equipment_id: Optional[int] = None):
    """
    Sharhlar ro'yxati. Sharhlar ochiq ma'lumot, lekin odatda muayyan
    texnika bo'yicha kerak bo'ladi.
    """
    # Admin yashirgan sharhlar (Figma N4) ilovada ko'rinmaydi
    query = db.query(Review).filter(Review.hidden.is_(False))
    if equipment_id is not None:
        query = query.filter(Review.equipment_id == equipment_id)
    return query.order_by(Review.created_at.desc()).offset(skip).limit(limit).all()


def update_review(db: Session, review_id: int, review: ReviewUpdate):
    """Sharhni yangilash"""
    db_review = db.query(Review).filter(Review.id == review_id).first()
    if not db_review:
        return None
    for key, value in review.dict(exclude_unset=True).items():
        setattr(db_review, key, value)
    db.commit()
    db.refresh(db_review)
    return db_review


def delete_review(db: Session, review_id: int):
    """Sharhni o'chirish"""
    db_review = db.query(Review).filter(Review.id == review_id).first()
    if db_review:
        db.delete(db_review)
        db.commit()
    return db_review


def moderate(db: Session, admin_id: int, review_id: int, hide: bool, reason: Optional[str] = None) -> dict:
    """
    Figma N4: admin sharhni yashiradi yoki qoldiradi. Yashirilgan sharh
    reytingga kirmaydi va ilovada ko'rinmaydi; muallifga xabar boradi.
    """
    from datetime import datetime, timezone

    from fastapi import HTTPException

    from app.models.admin_action import AdminAction
    from app.services import admin_order_service, notification_service

    admin_order_service._admin(db, admin_id)
    r = db.query(Review).filter(Review.id == review_id).first()
    if r is None:
        raise HTTPException(404, "Sharh topilmadi")
    was_hidden = bool(r.hidden)
    r.hidden = bool(hide)
    r.hidden_reason = (reason or None) if hide else None
    r.moderated_at = datetime.now(timezone.utc)
    r.moderated_by = admin_id
    db.add(AdminAction(admin_id=admin_id, action="review_hide" if hide else "review_keep",
                       entity="review", entity_id=r.id, payload={"reason": reason}))
    db.commit()
    if hide and not was_hidden:
        try:
            notification_service.create_localized(
                db, r.user_id, "review_hidden", "review_hidden.title", "review_hidden.body", None, None, None)
        except Exception:  # noqa: BLE001
            db.rollback()
    return {"id": r.id, "hidden": r.hidden}
