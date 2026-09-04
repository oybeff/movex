"""
Telegram orqali kirish.

Nega ikkita jadval. Telegram boti odamga BIRINCHI bo'lib yoza olmaydi va
telefon raqami bo'yicha odamni topa olmaydi — bunday API yo'q. Shuning
uchun kirish ikki bosqichli:

  1. Ilova havola beradi: t.me/bot?start=<token>. Odam Start bosadi va
     raqamini ulashadi — shundagina biz uning chat_id sini bilamiz.
     Bu telegram_login_requests.
  2. Bog'lanish saqlanadi (telegram_accounts), va KEYINGI kirishlarda
     kod to'g'ridan-to'g'ri Telegramga yuboriladi — havola kerak emas.

Raqam Telegramning O'ZIDAN keladi (contact xabari), ya'ni u allaqachon
tasdiqlangan: odam boshqa birovning raqamini yozib yubora olmaydi.
"""
from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
)
from sqlalchemy.sql import func

from app.db.base import Base

#: Kirish havolasi shuncha vaqt yashaydi
LOGIN_REQUEST_TTL_MINUTES = 10


class TelegramAccount(Base):
    """Telefon raqami ↔ Telegram akkaunti bog'lanishi."""

    __tablename__ = "telegram_accounts"

    id = Column(Integer, primary_key=True, index=True)

    #: Telegram chat identifikatori. BigInteger ataylab: Telegram id lari
    #: int32 chegarasidan oshib ketgan.
    chat_id = Column(BigInteger, nullable=False, unique=True, index=True)

    #: 998901234567 ko'rinishida. Telegramning contact xabaridan olinadi,
    #: ya'ni raqam tasdiqlangan.
    phone = Column(String(20), nullable=False, unique=True, index=True)

    username = Column(String(64), nullable=True)
    first_name = Column(String(100), nullable=True)

    #: Foydalanuvchi keyin ro'yxatdan o'tsa bog'lanadi. Bog'lanish
    #: paytida hisob hali bo'lmasligi mumkin — shuning uchun nullable.
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class TelegramLoginRequest(Base):
    """
    Bir martalik kirish so'rovi — chuqur havoladagi token.

    Token TASODIFIY va qisqa umrli: havola boshqa odamga tushsa ham,
    u bilan begona hisobga kirib bo'lmasligi kerak.
    """

    __tablename__ = "telegram_login_requests"

    STATUS_PENDING = "pending"      # havola berildi, Start hali bosilmagan
    STATUS_CONFIRMED = "confirmed"  # raqam ulashildi, kirish mumkin
    STATUS_USED = "used"            # token ishlatildi, qayta ishlatilmaydi

    id = Column(Integer, primary_key=True, index=True)
    token = Column(String(48), nullable=False, unique=True, index=True)

    status = Column(String(20), nullable=False, default=STATUS_PENDING, index=True)

    #: Start bosilgandan keyin to'ladi
    phone = Column(String(20), nullable=True, index=True)
    chat_id = Column(BigInteger, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
    expires_at = Column(DateTime(timezone=True), nullable=False, index=True)

    __table_args__ = (
        CheckConstraint(
            "status IN ('pending','confirmed','used')",
            name="check_tg_login_status",
        ),
    )
