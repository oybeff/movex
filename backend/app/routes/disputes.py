"""
Ilova: nizolar (Figma 07 N2 — tomonlar ilovada yozadi) va «Yordam» chati.
Rasmlar — /orders/problem-photo orqali yuklanadi (/static/problems/...).
"""
from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.routes.auth import get_current_user
from app.services import dispute_service, support_service

router = APIRouter()
support_router = APIRouter()


class _OpenIn(BaseModel):
    kind: str = Field(pattern="^(equipment|freight|material)$")
    order_id: int
    reason: str = Field(max_length=20)
    comment: Optional[str] = Field(default=None, max_length=1000)
    photos: List[str] = Field(default_factory=list, max_length=3)


class _MsgIn(BaseModel):
    text: Optional[str] = Field(default=None, max_length=2000)
    photos: List[str] = Field(default_factory=list, max_length=3)


@router.post("")
def open_dispute(data: _OpenIn, db: Session = Depends(get_db), user=Depends(get_current_user)):
    p = dispute_service.open_dispute(db, user, data.kind, data.order_id, data.reason, data.comment, data.photos)
    return dispute_service.read(db, user, p.id)


@router.get("/mine")
def mine(db: Session = Depends(get_db), user=Depends(get_current_user)):
    return dispute_service.list_mine(db, user)


@router.get("/{problem_id}")
def read(problem_id: int, db: Session = Depends(get_db), user=Depends(get_current_user)):
    return dispute_service.read(db, user, problem_id)


@router.post("/{problem_id}/messages")
def message(problem_id: int, data: _MsgIn, db: Session = Depends(get_db), user=Depends(get_current_user)):
    dispute_service.post_message(db, user, problem_id, data.text, data.photos)
    return dispute_service.read(db, user, problem_id)


class _SupportIn(BaseModel):
    app: str = Field(default="client", pattern="^(client|driver)$")
    text: Optional[str] = Field(default=None, max_length=2000)
    photo: Optional[str] = Field(default=None, max_length=300)


@support_router.get("/thread")
def support_thread(app: str = Query("client", pattern="^(client|driver)$"),
                   db: Session = Depends(get_db), user=Depends(get_current_user)):
    return support_service.get_thread(db, user, app)


@support_router.get("/unread")
def support_unread(app: str = Query("client", pattern="^(client|driver)$"),
                   db: Session = Depends(get_db), user=Depends(get_current_user)):
    return {"count": support_service.unread(db, user, app)}


@support_router.post("/messages")
def support_post(data: _SupportIn, db: Session = Depends(get_db), user=Depends(get_current_user)):
    return support_service.post(db, user, data.app, data.text, data.photo)
