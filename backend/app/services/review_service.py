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
    query = db.query(Review)
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
