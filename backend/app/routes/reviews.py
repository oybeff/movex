from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.schemas import review as review_schema
from app.services import review_service
from app.dependencies import get_db, get_current_user

router = APIRouter()


def _own_or_admin(review, current_user):
    if review.user_id != current_user.id and getattr(current_user, "role", None) != "admin":
        raise HTTPException(status_code=403, detail="Faqat o'z sharhingizni o'zgartira olasiz")


@router.post("/", response_model=review_schema.ReviewRead)
def create_review(review: review_schema.ReviewCreate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Sharh qoldirish. Muallif tokendan olinadi."""
    return review_service.create_review(db, review, current_user.id)


@router.get("/", response_model=list[review_schema.ReviewRead])
def get_reviews(
    equipment_id: Optional[int] = Query(None, description="Texnika bo'yicha filtr"),
    skip: int = 0,
    limit: int = Query(100, le=200),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
):
    return review_service.get_reviews(db, skip, limit, equipment_id)


@router.get("/{review_id}", response_model=review_schema.ReviewRead)
def get_review(review_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    db_review = review_service.get_review(db, review_id)
    if not db_review:
        raise HTTPException(status_code=404, detail="Review not found")
    return db_review


@router.put("/{review_id}", response_model=review_schema.ReviewRead)
def update_review(review_id: int, review: review_schema.ReviewUpdate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """O'z sharhini tahrirlash."""
    db_review = review_service.get_review(db, review_id)
    if not db_review:
        raise HTTPException(status_code=404, detail="Review not found")
    _own_or_admin(db_review, current_user)
    return review_service.update_review(db, review_id, review)


@router.delete("/{review_id}", response_model=dict)
def delete_review(review_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """O'z sharhini o'chirish."""
    db_review = review_service.get_review(db, review_id)
    if not db_review:
        raise HTTPException(status_code=404, detail="Review not found")
    _own_or_admin(db_review, current_user)
    review_service.delete_review(db, review_id)
    return {"message": "Review deleted successfully"}
