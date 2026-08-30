"""add_budget_reserves_table

Revision ID: a1b2c3d4e5f6
Revises: 020e1ec44a80
Create Date: 2025-11-17 21:25:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, Sequence[str], None] = '020e1ec44a80'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema - add budget_reserves table."""
    op.create_table(
        'budget_reserves',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('order_id', sa.Integer(), nullable=False),
        sa.Column('amount', sa.Numeric(precision=12, scale=2), nullable=False),
        sa.Column('description', sa.String(length=500), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.CheckConstraint('amount > 0', name='check_budget_reserve_amount'),
        sa.ForeignKeyConstraint(['order_id'], ['orders.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_budget_reserves_order_id'), 'budget_reserves', ['order_id'], unique=False)


def downgrade() -> None:
    """Downgrade schema - remove budget_reserves table."""
    op.drop_index(op.f('ix_budget_reserves_order_id'), table_name='budget_reserves')
    op.drop_table('budget_reserves')

