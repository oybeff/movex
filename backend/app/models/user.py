from sqlalchemy import Column, Integer, Numeric, String, Text, DateTime
from sqlalchemy.sql import func
from sqlalchemy import CheckConstraint
from app.db.base import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    full_name = Column(String(100), nullable=False)
    email = Column(String(100), unique=True, index=True, nullable=True)  # Optional
    phone = Column(String(20), unique=True, index=True, nullable=False)  # Required
    password_hash = Column(Text, nullable=False)
    role = Column(String(20), nullable=False)

    # To'lovni bo'lish (split) uchun texnika egasining Payme'dagi qabul
    # qiluvchi identifikatori. Bo'sh bo'lsa — bo'lish o'tkazib yuboriladi,
    # pul odatdagidek platformaga tushadi va keyin qo'lda o'tkaziladi.
    payme_receiver_id = Column(String(50), nullable=True)

    # Qidiruv va xabarnoma radiusi.
    #
    # Egasi uchun: shu nuqtadan radius ichidagi zayavkalar haqida xabar
    # keladi — butun O'zbekiston bo'ylab bildirishnoma olish ma'nosiz.
    # Mijoz uchun: katalog va xaritada shu radiusdagi texnika ko'rsatiladi.
    #
    # Nuqta bo'sh bo'lsa radius ishlatilmaydi va hech narsa filtrlanmaydi:
    # sozlamagan foydalanuvchi hech narsa ko'rmay qolmasligi kerak.
    search_latitude = Column(Numeric(10, 7), nullable=True)
    search_longitude = Column(Numeric(10, 7), nullable=True)
    search_radius_km = Column(Integer, nullable=False, default=100)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint("role IN ('client','owner','admin')", name="check_role"),
        CheckConstraint(
            "search_radius_km > 0 AND search_radius_km <= 1000",
            name="check_search_radius",
        ),
    )
