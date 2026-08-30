"""add click fields to transactions

Revision ID: add_click_fields
Revises: 
Create Date: 2025-11-13

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'add_click_fields'
down_revision = None  # Bu yerga oxirgi migration ID'sini qo'ying
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add click_trans_id, click_prepare_id and phone_number columns to balance_transactions table
    op.add_column('balance_transactions', sa.Column('click_trans_id', sa.Integer(), nullable=True))
    op.add_column('balance_transactions', sa.Column('click_prepare_id', sa.Integer(), nullable=True))
    op.add_column('balance_transactions', sa.Column('phone_number', sa.String(20), nullable=True))


def downgrade() -> None:
    # Remove click_trans_id, click_prepare_id and phone_number columns from balance_transactions table
    op.drop_column('balance_transactions', 'phone_number')
    op.drop_column('balance_transactions', 'click_prepare_id')
    op.drop_column('balance_transactions', 'click_trans_id')

