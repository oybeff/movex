"""balance_transactions: 'bonus' turini qo'shish

Ro'yxatdan o'tgan texnika egasiga beriladigan sovg'a alohida tur bilan
yoziladi. Alohida tur ataylab: adminkada va tarixda sovg'a to'ldirishdan
ajralib turishi kerak, aks holda pul qayerdan kelgani ko'rinmaydi.

Ustunda CHECK cheklovi bor, shuning uchun yangi qiymat migratsiyasiz
yozilmaydi — INSERT CheckViolation bilan yiqiladi.

Revision ID: f3b8c21d47ae
Revises: e2c7d4a91f35
Create Date: 2026-09-05
"""
from typing import Sequence, Union

from alembic import op

revision: str = 'f3b8c21d47ae'
down_revision: Union[str, Sequence[str], None] = 'e2c7d4a91f35'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

ALLOWED_WITH_BONUS = "type IN ('topup','payment','income','refund','withdrawal','bonus')"
ALLOWED_BEFORE = "type IN ('topup','payment','income','refund','withdrawal')"


def upgrade() -> None:
    op.drop_constraint('check_transaction_type', 'balance_transactions', type_='check')
    op.create_check_constraint(
        'check_transaction_type', 'balance_transactions', ALLOWED_WITH_BONUS
    )


def downgrade() -> None:
    # Sovg'a yozuvlari qolsa, eski cheklov o'rnatilmaydi — avval ularni
    # to'ldirishga aylantiramiz, aks holda downgrade yiqiladi.
    op.execute("UPDATE balance_transactions SET type = 'topup' WHERE type = 'bonus'")
    op.drop_constraint('check_transaction_type', 'balance_transactions', type_='check')
    op.create_check_constraint(
        'check_transaction_type', 'balance_transactions', ALLOWED_BEFORE
    )
