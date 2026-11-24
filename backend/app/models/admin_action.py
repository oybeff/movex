"""Admin amallari jurnali va buyurtmaga ichki izohlar (Figma «Admin panel» 02, 09)."""
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB

from app.db.base import Base


class AdminAction(Base):
    __tablename__ = "admin_actions"

    id = Column(Integer, primary_key=True)
    admin_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    action = Column(String(40), nullable=False)
    entity = Column(String(20), nullable=False)
    entity_id = Column(Integer, nullable=True)
    payload = Column(JSONB, nullable=True)
    ip = Column(String(64), nullable=True)
    user_agent = Column(String(300), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class OrderNote(Base):
    __tablename__ = "order_notes"

    id = Column(Integer, primary_key=True)
    kind = Column(String(12), nullable=False)
    order_id = Column(Integer, nullable=False)
    admin_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    text = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
