"""balances.bonus_balance — sovg'a pulini yechib bo'lmaydi

Sovg'a balansga tushadi va ilova ichida ISHLATILADI (buyurtma, material,
e'lon), lekin KARTAGA YECHILMAYDI. Aks holda har bir yangi SIM kartadan
50 000 chiqib ketardi: ro'yxatdan o't, pulni yech, tashlab ket.

Shuning uchun sovg'aning ishlatilmagan qismi alohida ustunda yuriydi.
Yechishga mavjud summa = balance - frozen_balance - bonus_balance.

Revision ID: c47f9a1e6b23
Revises: a91c4e8b2d76
Create Date: 2026-09-05
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'c47f9a1e6b23'
down_revision: Union[str, Sequence[str], None] = 'a91c4e8b2d76'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'balances',
        sa.Column('bonus_balance', sa.Numeric(12, 2), nullable=False,
                  server_default='0'),
    )
    # Allaqachon berilgan sovg'alarni hisobga olamiz: ular ham yechilmasin.
    op.execute("""
        UPDATE balances b
           SET bonus_balance = LEAST(
                   b.balance,
                   COALESCE((SELECT SUM(t.amount)
                               FROM balance_transactions t
                              WHERE t.user_id = b.user_id
                                AND t.type = 'bonus'
                                AND t.status = 'completed'), 0)
               )
    """)


def downgrade() -> None:
    op.drop_column('balances', 'bonus_balance')
