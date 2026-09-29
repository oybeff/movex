from sqlalchemy import Boolean, Column, Integer, Numeric, String, Text, DateTime
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

    # Interfeys tili. Serverda yoziladigan matnlar (xabarnoma, push) shu
    # til bo'yicha tuziladi.
    #
    # Ilovaning o'zi tarjimani bilardi, lekin push matnini SERVER yozadi va
    # telefon ekranida uni qayta tarjima qilib bo'lmaydi. Shuning uchun til
    # bazada ham turishi kerak.
    language = Column(String(5), nullable=False, default="uz")

    # Adminkadan boshqariladi.
    #
    # is_blocked — umuman kira olmaydi. Kirish paytida tekshiriladi.
    # is_frozen  — kiradi va hammasini ko'radi, lekin buyurtma bera olmaydi,
    #              taklif yubora olmaydi, e'lon qo'ya olmaydi va pul yecha
    #              olmaydi. Nizoli holatlar uchun: odamni yo'qotmaymiz,
    #              lekin pul harakatini to'xtatamiz.
    is_blocked = Column(Boolean, nullable=False, default=False)
    is_frozen = Column(Boolean, nullable=False, default=False)
    blocked_reason = Column(Text, nullable=True)

    last_login_at = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint("role IN ('client','owner','admin')", name="check_role"),
        CheckConstraint(
            "search_radius_km > 0 AND search_radius_km <= 1000",
            name="check_search_radius",
        ),
        CheckConstraint("language IN ('uz','ru')", name="check_user_language"),
    )
