"""Состояния заказа из макета: продление по согласию, опоздание, кто
отменил, автоподтверждение, жалобы

- orders.extend_requested_hours — клиент попросил продлить (B3), ждёт
  согласия владельца; деньги двигаются только после согласия.
- orders.delay_minutes / delay_reason — владелец сообщил об опоздании (B2).
- orders.cancelled_by — 'client' | 'owner' | 'admin': клиенту, у которого
  владелец отменил заказ, показывается B1 «искать другую технику».
- orders.problem_reported_at — клиент нажал «Muammo bor» (B5); такой заказ
  НЕ подтверждается автоматически через 10 минут.
- order_problems — сами жалобы: причина, комментарий, до трёх фото.

Revision ID: e1c7a4d95b20
Revises: d8b3f6a2c917
Create Date: 2026-11-13
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'e1c7a4d95b20'
down_revision: Union[str, Sequence[str], None] = 'd8b3f6a2c917'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

REASONS = "('not_arrived','wrong_equipment','poor_quality','price_differs','other')"


def upgrade() -> None:
    op.add_column('orders', sa.Column('extend_requested_hours', sa.Integer(), nullable=True))
    op.add_column('orders', sa.Column('delay_minutes', sa.Integer(), nullable=True))
    op.add_column('orders', sa.Column('delay_reason', sa.Text(), nullable=True))
    op.add_column('orders', sa.Column('cancelled_by', sa.String(10), nullable=True))
    op.add_column('orders', sa.Column('problem_reported_at', sa.DateTime(timezone=True), nullable=True))
    op.create_check_constraint(
        'check_order_extend_hours', 'orders',
        'extend_requested_hours IS NULL OR extend_requested_hours BETWEEN 1 AND 12',
    )
    op.create_check_constraint(
        'check_order_delay', 'orders', 'delay_minutes IS NULL OR delay_minutes BETWEEN 1 AND 600',
    )
    op.create_check_constraint(
        'check_order_cancelled_by', 'orders',
        "cancelled_by IS NULL OR cancelled_by IN ('client','owner','admin')",
    )
    op.create_table(
        'order_problems',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('order_id', sa.Integer(), sa.ForeignKey('orders.id', ondelete='CASCADE'),
                  nullable=False, index=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('reason', sa.String(20), nullable=False),
        sa.Column('comment', sa.Text(), nullable=True),
        sa.Column('photos', sa.JSON(), nullable=True),
        sa.Column('status', sa.String(10), nullable=False, server_default='open'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint(f'reason IN {REASONS}', name='check_problem_reason'),
        sa.CheckConstraint("status IN ('open','resolved')", name='check_problem_status'),
    )


def downgrade() -> None:
    op.drop_table('order_problems')
    op.drop_constraint('check_order_cancelled_by', 'orders', type_='check')
    op.drop_constraint('check_order_delay', 'orders', type_='check')
    op.drop_constraint('check_order_extend_hours', 'orders', type_='check')
    for col in ('problem_reported_at', 'cancelled_by', 'delay_reason', 'delay_minutes',
                'extend_requested_hours'):
        op.drop_column('orders', col)
