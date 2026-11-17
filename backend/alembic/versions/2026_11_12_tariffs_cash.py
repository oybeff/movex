"""Тарифный заказ «как такси» и оплата наличными

- tariffs — цена часа на пару «тип техники × тариф» (econom/fast/day),
  задаёт админ в tariffs.php;
- equipment_attachments — навесное оборудование с надбавкой за час;
- equipment_requests: tariff, hours, attachment_id, attachment_price,
  payment_method, origin_* («Qayerdan»);
- orders: payment_method, owner_frozen (заморозка комиссии владельца для
  наличного заказа), tariff, hours.

Тарифы НЕ засеваются: цены — решение владельца продукта, а не кода.
Пока админ их не задал, тарифный заказ для типа просто недоступен.

Revision ID: c5a9e2f71d34
Revises: b3f8e1d27c90
Create Date: 2026-11-12
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'c5a9e2f71d34'
down_revision: Union[str, Sequence[str], None] = 'b3f8e1d27c90'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'tariffs',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('equipment_type', sa.String(50), nullable=False, index=True),
        sa.Column('tier', sa.String(10), nullable=False),
        sa.Column('price_per_hour', sa.Numeric(12, 2), nullable=False),
        sa.Column('min_hours', sa.Integer(), nullable=False, server_default='4'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint('equipment_type', 'tier', name='uq_tariff_type_tier'),
        sa.CheckConstraint("tier IN ('econom','fast','day')", name='check_tariff_tier'),
        sa.CheckConstraint('price_per_hour > 0', name='check_tariff_price'),
        sa.CheckConstraint('min_hours BETWEEN 1 AND 24', name='check_tariff_min_hours'),
    )
    op.create_table(
        'equipment_attachments',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('equipment_type', sa.String(50), nullable=False, index=True),
        sa.Column('name_uz', sa.String(100), nullable=False),
        sa.Column('name_ru', sa.String(100), nullable=False),
        sa.Column('price_per_hour', sa.Numeric(12, 2), nullable=False, server_default='0'),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('sort_order', sa.Integer(), nullable=False, server_default='0'),
        sa.CheckConstraint('price_per_hour >= 0', name='check_attachment_price'),
    )

    op.add_column('equipment_requests', sa.Column('tariff', sa.String(10), nullable=True))
    op.add_column('equipment_requests', sa.Column('hours', sa.Integer(), nullable=True))
    op.add_column('equipment_requests', sa.Column(
        'attachment_id', sa.Integer(),
        sa.ForeignKey('equipment_attachments.id', ondelete='SET NULL'), nullable=True,
    ))
    op.add_column('equipment_requests', sa.Column('attachment_price', sa.Numeric(12, 2), nullable=True))
    op.add_column('equipment_requests', sa.Column(
        'payment_method', sa.String(10), nullable=False, server_default='balance',
    ))
    op.add_column('equipment_requests', sa.Column('origin_latitude', sa.String(50), nullable=True))
    op.add_column('equipment_requests', sa.Column('origin_longitude', sa.String(50), nullable=True))
    op.add_column('equipment_requests', sa.Column('origin_address', sa.Text(), nullable=True))
    op.create_check_constraint(
        'check_request_payment_method', 'equipment_requests',
        "payment_method IN ('balance','cash')",
    )
    op.create_check_constraint(
        'check_request_tariff', 'equipment_requests',
        "tariff IS NULL OR (tariff IN ('econom','fast','day') AND hours > 0 AND mode = 'quick')",
    )
    op.create_check_constraint(
        'check_request_cash_only_tariff', 'equipment_requests',
        "payment_method = 'balance' OR tariff IS NOT NULL",
    )

    op.add_column('orders', sa.Column(
        'payment_method', sa.String(10), nullable=False, server_default='balance',
    ))
    op.add_column('orders', sa.Column(
        'owner_frozen', sa.Numeric(10, 2), nullable=False, server_default='0',
    ))
    op.add_column('orders', sa.Column('tariff', sa.String(10), nullable=True))
    op.add_column('orders', sa.Column('hours', sa.Integer(), nullable=True))
    op.create_check_constraint(
        'check_order_payment_method', 'orders', "payment_method IN ('balance','cash')",
    )
    op.create_check_constraint('check_order_owner_frozen', 'orders', 'owner_frozen >= 0')
    op.create_check_constraint(
        'check_order_cash_no_escrow', 'orders',
        "payment_method = 'balance' OR frozen_amount = 0",
    )


def downgrade() -> None:
    op.drop_constraint('check_order_cash_no_escrow', 'orders', type_='check')
    op.drop_constraint('check_order_owner_frozen', 'orders', type_='check')
    op.drop_constraint('check_order_payment_method', 'orders', type_='check')
    for col in ('hours', 'tariff', 'owner_frozen', 'payment_method'):
        op.drop_column('orders', col)

    op.drop_constraint('check_request_cash_only_tariff', 'equipment_requests', type_='check')
    op.drop_constraint('check_request_tariff', 'equipment_requests', type_='check')
    op.drop_constraint('check_request_payment_method', 'equipment_requests', type_='check')
    for col in ('origin_address', 'origin_longitude', 'origin_latitude', 'payment_method',
                'attachment_price', 'attachment_id', 'hours', 'tariff'):
        op.drop_column('equipment_requests', col)

    op.drop_table('equipment_attachments')
    op.drop_table('tariffs')
