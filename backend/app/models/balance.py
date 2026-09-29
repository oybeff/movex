from sqlalchemy import Column, Integer, Numeric, String, DateTime, ForeignKey
from decimal import Decimal

from sqlalchemy import event
from sqlalchemy.orm import Session
from sqlalchemy.sql import func
from sqlalchemy import CheckConstraint
from app.db.base import Base

class Balance(Base):
    __tablename__ = "balances"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False, index=True)
    balance = Column(Numeric(12,2), default=0.0, nullable=False)  # Umumiy balans
    frozen_balance = Column(Numeric(12,2), default=0.0, nullable=False)  # Muzlatilgan balans (pending orders uchun)
    #: Sovg'aning ishlatilmagan qismi. Ilova ichida ishlatiladi, lekin
    #: kartaga YECHILMAYDI: aks holda har bir yangi SIM kartadan pul
    #: chiqib ketardi. Yechishga mavjud = balance - frozen - bonus.
    bonus_balance = Column(Numeric(12,2), default=0.0, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    __table_args__ = (
        CheckConstraint("balance >= 0", name="check_balance_non_negative"),
        CheckConstraint("frozen_balance >= 0", name="check_frozen_balance_non_negative"),
        CheckConstraint("frozen_balance <= balance", name="check_frozen_balance_not_exceed_balance"),
    )


class BalanceTransaction(Base):
    __tablename__ = "balance_transactions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    amount = Column(Numeric(12,2), nullable=False)
    type = Column(String(20), nullable=False)  # 'topup', 'payment', 'income', 'refund'
    status = Column(String(20), nullable=False)  # 'pending', 'completed', 'failed'
    #: Hozir yangi to'lovlarda faqat 'rahmat'. Qolganlari tarixda qolgan
    #: qiymatlar (payment_providers.LEGACY_PAYMENT_METHODS) — o'chirilmaydi,
    #: chunki o'sha pul haqiqatan o'sha tizim orqali kelgan.
    payment_method = Column(String(50))
    description = Column(String(500))
    order_id = Column(Integer, ForeignKey("orders.id", ondelete="SET NULL"), nullable=True)  # Buyurtma bilan bog'lash

    #: To'lov haqida xabar beriladigan telefon (SMS bilan invoys havolasi).
    phone_number = Column(String(20), nullable=True)

    # ------------------------------------------------- Rahmat (Multicard)
    #
    # `rahmat_uuid` — shlyuzdagi tranzaksiya raqami. U invoys yaratilganda
    # DARHOL yoziladi: vebhukda faqat uuid bo'lishi mumkin, va usiz qaysi
    # to'lov ekanini aniqlashning yo'li yo'q.
    #
    # `rahmat_status` — shlyuzning O'Z holati (draft/progress/success/...).
    # Bizning `status` dan alohida turadi ataylab: ularni bitta ustunga
    # siqib bo'lmaydi, chunki 'hold' va 'billing' bizda ikkalasi ham
    # 'pending' ga tushadi, lekin adminkada farqi ko'rinishi kerak.
    rahmat_uuid = Column(String(64), nullable=True, index=True)
    rahmat_status = Column(String(20), nullable=True)
    rahmat_checkout_url = Column(String(500), nullable=True)
    rahmat_card_pan = Column(String(32), nullable=True)
    rahmat_ps = Column(String(20), nullable=True)
    rahmat_billing_id = Column(String(64), nullable=True)
    rahmat_receipt_url = Column(String(500), nullable=True)
    rahmat_payment_time = Column(String(32), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # DIQQAT: bu yerdagi ro'yxatlar bazadagi haqiqiy cheklov bilan bir xil
    # bo'lishi kerak. Schema Alembic bilan yuritiladi, shuning uchun
    # o'zgartirish migratsiyada bo'ladi — bu satrlar esa o'qiyotgan odamni
    # chalg'itmasligi uchun yangilanib turadi.
    __table_args__ = (
        CheckConstraint("amount > 0", name="check_transaction_amount"),
        CheckConstraint(
            "type IN ('topup','payment','income','refund','withdrawal','bonus')",
            name="check_transaction_type",
        ),
        CheckConstraint("status IN ('pending','completed','failed','canceled')", name="check_transaction_status"),
        CheckConstraint(
            "payment_method IN ('rahmat','click','payme','uzum','card','cash') "
            "OR payment_method IS NULL",
            name="check_transaction_payment_method",
        ),
    )



# Sovg'a hech qachon balansdan katta bo'lmasligi kerak.
#
# Pul yechiladigan joylar ettita (buyurtma, material, e'lon, payme, pul
# yechish...). Har biriga qo'lda tekshiruv qo'yilsa, ertami-kechmi bittasi
# unutilardi — shuning uchun qoida BITTA joyda: har qanday saqlashdan oldin
# bonus balansgacha qisqartiriladi.
#
# Ma'nosi: odam pul sarflaganda avval o'z puli, keyin sovg'a ishlatiladi.
@event.listens_for(Session, "before_flush")
def _clamp_bonus_balance(session, flush_context, instances):
    for obj in list(session.dirty) + list(session.new):
        if not isinstance(obj, Balance):
            continue
        balance = Decimal(str(obj.balance or 0))
        bonus = Decimal(str(obj.bonus_balance or 0))
        if bonus > balance:
            obj.bonus_balance = balance
        elif bonus < 0:
            obj.bonus_balance = Decimal("0")
