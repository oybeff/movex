"""Доставка стройматериалов водителями (23.11.2026).

- material_categories — 10 категорий из ТЗ Шерзодбека; водитель отмечает,
  что возит, и минимум по каждой («Labo — penoblok от 50 dona»);
- delivery_driver_profiles — машина водителя (код из delivery_vehicles),
  номер, своя цена за км/подачу, онлайн и последняя точка GPS;
- delivery_driver_categories — категории водителя с минимумом;
- material_orders: кто везёт (dispatch), статус доставки, водитель, его
  цена и комиссия, способ оплаты доставки (Go wallet или наличные);
- уведомления material_driver_found / material_picked_up /
  material_driver_arrived;
- delivery_search_radius_km — радиус поиска водителя от склада (30 км).

Revision ID: c4f8a2d6e913
Revises: a9c3e7f2b5d1
"""
import sqlalchemy as sa
from alembic import op

revision = 'c4f8a2d6e913'
down_revision = 'a9c3e7f2b5d1'
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
    "driver_document_rejected",
)
ADDED = ("material_driver_found", "material_picked_up", "material_driver_arrived")


def _check(types):
    return "type IN (" + ", ".join(f"'{t}'" for t in types) + ")"


# code, uz, ru, unit (piece|bag|tonne|m3), sort
CATEGORIES = [
    ("sand", "Qum", "Песок", "m3", 10),
    ("gravel", "Shag‘al va sheben", "Гравий и щебень", "tonne", 20),
    ("fired_brick", "Pishgan g‘isht", "Жжёный кирпич", "piece", 30),
    ("raw_brick", "Xom g‘isht", "Сырцовый кирпич", "piece", 40),
    ("cement", "Sement", "Цемент", "bag", 50),
    ("soil", "Tuproq", "Грунт", "tonne", 60),
    ("foam_block", "Penablok", "Пеноблок", "piece", 70),
    ("cinder_block", "Shlakoblok", "Шлакоблок", "piece", 80),
    ("gas_block", "Gazoblok", "Газоблок", "piece", 90),
    ("stone", "Mayda tosh", "Мелкий камень", "tonne", 100),
]


def upgrade():
    op.create_table(
        'material_categories',
        sa.Column('code', sa.String(30), primary_key=True),
        sa.Column('name_uz', sa.String(100), nullable=False),
        sa.Column('name_ru', sa.String(100), nullable=False),
        sa.Column('unit', sa.String(10), nullable=False),
        sa.Column('is_enabled', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('sort_order', sa.Integer(), nullable=False, server_default='0'),
    )
    t = sa.table('material_categories', sa.column('code'), sa.column('name_uz'), sa.column('name_ru'),
                 sa.column('unit'), sa.column('sort_order'))
    op.bulk_insert(t, [dict(code=c, name_uz=u, name_ru=r, unit=un, sort_order=s)
                       for c, u, r, un, s in CATEGORIES])

    op.create_table(
        'delivery_driver_profiles',
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('vehicle_code', sa.String(30), sa.ForeignKey('delivery_vehicles.code', ondelete='RESTRICT'),
                  nullable=False),
        sa.Column('plate', sa.String(20), nullable=True),
        sa.Column('price_per_km', sa.Numeric(12, 2), nullable=True),
        sa.Column('base_fee', sa.Numeric(12, 2), nullable=True),
        sa.Column('is_online', sa.Boolean(), nullable=False, server_default=sa.text('false')),
        sa.Column('latitude', sa.Numeric(10, 7), nullable=True),
        sa.Column('longitude', sa.Numeric(10, 7), nullable=True),
        sa.Column('location_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint('price_per_km IS NULL OR price_per_km >= 0', name='check_ddp_km'),
        sa.CheckConstraint('base_fee IS NULL OR base_fee >= 0', name='check_ddp_base'),
    )
    op.create_table(
        'delivery_driver_categories',
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('category_code', sa.String(30),
                  sa.ForeignKey('material_categories.code', ondelete='CASCADE'), primary_key=True),
        sa.Column('min_quantity', sa.Numeric(12, 2), nullable=False, server_default='1'),
        sa.CheckConstraint('min_quantity > 0', name='check_ddc_min'),
    )

    add = op.add_column
    add('material_orders', sa.Column('dispatch', sa.String(10), nullable=False, server_default='seller'))
    add('material_orders', sa.Column('delivery_payment', sa.String(10), nullable=False, server_default='balance'))
    add('material_orders', sa.Column('delivery_status', sa.String(20), nullable=True))
    add('material_orders', sa.Column('driver_id', sa.Integer(),
                                     sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True))
    add('material_orders', sa.Column('driver_fee', sa.Numeric(12, 2), nullable=True))
    add('material_orders', sa.Column('driver_commission', sa.Numeric(12, 2), nullable=False, server_default='0'))
    add('material_orders', sa.Column('driver_frozen', sa.Numeric(12, 2), nullable=False, server_default='0'))
    add('material_orders', sa.Column('accepted_at', sa.DateTime(timezone=True), nullable=True))
    add('material_orders', sa.Column('picked_up_at', sa.DateTime(timezone=True), nullable=True))
    add('material_orders', sa.Column('arrived_at', sa.DateTime(timezone=True), nullable=True))
    op.create_index('ix_material_orders_driver_id', 'material_orders', ['driver_id'])
    op.create_index('ix_material_orders_delivery_status', 'material_orders', ['delivery_status'])
    op.create_check_constraint('check_material_order_dispatch', 'material_orders',
                               "dispatch IN ('seller','driver')")
    op.create_check_constraint('check_material_order_delivery_payment', 'material_orders',
                               "delivery_payment IN ('balance','cash')")
    op.create_check_constraint(
        'check_material_order_delivery_status', 'material_orders',
        "delivery_status IS NULL OR delivery_status IN "
        "('waiting_seller','searching','accepted','picked_up','arrived','done','cancelled')")

    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications",
                               _check(NOTIFICATION_TYPES + ADDED))

    op.execute(
        "INSERT INTO app_settings (key, value) "
        "VALUES ('delivery_search_radius_km', to_jsonb('30'::text)) "
        "ON CONFLICT (key) DO NOTHING"
    )


def downgrade():
    op.execute("DELETE FROM app_settings WHERE key = 'delivery_search_radius_km'")
    op.execute("DELETE FROM notifications WHERE type IN "
               "('material_driver_found','material_picked_up','material_driver_arrived')")
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications", _check(NOTIFICATION_TYPES))
    for c in ('check_material_order_delivery_status', 'check_material_order_delivery_payment',
              'check_material_order_dispatch'):
        op.drop_constraint(c, 'material_orders', type_='check')
    op.drop_index('ix_material_orders_delivery_status', table_name='material_orders')
    op.drop_index('ix_material_orders_driver_id', table_name='material_orders')
    for col in ('arrived_at', 'picked_up_at', 'accepted_at', 'driver_frozen', 'driver_commission',
                'driver_fee', 'driver_id', 'delivery_status', 'delivery_payment', 'dispatch'):
        op.drop_column('material_orders', col)
    op.drop_table('delivery_driver_categories')
    op.drop_table('delivery_driver_profiles')
    op.drop_table('material_categories')
