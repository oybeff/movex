"""Rahmat (Multicard) — yagona to'lov tizimi, Click va Payme olib tashlandi

Nima o'zgaradi:

  1. balance_transactions ga Rahmat ustunlari qo'shiladi (uuid, holat,
     chekaut havolasi, karta, chek). `rahmat_uuid` indeksli: callback va
     vebhuk tranzaksiyani aynan shu bo'yicha topadi.

  2. Click va Payme ustunlari O'CHIRILADI. Ular xavfsiz o'chiriladi,
     chunki bu ikki integratsiya hech qachon jangovar kalitlar bilan
     ishlamagan (docs/backend/PAYMENTS.md — "boevyx merchant-klyuchey net"),
     ya'ni ularda haqiqiy to'lov yo'q. Kod ketgach ustunlar faqat
     chalg'itardi.

  3. payment_method cheklovi 'rahmat' ni qabul qiladi. Eski qiymatlar
     ('click', 'payme', 'uzum', 'card', 'cash') ro'yxatda QOLADI: o'sha
     pul haqiqatan o'sha tizim orqali kelgan, uni qayta yozish tarixni
     buzish bo'lardi. Yangi to'lov esa ular bilan o'tmaydi — buni
     SELF_SERVICE_PAYMENT_METHODS hal qiladi, cheklov emas.

  4. payments.payment_method cheklovi 'Rahmat' ni qabul qiladi.

  5. payout_requests ga o'tkazma ustunlari qo'shiladi: pul kartaga endi
     shlyuz orqali ketadi, va uuid saqlanmasa, timeoutdan keyin holatni
     so'rash imkoni bo'lmaydi — ariza bo'yicha pul ikki marta ketardi.

  6. users.payme_receiver_id o'chiriladi. U faqat Payme split uchun
     kerak edi va endi hech qayerda o'qilmaydi.

Revision ID: b6d1f38a52c9
Revises: c47f9a1e6b23
Create Date: 2026-09-29
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "b6d1f38a52c9"
down_revision: Union[str, Sequence[str], None] = "c47f9a1e6b23"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


TX_METHOD_CONSTRAINT = "check_transaction_payment_method"
TX_METHODS_WITH_RAHMAT = (
    "payment_method IN ('rahmat','click','payme','uzum','card','cash') "
    "OR payment_method IS NULL"
)
TX_METHODS_BEFORE = (
    "payment_method IN ('click','payme','uzum','card','cash') "
    "OR payment_method IS NULL"
)

PAYMENT_METHOD_CONSTRAINT = "check_payment_method"
PAYMENT_METHODS_WITH_RAHMAT = (
    "payment_method IN ('Rahmat','Payme','Click','Card') OR payment_method IS NULL"
)
PAYMENT_METHODS_BEFORE = (
    "payment_method IN ('Payme','Click','Card') OR payment_method IS NULL"
)

#: Olib tashlanadigan ustunlar: (jadval, ustun, qaytarish uchun turi)
DROPPED = [
    ("balance_transactions", "click_trans_id", sa.Integer()),
    ("balance_transactions", "click_prepare_id", sa.Integer()),
    ("balance_transactions", "payme_transaction_id", sa.String(length=50)),
    ("balance_transactions", "payme_state", sa.Integer()),
    ("balance_transactions", "payme_create_time", sa.BigInteger()),
    ("balance_transactions", "payme_perform_time", sa.BigInteger()),
    ("balance_transactions", "payme_cancel_time", sa.BigInteger()),
    ("balance_transactions", "payme_reason", sa.Integer()),
    ("users", "payme_receiver_id", sa.String(length=50)),
]

RAHMAT_TX_COLUMNS = [
    ("rahmat_uuid", sa.String(length=64)),
    ("rahmat_status", sa.String(length=20)),
    ("rahmat_checkout_url", sa.String(length=500)),
    ("rahmat_card_pan", sa.String(length=32)),
    ("rahmat_ps", sa.String(length=20)),
    ("rahmat_billing_id", sa.String(length=64)),
    ("rahmat_receipt_url", sa.String(length=500)),
    ("rahmat_payment_time", sa.String(length=32)),
]

RAHMAT_PAYOUT_COLUMNS = [
    ("rahmat_uuid", sa.String(length=64)),
    ("rahmat_status", sa.String(length=20)),
    ("rahmat_receipt_url", sa.String(length=500)),
    ("rahmat_error", sa.Text()),
]


def _has_column(table: str, column: str) -> bool:
    """
    Ustun bor-yo'qligini tekshirish.

    Kerak, chunki bu loyihada schema bir necha yo'l bilan yasalgan
    (ilgari `Base.metadata.create_all` ham ishlatilgan) va ba'zi
    ustunlar bazada allaqachon bo'lishi mumkin. IF NOT EXISTS
    ko'rinishi `op.add_column` da yo'q.
    """
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if table not in inspector.get_table_names():
        return False
    return column in {col["name"] for col in inspector.get_columns(table)}


def upgrade() -> None:
    for name, type_ in RAHMAT_TX_COLUMNS:
        if not _has_column("balance_transactions", name):
            op.add_column("balance_transactions", sa.Column(name, type_, nullable=True))

    if not _has_column("payout_requests", "rahmat_uuid"):
        for name, type_ in RAHMAT_PAYOUT_COLUMNS:
            op.add_column("payout_requests", sa.Column(name, type_, nullable=True))

    op.create_index(
        "ix_balance_transactions_rahmat_uuid",
        "balance_transactions",
        ["rahmat_uuid"],
        unique=False,
    )
    op.create_index(
        "ix_payout_requests_rahmat_uuid",
        "payout_requests",
        ["rahmat_uuid"],
        unique=False,
    )

    op.drop_constraint(TX_METHOD_CONSTRAINT, "balance_transactions", type_="check")
    op.create_check_constraint(
        TX_METHOD_CONSTRAINT, "balance_transactions", TX_METHODS_WITH_RAHMAT
    )

    op.drop_constraint(PAYMENT_METHOD_CONSTRAINT, "payments", type_="check")
    op.create_check_constraint(
        PAYMENT_METHOD_CONSTRAINT, "payments", PAYMENT_METHODS_WITH_RAHMAT
    )

    for table, column, _type in DROPPED:
        if _has_column(table, column):
            op.drop_column(table, column)


def downgrade() -> None:
    for table, column, type_ in DROPPED:
        if not _has_column(table, column):
            op.add_column(table, sa.Column(column, type_, nullable=True))

    op.drop_constraint(PAYMENT_METHOD_CONSTRAINT, "payments", type_="check")
    op.create_check_constraint(
        PAYMENT_METHOD_CONSTRAINT, "payments", PAYMENT_METHODS_BEFORE
    )

    # DIQQAT: orqaga qaytishdan oldin 'rahmat' bo'lgan satrlarni o'zgartirish
    # kerak, aks holda cheklov qo'yilmaydi. Ularni jimgina qayta yozmaymiz —
    # pul qayerdan kelganini yolg'on ko'rsatish mumkin emas.
    op.drop_constraint(TX_METHOD_CONSTRAINT, "balance_transactions", type_="check")
    op.create_check_constraint(
        TX_METHOD_CONSTRAINT, "balance_transactions", TX_METHODS_BEFORE
    )

    op.drop_index("ix_payout_requests_rahmat_uuid", table_name="payout_requests")
    op.drop_index("ix_balance_transactions_rahmat_uuid", table_name="balance_transactions")

    for name, _type in RAHMAT_PAYOUT_COLUMNS:
        if _has_column("payout_requests", name):
            op.drop_column("payout_requests", name)

    for name, _type in RAHMAT_TX_COLUMNS:
        if _has_column("balance_transactions", name):
            op.drop_column("balance_transactions", name)
