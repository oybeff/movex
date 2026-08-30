from sqlalchemy.orm import Session
from app.models.review import Review
from app.schemas.review import ReviewCreate, ReviewUpdate


def create_review(db: Session, review: ReviewCreate):
    """Yangi sharh yaratish"""
    db_review = Review(**review.dict())
    db.add(db_review)
    db.commit()
    db.refresh(db_review)
    return db_review


def get_review(db: Session, review_id: int):
    """Bitta sharhni olish"""
    return db.query(Review).filter(Review.id == review_id).first()


def get_reviews(db: Session, skip: int = 0, limit: int = 100):
    """Barcha sharhlarni olish"""
    return db.query(Review).offset(skip).limit(limit).all()


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
