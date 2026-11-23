"""Водитель: компенсация за отмену/неявку (E1, E7) и оценка клиента (D6).

Revision ID: d7e2a5c84f16
Revises: c3d5e8f1a274
"""
import sqlalchemy as sa
from alembic import op

revision = 'd7e2a5c84f16'
down_revision = 'c3d5e8f1a274'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('orders', sa.Column('compensation', sa.Numeric(12, 2), nullable=False, server_default='0'))
    op.create_check_constraint('check_order_compensation', 'orders', 'compensation >= 0')
    op.create_table(
        'client_ratings',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('order_id', sa.Integer(), sa.ForeignKey('orders.id', ondelete='CASCADE'), nullable=False, unique=True),
        sa.Column('owner_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('client_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('rating', sa.Integer(), nullable=False),
        sa.Column('tags', sa.String(200), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint('rating BETWEEN 1 AND 5', name='check_client_rating_value'),
    )
    op.create_index('ix_client_ratings_owner_id', 'client_ratings', ['owner_id'])
    op.create_index('ix_client_ratings_client_id', 'client_ratings', ['client_id'])


def downgrade():
    op.drop_index('ix_client_ratings_client_id', 'client_ratings')
    op.drop_index('ix_client_ratings_owner_id', 'client_ratings')
    op.drop_table('client_ratings')
    op.drop_constraint('check_order_compensation', 'orders', type_='check')
    op.drop_column('orders', 'compensation')
