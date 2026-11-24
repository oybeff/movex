"""Admin P5 jadvallari (Figma «Admin panel» 00, 01, 08, 09).

Kirish, taklif va ishonchli qurilmalar bilan PHP panel o'zi ishlaydi;
modellar bu yerda — bo'sh bazada init_db (create_all) ham ularni yaratsin.
"""
from sqlalchemy import (Boolean, CheckConstraint, Column, DateTime, ForeignKey, Integer, Numeric,
                        String, Text, func)
from sqlalchemy.dialects.postgresql import JSONB

from app.db.base import Base

ADMIN_ROLES = ("super_admin", "operator", "finance", "moderator", "support")
_ROLES_SQL = "(" + ",".join(f"'{r}'" for r in ADMIN_ROLES) + ")"


class AdminLoginAttempt(Base):
    __tablename__ = "admin_login_attempts"

    id = Column(Integer, primary_key=True)
    login = Column(String(50), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=True)
    stage = Column(String(10), nullable=False)
    success = Column(Boolean, nullable=False)
    ip = Column(String(64), nullable=True)
    user_agent = Column(String(300), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False, index=True)

    __table_args__ = (CheckConstraint("stage IN ('password','sms','reset')", name="check_admin_login_stage"),)


class AdminOtp(Base):
    __tablename__ = "admin_otp"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    purpose = Column(String(10), nullable=False)
    code_hash = Column(String(255), nullable=False)
    attempts = Column(Integer, nullable=False, server_default="0")
    expires_at = Column(DateTime(timezone=True), nullable=False)
    used_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (CheckConstraint("purpose IN ('login','reset')", name="check_admin_otp_purpose"),)


class AdminTrustedDevice(Base):
    __tablename__ = "admin_trusted_devices"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    token_hash = Column(String(64), nullable=False, unique=True)
    user_agent = Column(String(300), nullable=True)
    ip = Column(String(64), nullable=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class AdminInvite(Base):
    __tablename__ = "admin_invites"

    id = Column(Integer, primary_key=True)
    token_hash = Column(String(64), nullable=False, unique=True)
    phone = Column(String(20), nullable=False)
    full_name = Column(String(120), nullable=False)
    admin_role = Column(String(20), nullable=False)
    invited_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    accepted_at = Column(DateTime(timezone=True), nullable=True)
    revoked_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (CheckConstraint(f"admin_role IN {_ROLES_SQL}", name="check_admin_invite_role"),)


class PushCampaign(Base):
    __tablename__ = "push_campaigns"

    id = Column(Integer, primary_key=True)
    title_uz = Column(String(120), nullable=False)
    body_uz = Column(Text, nullable=False)
    title_ru = Column(String(120), nullable=True)
    body_ru = Column(Text, nullable=True)
    audience = Column(JSONB, nullable=False)
    status = Column(String(12), nullable=False, server_default="draft")
    scheduled_at = Column(DateTime(timezone=True), nullable=True)
    sent_at = Column(DateTime(timezone=True), nullable=True)
    recipients = Column(Integer, nullable=False, server_default="0")
    pushed = Column(Integer, nullable=False, server_default="0")
    error = Column(Text, nullable=True)
    created_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        CheckConstraint("status IN ('draft','scheduled','sending','sent','failed','cancelled')",
                        name="check_push_campaign_status"),
    )


class DriverLocation(Base):
    __tablename__ = "driver_locations"

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    online = Column(Boolean, nullable=False, server_default="false")
    latitude = Column(Numeric(10, 7), nullable=True)
    longitude = Column(Numeric(10, 7), nullable=True)
    accuracy_m = Column(Numeric(8, 1), nullable=True)
    speed_kmh = Column(Numeric(6, 1), nullable=True)
    heading = Column(Numeric(5, 1), nullable=True)
    location_at = Column(DateTime(timezone=True), nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
