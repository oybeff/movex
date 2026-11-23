"""«Yuk tashish» — перевозка груза клиента из А в Б «как такси» (24.11.2026).

- delivery_vehicles: режим цены (km | hour), цена часа, минимум часов,
  есть ли выбор кузова (tentli / tentsiz);
- delivery_driver_profiles.body_type: tent | open | NULL (не указан);
- freight_orders — сам заказ; деньги как у доставки стройматериалов:
  Go wallet (заморожено) или наличные водителю, комиссия — с водителя;
- уведомления freight_driver_found / freight_loaded / freight_arrived;
- группа transport в каталоге переименована в «Yuk tashish».

Revision ID: d2b7e9a4c158
Revises: c4f8a2d6e913
"""
import sqlalchemy as sa
from alembic import op

revision = 'd2b7e9a4c158'
down_revision = 'c4f8a2d6e913'
branch_labels = None
depends_on = None

NOTIFICATION_TYPES = (
    "order_created", "order_confirmed", "order_rejected", "order_cancelled",
    "order_completed", "balance_topup", "payout_paid", "payout_rejected", "system",
    "request_created", "request_offer", "request_offer_accepted", "request_offer_rejected",
    "request_cancelled", "listing_taken", "listing_confirmed", "listing_cancelled",
    "listing_done", "quick_request", "order_departed", "order_arrived", "order_started",
    "order_finished", "order_delayed", "order_extend_requested", "order_extend_approved",
    "order_extend_declined", "listing_offer", "material_order", "material_confirmed",
    "material_cancelled", "material_delivered", "material_moderated", "driver_approved",
    "driver_document_rejected", "material_driver_found", "material_picked_up",
    "material_driver_arrived",
)
ADDED = ("freight_driver_found", "freight_loaded", "freight_arrived", "freight_cancelled")


def _check(types):
    return "type IN (" + ", ".join(f"'{t}'" for t in types) + ")"


def upgrade():
    op.add_column('delivery_vehicles', sa.Column('price_mode', sa.String(10), nullable=False, server_default='km'))
    op.add_column('delivery_vehicles', sa.Column('price_per_hour', sa.Numeric(12, 2), nullable=True))
    op.add_column('delivery_vehicles', sa.Column('min_hours', sa.Integer(), nullable=False, server_default='1'))
    op.add_column('delivery_vehicles', sa.Column('has_body_choice', sa.Boolean(), nullable=False,
                                                 server_default=sa.text('false')))
    op.create_check_constraint('check_delivery_vehicle_price_mode', 'delivery_vehicles',
                               "price_mode IN ('km','hour')")
    op.create_check_constraint('check_delivery_vehicle_min_hours', 'delivery_vehicles', 'min_hours >= 1')
    # Tentli / tentsiz — у малых и средних бортовых (просьба Шерзодбека).
    op.execute("UPDATE delivery_vehicles SET has_body_choice = true "
               "WHERE code IN ('labo','porter','bongo','gazel','isuzu_3','mighty','isuzu')")

    op.add_column('delivery_driver_profiles', sa.Column('body_type', sa.String(10), nullable=True))
    op.create_check_constraint('check_ddp_body', 'delivery_driver_profiles',
                               "body_type IS NULL OR body_type IN ('tent','open')")

    op.create_table(
        'freight_orders',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('client_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False,
                  index=True),
        sa.Column('driver_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True,
                  index=True),
        sa.Column('vehicle_code', sa.String(30), nullable=False),
        sa.Column('body_type', sa.String(10), nullable=True),
        sa.Column('cargo_tonnes', sa.Numeric(8, 2), nullable=True),
        sa.Column('cargo_note', sa.Text(), nullable=True),
        sa.Column('from_address', sa.Text(), nullable=True),
        sa.Column('from_latitude', sa.Numeric(10, 7), nullable=False),
        sa.Column('from_longitude', sa.Numeric(10, 7), nullable=False),
        sa.Column('to_address', sa.Text(), nullable=True),
        sa.Column('to_latitude', sa.Numeric(10, 7), nullable=False),
        sa.Column('to_longitude', sa.Numeric(10, 7), nullable=False),
        sa.Column('distance_km', sa.Numeric(10, 2), nullable=False),
        sa.Column('price_mode', sa.String(10), nullable=False),
        sa.Column('hours', sa.Integer(), nullable=True),
        sa.Column('price', sa.Numeric(12, 2), nullable=False),
        sa.Column('payment_method', sa.String(10), nullable=False, server_default='balance'),
        sa.Column('frozen_amount', sa.Numeric(12, 2), nullable=False, server_default='0'),
        sa.Column('driver_fee', sa.Numeric(12, 2), nullable=True),
        sa.Column('driver_commission', sa.Numeric(12, 2), nullable=False, server_default='0'),
        sa.Column('driver_frozen', sa.Numeric(12, 2), nullable=False, server_default='0'),
        sa.Column('status', sa.String(20), nullable=False, server_default='searching', index=True),
        sa.Column('accepted_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('loaded_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('arrived_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('finished_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('cancelled_by', sa.String(10), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), index=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint('price > 0', name='check_freight_price'),
        sa.CheckConstraint("payment_method IN ('balance','cash')", name='check_freight_payment'),
        sa.CheckConstraint("status IN ('searching','accepted','loaded','arrived','done','cancelled')",
                           name='check_freight_status'),
        sa.CheckConstraint("body_type IS NULL OR body_type IN ('tent','open')", name='check_freight_body'),
        sa.CheckConstraint("price_mode IN ('km','hour')", name='check_freight_price_mode'),
    )

    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications",
                               _check(NOTIFICATION_TYPES + ADDED))


def downgrade():
    op.execute("DELETE FROM notifications WHERE type IN "
               "('freight_driver_found','freight_loaded','freight_arrived','freight_cancelled')")
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications", _check(NOTIFICATION_TYPES))
    op.drop_table('freight_orders')
    op.drop_constraint('check_ddp_body', 'delivery_driver_profiles', type_='check')
    op.drop_column('delivery_driver_profiles', 'body_type')
    op.drop_constraint('check_delivery_vehicle_min_hours', 'delivery_vehicles', type_='check')
    op.drop_constraint('check_delivery_vehicle_price_mode', 'delivery_vehicles', type_='check')
    for c in ('has_body_choice', 'min_hours', 'price_per_hour', 'price_mode'):
        op.drop_column('delivery_vehicles', c)
