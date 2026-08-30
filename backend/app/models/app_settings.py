from sqlalchemy import Column, Integer, String, Text, DateTime, JSON
from sqlalchemy.sql import func
from app.db.base import Base

class AppSettings(Base):
    __tablename__ = "app_settings"

    id = Column(Integer, primary_key=True, index=True)
    key = Column(String(100), unique=True, nullable=False, index=True)
    value = Column(JSON, nullable=True)
    description = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class ContactMethod(Base):
    __tablename__ = "contact_methods"

    id = Column(Integer, primary_key=True, index=True)
    type = Column(String(50), nullable=False)  # phone, email, telegram, whatsapp, website, sms
    label = Column(String(100), nullable=False)
    value = Column(String(255), nullable=False)
    icon = Column(String(50), nullable=True)
    order = Column(Integer, default=0)
    is_active = Column(Integer, default=1)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

