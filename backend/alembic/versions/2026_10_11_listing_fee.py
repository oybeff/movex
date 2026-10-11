"""E'lon joylash uchun to'lov

- users.listing_fee_override — shu foydalanuvchi uchun alohida narx.
  NULL — umumiy narx (app_settings.listing_fee_amount), 0 — bepul.
- balance_transactions.type ga 'listing_fee' qo'shiladi: CHECK cheklovi
  bor, usiz INSERT yiqiladi.

Revision ID: a7d2e9c41b58
Revises: d4e7a1c93f52
Create Date: 2026-10-11
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'a7d2e9c41b58'
down_revision: Union[str, Sequence[str], None] = 'd4e7a1c93f52'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

ALLOWED_AFTER = (
    "type IN ('topup','payment','income','refund','withdrawal','bonus','listing_fee')"
)
ALLOWED_BEFORE = "type IN ('topup','payment','income','refund','withdrawal','bonus')"

# Adminkadan berilgan sovg'a payment_method='admin' bilan yoziladi —
# tarixda va takroriy bosishni tekshirishda ro'yxatdan o'tish sovg'asidan
# ajralib turishi uchun.
METHODS_AFTER = (
    "payment_method IN ('rahmat','click','payme','uzum','card','cash','admin') "
    "OR payment_method IS NULL"
)
METHODS_BEFORE = (
    "payment_method IN ('rahmat','click','payme','uzum','card','cash') "
    "OR payment_method IS NULL"
)


def upgrade() -> None:
    op.add_column(
        'users',
        sa.Column('listing_fee_override', sa.Numeric(12, 2), nullable=True),
    )
    op.create_check_constraint(
        'check_listing_fee_override',
        'users',
        'listing_fee_override IS NULL OR listing_fee_override >= 0',
    )
    op.drop_constraint('check_transaction_type', 'balance_transactions', type_='check')
    op.create_check_constraint('check_transaction_type', 'balance_transactions', ALLOWED_AFTER)
    op.drop_constraint('check_transaction_payment_method', 'balance_transactions', type_='check')
    op.create_check_constraint(
        'check_transaction_payment_method', 'balance_transactions', METHODS_AFTER
    )


def downgrade() -> None:
    op.execute("UPDATE balance_transactions SET payment_method = NULL WHERE payment_method = 'admin'")
    op.drop_constraint('check_transaction_payment_method', 'balance_transactions', type_='check')
    op.create_check_constraint(
        'check_transaction_payment_method', 'balance_transactions', METHODS_BEFORE
    )
    # To'lov yozuvlari qolsa eski cheklov o'rnatilmaydi
    op.execute("UPDATE balance_transactions SET type = 'payment' WHERE type = 'listing_fee'")
    op.drop_constraint('check_transaction_type', 'balance_transactions', type_='check')
    op.create_check_constraint('check_transaction_type', 'balance_transactions', ALLOWED_BEFORE)
    op.drop_constraint('check_listing_fee_override', 'users', type_='check')
    op.drop_column('users', 'listing_fee_override')
