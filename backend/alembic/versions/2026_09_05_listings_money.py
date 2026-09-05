"""E'lonlarda pul: kelishilgan narx, ulush va budjet yozuvi

E'lonlar ilgari pulga umuman tegmasdi. Endi ular buyurtmalar bilan bir xil
ishlaydi: tasdiqlashda muallifning balansida summa MUZLAYDI, yakunlashda
ijrochiga o'tadi, platforma ulushi esa budjetga yoziladi.

Ikki o'zgarish kerak:

1. listings.agreed_price va listings.commission — kelishilgan summa va ulush
   TASDIQLASH PAYTIDA yoziladi. Ko'rsatishda hisoblab bo'lmaydi: adminkada
   stavka o'zgarsa, eski e'lonlar tarixi qayta yozilib ketardi.

2. budget_reserves endi e'longa ham tegishli bo'lishi mumkin, shuning uchun
   order_id bo'sh bo'lishga ruxsat oladi va listing_id qo'shiladi. Ikkalasi
   birdan yoki ikkalasi ham bo'sh bo'lishi mumkin emas — CHECK qo'yiladi.

Revision ID: a91c4e8b2d76
Revises: f3b8c21d47ae
Create Date: 2026-09-05
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'a91c4e8b2d76'
down_revision: Union[str, Sequence[str], None] = 'f3b8c21d47ae'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('listings', sa.Column('agreed_price', sa.Numeric(12, 2), nullable=True))
    op.add_column('listings', sa.Column('commission', sa.Numeric(12, 2), nullable=True))

    op.alter_column('budget_reserves', 'order_id', existing_type=sa.Integer(), nullable=True)
    op.add_column('budget_reserves', sa.Column('listing_id', sa.Integer(), nullable=True))
    op.create_foreign_key(
        'fk_budget_reserves_listing', 'budget_reserves', 'listings',
        ['listing_id'], ['id'], ondelete='CASCADE',
    )
    op.create_index('ix_budget_reserves_listing_id', 'budget_reserves', ['listing_id'])
    op.create_check_constraint(
        'check_budget_reserve_source', 'budget_reserves',
        '(order_id IS NOT NULL AND listing_id IS NULL) '
        'OR (order_id IS NULL AND listing_id IS NOT NULL)',
    )


def downgrade() -> None:
    # E'lonlardan yig'ilgan ulush yozuvlari order_id siz qoladi, ya'ni eski
    # NOT NULL ni tiklab bo'lmaydi — avval ularni o'chiramiz.
    op.execute("DELETE FROM budget_reserves WHERE listing_id IS NOT NULL")
    op.drop_constraint('check_budget_reserve_source', 'budget_reserves', type_='check')
    op.drop_index('ix_budget_reserves_listing_id', table_name='budget_reserves')
    op.drop_constraint('fk_budget_reserves_listing', 'budget_reserves', type_='foreignkey')
    op.drop_column('budget_reserves', 'listing_id')
    op.alter_column('budget_reserves', 'order_id', existing_type=sa.Integer(), nullable=False)

    op.drop_column('listings', 'commission')
    op.drop_column('listings', 'agreed_price')
