"""«Yuk tashish» по шагам макета Y1–Y8 (24.11.2026).

delivery_vehicles: марка, класс (small/medium/large/trailer), размеры
кузова (для проверки «sig'maydi», Y7), список кузовов модели (tent,
open = bortli, van = furgon, isothermal, fridge, tank, manipulator).

freight_orders: тип груза, размеры, нужен ли грузчик (+ цена грузчика из
app_settings.freight_loader_fee), когда (scheduled_at; NULL — сейчас).

Revision ID: e6a1c3f8d297
Revises: d2b7e9a4c158
"""
import sqlalchemy as sa
from alembic import op

revision = 'e6a1c3f8d297'
down_revision = 'd2b7e9a4c158'
branch_labels = None
depends_on = None

BODIES = "'tent','open','van','isothermal','fridge','tank','manipulator'"

# code: brand, class, L, W, H, bodies
SEED = {
    'damas': ('Damas', 'small', 1.8, 1.2, 1.2, 'van'),
    'labo': ('Labo', 'small', 2.0, 1.4, 0.4, 'open,tent'),
    'porter': ('Hyundai', 'medium', 2.8, 1.6, 1.6, 'tent,open,van,isothermal,fridge'),
    'bongo': ('Kia', 'medium', 2.9, 1.6, 1.5, 'tent,open,van'),
    'gazel': ('Gazel', 'small', 3.0, 1.9, 1.9, 'tent,open,van,isothermal'),
    'isuzu_3': ('Isuzu', 'medium', 4.4, 2.1, 2.1, 'tent,open,van,isothermal,fridge'),
    'mighty': ('Hyundai', 'medium', 4.3, 2.0, 2.0, 'tent,open,van,manipulator'),
    'isuzu': ('Isuzu', 'medium', 5.2, 2.2, 2.2, 'tent,open,van,isothermal,fridge,manipulator'),
    'kamaz': ('KamAZ', 'large', 6.0, 2.4, 1.0, 'open,tent'),
    'fura': ('Fura', 'trailer', 13.6, 2.45, 2.7, 'tent,isothermal,fridge'),
    'howo': ('HOWO', 'large', 5.6, 2.3, 1.5, 'open'),
}


def upgrade():
    add = op.add_column
    add('delivery_vehicles', sa.Column('brand', sa.String(40), nullable=True))
    add('delivery_vehicles', sa.Column('size_class', sa.String(10), nullable=False, server_default='medium'))
    add('delivery_vehicles', sa.Column('body_length_m', sa.Numeric(5, 2), nullable=True))
    add('delivery_vehicles', sa.Column('body_width_m', sa.Numeric(5, 2), nullable=True))
    add('delivery_vehicles', sa.Column('body_height_m', sa.Numeric(5, 2), nullable=True))
    add('delivery_vehicles', sa.Column('body_types', sa.String(120), nullable=False, server_default=''))
    op.create_check_constraint('check_delivery_vehicle_class', 'delivery_vehicles',
                               "size_class IN ('small','medium','large','trailer')")
    for code, (brand, cls, l, w, h, bodies) in SEED.items():
        op.execute(sa.text(
            "UPDATE delivery_vehicles SET brand=:b, size_class=:c, body_length_m=:l, body_width_m=:w, "
            "body_height_m=:h, body_types=:t, has_body_choice=:hc WHERE code=:code"
        ).bindparams(b=brand, c=cls, l=l, w=w, h=h, t=bodies, hc=',' in bodies, code=code))

    op.drop_constraint('check_ddp_body', 'delivery_driver_profiles', type_='check')
    op.create_check_constraint('check_ddp_body', 'delivery_driver_profiles',
                               f"body_type IS NULL OR body_type IN ({BODIES})")
    op.drop_constraint('check_freight_body', 'freight_orders', type_='check')
    op.create_check_constraint('check_freight_body', 'freight_orders',
                               f"body_type IS NULL OR body_type IN ({BODIES})")

    add('freight_orders', sa.Column('cargo_type', sa.String(20), nullable=True))
    add('freight_orders', sa.Column('cargo_length_m', sa.Numeric(5, 2), nullable=True))
    add('freight_orders', sa.Column('cargo_width_m', sa.Numeric(5, 2), nullable=True))
    add('freight_orders', sa.Column('cargo_height_m', sa.Numeric(5, 2), nullable=True))
    add('freight_orders', sa.Column('cargo_volume_m3', sa.Numeric(7, 2), nullable=True))
    add('freight_orders', sa.Column('needs_loader', sa.Boolean(), nullable=False, server_default=sa.text('false')))
    add('freight_orders', sa.Column('loader_fee', sa.Numeric(12, 2), nullable=False, server_default='0'))
    add('freight_orders', sa.Column('scheduled_at', sa.DateTime(timezone=True), nullable=True))

    op.execute(
        "INSERT INTO app_settings (key, value) VALUES ('freight_loader_fee', to_jsonb('50000'::text)) "
        "ON CONFLICT (key) DO NOTHING"
    )


def downgrade():
    op.execute("DELETE FROM app_settings WHERE key = 'freight_loader_fee'")
    for c in ('scheduled_at', 'loader_fee', 'needs_loader', 'cargo_volume_m3', 'cargo_height_m',
              'cargo_width_m', 'cargo_length_m', 'cargo_type'):
        op.drop_column('freight_orders', c)
    op.drop_constraint('check_freight_body', 'freight_orders', type_='check')
    op.create_check_constraint('check_freight_body', 'freight_orders',
                               "body_type IS NULL OR body_type IN ('tent','open')")
    op.drop_constraint('check_ddp_body', 'delivery_driver_profiles', type_='check')
    op.create_check_constraint('check_ddp_body', 'delivery_driver_profiles',
                               "body_type IS NULL OR body_type IN ('tent','open')")
    op.drop_constraint('check_delivery_vehicle_class', 'delivery_vehicles', type_='check')
    for c in ('body_types', 'body_height_m', 'body_width_m', 'body_length_m', 'size_class', 'brand'):
        op.drop_column('delivery_vehicles', c)
