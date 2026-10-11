"""Tez buyurtma: zayavka "kim birinchi oldi" rejimida

- equipment_requests.mode — 'tender' (takliflar, avvalgidek) yoki 'quick'
  (mijoz narxni o'zi qo'yadi, birinchi bo'lib olgan ega oladi);
- equipment_requests.start_time — boshlanish vaqti (tez buyurtmada majburiy);
- equipment_requests.frozen_amount — tez buyurtmada mijoz balansida
  muzlatilgan summa. Olinganda buyurtmaga o'tadi (0 bo'ladi), bekor yoki
  muddat tugaganda qaytariladi;
- orders.start_time — buyurtmaga ham o'tadi;
- quick_request_declines — ega "Rad etish"ni bosgan zayavkalar, unga
  qayta ko'rsatilmasin.

Revision ID: b3f8e1d27c90
Revises: a7d2e9c41b58
Create Date: 2026-10-11
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'b3f8e1d27c90'
down_revision: Union[str, Sequence[str], None] = 'a7d2e9c41b58'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


NOTIF_BEFORE = "type IN ('order_created','order_confirmed','order_rejected','order_cancelled','order_completed','balance_topup','payout_paid','payout_rejected','system','request_created','request_offer','request_offer_accepted','request_offer_rejected','request_cancelled','listing_taken','listing_confirmed','listing_cancelled','listing_done')"
NOTIF_AFTER = "type IN ('order_created','order_confirmed','order_rejected','order_cancelled','order_completed','balance_topup','payout_paid','payout_rejected','system','request_created','request_offer','request_offer_accepted','request_offer_rejected','request_cancelled','listing_taken','listing_confirmed','listing_cancelled','listing_done','quick_request')"


def upgrade() -> None:
    op.drop_constraint('check_notification_type', 'notifications', type_='check')
    op.create_check_constraint('check_notification_type', 'notifications', NOTIF_AFTER)
    op.add_column('equipment_requests', sa.Column(
        'mode', sa.String(10), nullable=False, server_default='tender'))
    op.add_column('equipment_requests', sa.Column('start_time', sa.Time(), nullable=True))
    op.add_column('equipment_requests', sa.Column(
        'frozen_amount', sa.Numeric(12, 2), nullable=False, server_default='0'))
    op.create_check_constraint(
        'check_request_mode', 'equipment_requests', "mode IN ('tender','quick')")
    op.create_check_constraint(
        'check_request_frozen_amount', 'equipment_requests', 'frozen_amount >= 0')
    # Tez buyurtmada narx bo'lmasa, muzlatadigan narsa yo'q
    op.create_check_constraint(
        'check_quick_request_budget', 'equipment_requests',
        "mode <> 'quick' OR (budget IS NOT NULL AND start_time IS NOT NULL)")

    op.add_column('orders', sa.Column('start_time', sa.Time(), nullable=True))

    op.create_table(
        'quick_request_declines',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('request_id', sa.Integer(),
                  sa.ForeignKey('equipment_requests.id', ondelete='CASCADE'),
                  nullable=False, index=True),
        sa.Column('owner_id', sa.Integer(),
                  sa.ForeignKey('users.id', ondelete='CASCADE'),
                  nullable=False, index=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint('request_id', 'owner_id', name='uq_quick_decline'),
    )


def downgrade() -> None:
    op.execute("DELETE FROM notifications WHERE type = 'quick_request'")
    op.drop_constraint('check_notification_type', 'notifications', type_='check')
    op.create_check_constraint('check_notification_type', 'notifications', NOTIF_BEFORE)
    op.drop_table('quick_request_declines')
    op.drop_column('orders', 'start_time')
    op.drop_constraint('check_quick_request_budget', 'equipment_requests', type_='check')
    op.drop_constraint('check_request_frozen_amount', 'equipment_requests', type_='check')
    op.drop_constraint('check_request_mode', 'equipment_requests', type_='check')
    op.drop_column('equipment_requests', 'frozen_amount')
    op.drop_column('equipment_requests', 'start_time')
    op.drop_column('equipment_requests', 'mode')
