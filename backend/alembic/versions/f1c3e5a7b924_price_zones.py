"""Регионы цен: price_zones + zone_tariffs (Шерзодбек, 24.11.2026).

Revision ID: f1c3e5a7b924
Revises: e8b2c4d6f913
"""
from alembic import op
import sqlalchemy as sa

revision = 'f1c3e5a7b924'
down_revision = 'e8b2c4d6f913'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'price_zones',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('name', sa.String(100), nullable=False),
        sa.Column('polygon', sa.JSON(), nullable=False),
        sa.Column('surcharge_percent', sa.Numeric(5, 2), nullable=False, server_default='0'),
        sa.Column('is_enabled', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('sort_order', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint('surcharge_percent BETWEEN -50 AND 200', name='check_zone_surcharge'),
    )
    op.create_table(
        'zone_tariffs',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('zone_id', sa.Integer(), sa.ForeignKey('price_zones.id', ondelete='CASCADE'), nullable=False),
        sa.Column('equipment_type', sa.String(50), nullable=False),
        sa.Column('tier', sa.String(10), nullable=False),
        sa.Column('price', sa.Numeric(12, 2), nullable=False),
        sa.UniqueConstraint('zone_id', 'equipment_type', 'tier', name='uq_zone_tariff'),
        sa.CheckConstraint("tier IN ('econom','fast','day')", name='check_zone_tariff_tier'),
        sa.CheckConstraint('price > 0', name='check_zone_tariff_price'),
    )
    op.create_index('ix_zone_tariffs_zone_id', 'zone_tariffs', ['zone_id'])
    # Регион в заявке: какая зона посчитала цену (для админки и разборов).
    op.add_column('equipment_requests', sa.Column('price_zone_id', sa.Integer(), nullable=True))


def downgrade():
    op.drop_column('equipment_requests', 'price_zone_id')
    op.drop_index('ix_zone_tariffs_zone_id', table_name='zone_tariffs')
    op.drop_table('zone_tariffs')
    op.drop_table('price_zones')
