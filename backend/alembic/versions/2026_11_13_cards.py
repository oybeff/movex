"""Привязанные карты клиента (K1–K6) и оплата заказа картой через холд.

- user_cards — токен карты от Multicard, маска номера, платёжная система.
  Сам номер карты к нам НЕ попадает: его вводят на странице Multicard.
- card_bind_sessions — открытые сессии привязки (session_id → user_id),
  чтобы колбэк привязал карту именно тому, кто её добавлял.
- card_payments — холд на карте под заказ: draft → active → charged,
  или cancelled. uuid — платёж в Multicard.
- payment_method 'card' в заявках и заказах; статус заявки
  'awaiting_payment' — холд ещё не подтверждён, владельцы её не видят.

Revision ID: b4c8e2f17a39
Revises: a7d3e9c41b56
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'b4c8e2f17a39'
down_revision: Union[str, Sequence[str], None] = 'a7d3e9c41b56'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'user_cards',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('token', sa.String(255), nullable=False, unique=True),
        sa.Column('pan', sa.String(20), nullable=False),
        sa.Column('ps', sa.String(20), nullable=True),
        sa.Column('holder_name', sa.String(100), nullable=True),
        sa.Column('is_default', sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('status', sa.String(10), nullable=False, server_default='active'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint("status IN ('active','deleted')", name='check_card_status'),
    )
    op.create_table(
        'card_bind_sessions',
        sa.Column('session_id', sa.String(64), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('card_id', sa.Integer(), sa.ForeignKey('user_cards.id', ondelete='SET NULL'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_table(
        'card_payments',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('card_id', sa.Integer(), sa.ForeignKey('user_cards.id', ondelete='SET NULL'), nullable=True),
        sa.Column('request_id', sa.Integer(), sa.ForeignKey('equipment_requests.id', ondelete='SET NULL'), nullable=True, index=True),
        sa.Column('order_id', sa.Integer(), sa.ForeignKey('orders.id', ondelete='SET NULL'), nullable=True, index=True),
        sa.Column('uuid', sa.String(64), nullable=True, unique=True),
        sa.Column('amount', sa.Numeric(12, 2), nullable=False),
        sa.Column('status', sa.String(12), nullable=False, server_default='draft'),
        sa.Column('error', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint(
            "status IN ('draft','active','charged','cancelled','failed','unknown')",
            name='check_card_payment_status',
        ),
        sa.CheckConstraint('amount > 0', name='check_card_payment_amount'),
    )
    op.add_column('equipment_requests', sa.Column(
        'card_id', sa.Integer(), sa.ForeignKey('user_cards.id', ondelete='SET NULL'), nullable=True))
    op.drop_constraint('check_request_status', 'equipment_requests', type_='check')
    op.create_check_constraint(
        'check_request_status', 'equipment_requests',
        "status IN ('awaiting_payment','open','assigned','cancelled','expired')",
    )
    op.drop_constraint('check_request_payment_method', 'equipment_requests', type_='check')
    op.create_check_constraint(
        'check_request_payment_method', 'equipment_requests', "payment_method IN ('balance','cash','card')",
    )
    op.drop_constraint('check_order_payment_method', 'orders', type_='check')
    op.create_check_constraint(
        'check_order_payment_method', 'orders', "payment_method IN ('balance','cash','card')",
    )


def downgrade() -> None:
    op.drop_constraint('check_order_payment_method', 'orders', type_='check')
    op.create_check_constraint('check_order_payment_method', 'orders', "payment_method IN ('balance','cash')")
    op.drop_constraint('check_request_payment_method', 'equipment_requests', type_='check')
    op.create_check_constraint('check_request_payment_method', 'equipment_requests', "payment_method IN ('balance','cash')")
    op.drop_constraint('check_request_status', 'equipment_requests', type_='check')
    op.create_check_constraint('check_request_status', 'equipment_requests', "status IN ('open','assigned','cancelled','expired')")
    op.drop_column('equipment_requests', 'card_id')
    op.drop_table('card_payments')
    op.drop_table('card_bind_sessions')
    op.drop_table('user_cards')
