"""
«Yuk tashish» — перевозка груза клиента из А в Б (24.11.2026).
Логика — app/services/freight_service.py. Водительские адреса — в
routes/drivers.py (/drivers/freight/*).
"""
from datetime import datetime
from decimal import Decimal
from typing import Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.user import User
from app.routes.auth import get_current_user
from app.services import freight_service

router = APIRouter()


class FreightCreate(BaseModel):
    vehicle_code: str = Field(max_length=30)
    body_type: Optional[str] = Field(default=None, pattern="^(tent|open|van|isothermal|fridge|tank|manipulator)$")
    cargo_type: Optional[str] = Field(default=None, max_length=20)
    cargo_length_m: Optional[Decimal] = Field(default=None, gt=0, le=Decimal("30"))
    cargo_width_m: Optional[Decimal] = Field(default=None, gt=0, le=Decimal("5"))
    cargo_height_m: Optional[Decimal] = Field(default=None, gt=0, le=Decimal("5"))
    cargo_volume_m3: Optional[Decimal] = Field(default=None, gt=0, le=Decimal("200"))
    needs_loader: bool = False
    loader_mode: Optional[str] = Field(default="hour", pattern="^(hour|day)$")
    loader_hours: Optional[int] = Field(default=None, ge=1, le=24)
    scheduled_at: Optional[datetime] = None
    cargo_tonnes: Optional[Decimal] = Field(default=None, gt=0, le=Decimal("100"))
    cargo_note: Optional[str] = Field(default=None, max_length=1000)
    from_address: Optional[str] = Field(default=None, max_length=500)
    from_latitude: float = Field(ge=-90, le=90)
    from_longitude: float = Field(ge=-180, le=180)
    to_address: Optional[str] = Field(default=None, max_length=500)
    to_latitude: float = Field(ge=-90, le=90)
    to_longitude: float = Field(ge=-180, le=180)
    hours: Optional[int] = Field(default=None, ge=1, le=48)
    payment_method: Optional[str] = Field(default="balance", pattern="^(balance|cash)$")


@router.get("/quote")
def freight_quote(
    from_lat: float = Query(..., ge=-90, le=90),
    from_lon: float = Query(..., ge=-180, le=180),
    to_lat: float = Query(..., ge=-90, le=90),
    to_lon: float = Query(..., ge=-180, le=180),
    tonnes: Optional[Decimal] = Query(None, gt=0, le=100),
    hours: Optional[int] = Query(None, ge=1, le=48),
    body: Optional[str] = Query(None, max_length=20),
    weight_kg: Optional[Decimal] = Query(None, gt=0, le=100000),
    length: Optional[Decimal] = Query(None, gt=0, le=30),
    width: Optional[Decimal] = Query(None, gt=0, le=5),
    height: Optional[Decimal] = Query(None, gt=0, le=5),
    loader: bool = Query(False),
    loader_mode: Optional[str] = Query(None, pattern="^(hour|day)$"),
    loader_hours: Optional[int] = Query(None, ge=1, le=24),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Все грузовики с ценой на маршрут и подсказка, какой подходит по весу."""
    return freight_service.quote(db, from_lat, from_lon, to_lat, to_lon, tonnes, hours, body,
                                 weight_kg, length, width, height, loader,
                                 loader_mode, loader_hours)


@router.post("/orders")
def freight_create(data: FreightCreate, db: Session = Depends(get_db),
                   current_user: User = Depends(get_current_user)):
    return freight_service.read(db, freight_service.create(db, current_user, data), current_user)


@router.get("/orders")
def freight_my_orders(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return [freight_service.read(db, o, current_user) for o in freight_service.client_orders(db, current_user)]


@router.post("/orders/{order_id}/cancel")
def freight_cancel(order_id: int, db: Session = Depends(get_db),
                   current_user: User = Depends(get_current_user)):
    return freight_service.read(db, freight_service.client_cancel(db, current_user, order_id), current_user)


@router.post("/orders/{order_id}/finish")
def freight_finish(order_id: int, db: Session = Depends(get_db),
                   current_user: User = Depends(get_current_user)):
    return freight_service.read(db, freight_service.finish(db, current_user, order_id), current_user)
