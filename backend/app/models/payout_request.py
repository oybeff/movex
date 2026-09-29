from sqlalchemy import CheckConstraint, Column, DateTime, ForeignKey, Integer, Numeric, String, Text
from sqlalchemy.sql import func

from app.db.base import Base


class PayoutRequest(Base):
    """
    Texnika egasining pul yechish arizasi.

    Ilgari bunday imkoniyat umuman yo'q edi: egasining balansi o'sib borardi,
    lekin pulni olib chiqishning hech qanday yo'li yo'q edi.

    Pul harakati:
      ariza berilganda  — summa frozen_balance ga o'tadi (ikki marta
                          so'ralmasligi uchun);
      to'langanda       — balansdan yechiladi va muzlatish olib tashlanadi;
      rad etilganda     — faqat muzlatish olib tashlanadi, pul egasida qoladi.
    """

    __tablename__ = "payout_requests"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    # amount — egasi so'ragan summa, balansdan aynan shu ushlab qolinadi.
    # commission — platforma ulushi, payout_amount — kartaga o'tkaziladigan
    # qolgan qism. Uchalasi ham saqlanadi: sozlama keyin o'zgarsa, eski ariza
    # yangi foiz bo'yicha qayta hisoblanib, tarixni yolg'on ko'rsatardi.
    amount = Column(Numeric(12, 2), nullable=False)
    commission = Column(Numeric(12, 2), nullable=False, default=0)
    payout_amount = Column(Numeric(12, 2), nullable=False)

    # pending — ko'rib chiqilmoqda, paid — to'langan, rejected — rad etilgan
    status = Column(String(20), nullable=False, default="pending", index=True)

    # Pul o'tkaziladigan karta. MAXFIY ma'lumot: ochiq API'da hech qachon
    # to'liq qaytarilmaydi, faqat oxirgi 4 raqami ko'rsatiladi.
    card_number = Column(String(32), nullable=False)
    card_holder = Column(String(100), nullable=True)

    # ------------------------------------------------- Rahmat (Multicard)
    #
    # Pul kartaga SHLYUZ orqali o'tadi (POST /payment/credit), qo'lda emas.
    # `rahmat_uuid` shu o'tkazmaning raqami: so'rov timeout bilan tugasa
    # yoki ERROR_UNKNOWN qaytsa, hujjat qayta yuborishni emas, HOLATNI
    # so'rashni talab qiladi — usiz bir arizaga pul ikki marta ketardi.
    rahmat_uuid = Column(String(64), nullable=True, index=True)
    #: Shlyuzning o'z holati: draft / progress / success / error / revert
    rahmat_status = Column(String(20), nullable=True)
    rahmat_receipt_url = Column(String(500), nullable=True)
    #: Oxirgi xato. Ariza 'pending' da qoladi, lekin admin nima
    #: bo'lganini ko'rishi kerak — jim qolgan xato eng yomon holat.
    rahmat_error = Column(Text, nullable=True)

    comment = Column(Text, nullable=True)            # egasining izohi
    admin_comment = Column(Text, nullable=True)      # rad etish sababi
    processed_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    processed_at = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint("amount > 0", name="check_payout_amount_positive"),
        CheckConstraint("commission >= 0", name="check_payout_commission_not_negative"),
        # Kartaga ketadigan summa musbat: aks holda ega ariza berib,
        # hech narsa olmasdan balansidan ayrilardi.
        CheckConstraint("payout_amount > 0", name="check_payout_amount_positive_net"),
        CheckConstraint(
            "status IN ('pending','paid','rejected')",
            name="check_payout_status",
        ),
    )

    @property
    def card_masked(self) -> str:
        """Ko'rsatish uchun: oxirgi 4 raqamdan boshqasi yashiriladi."""
        digits = "".join(ch for ch in (self.card_number or "") if ch.isdigit())
        return f"•••• {digits[-4:]}" if len(digits) >= 4 else "••••"
