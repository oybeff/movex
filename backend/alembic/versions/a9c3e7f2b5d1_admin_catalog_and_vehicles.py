"""Справочники в админке: типы техники (equipment_catalog), машины доставки
(delivery_vehicles), переключатель стройматериалов (materials_enabled).

Revision ID: a9c3e7f2b5d1
Revises: f2e4b6a8c0d2
"""
import sqlalchemy as sa
from alembic import op

revision = 'a9c3e7f2b5d1'
down_revision = 'f2e4b6a8c0d2'
branch_labels = None
depends_on = None

# (code, uz, ru, group, sort) — те же коды, что в app/core/equipment_types.py
TYPES = [
    ("excavator", "Ekskavator", "Экскаватор", "earth", 10),
    ("backhoe_loader", "Ekskavator-yuklagich", "Экскаватор-погрузчик", "earth", 20),
    ("mini_excavator", "Mini ekskavator", "Мини-экскаватор", "earth", 30),
    ("bulldozer", "Buldozer", "Бульдозер", "earth", 40),
    ("front_loader", "Frontal yuklagich", "Фронтальный погрузчик", "earth", 50),
    ("grader", "Greyder", "Грейдер", "earth", 60),
    ("roller", "Katok", "Каток", "earth", 70),
    ("truck_crane", "Avtokran", "Автокран", "lifting", 110),
    ("manipulator", "Manipulyator", "Манипулятор", "lifting", 120),
    ("aerial_platform", "Avtovishka", "Автовышка", "lifting", 130),
    ("dump_truck", "Samosval", "Самосвал", "transport", 210),
    ("tow_truck", "Tral / Evakuator", "Трал / Эвакуатор", "transport", 220),
    ("concrete_mixer", "Beton aralashtirgich", "Бетономешалка", "concrete", 310),
    ("concrete_pump", "Betonnasos", "Бетононасос", "concrete", 320),
    ("auger_drill", "Yamobur", "Ямобур", "other", 410),
    ("compressor", "Kompressor", "Компрессор", "other", 420),
    ("other", "Boshqa texnika", "Другая техника", "other", 900),
]

# (code, name, kg, m3, sort) — список из ТЗ Шерзодбека. Коды labo, isuzu,
# kamaz, howo уже записаны в material_orders.vehicle_code — их не трогать.
VEHICLES = [
    ("damas", "Damas", 500, 2.5, 10),
    ("labo", "Labo", 700, 2.5, 20),
    ("porter", "Hyundai Porter", 1000, 6, 30),
    ("bongo", "Kia Bongo", 1500, 7, 40),
    ("gazel", "Gazel", 2000, 9, 50),
    ("isuzu_3", "Isuzu NPR", 3000, 15, 60),
    ("mighty", "Hyundai Mighty", 4000, 18, 70),
    ("isuzu", "Isuzu NQR", 5000, 20, 80),
    ("kamaz", "KamAZ", 15000, 12, 90),
    ("fura", "Fura", 20000, 82, 100),
    ("howo", "HOWO", 25000, 20, 110),
]


def upgrade():
    op.create_table(
        'equipment_catalog',
        sa.Column('code', sa.String(40), primary_key=True),
        sa.Column('name_uz', sa.String(100), nullable=False),
        sa.Column('name_ru', sa.String(100), nullable=False),
        sa.Column('group_code', sa.String(20), nullable=False, server_default='other'),
        sa.Column('subtitle_uz', sa.String(150), nullable=True),
        sa.Column('subtitle_ru', sa.String(150), nullable=True),
        sa.Column('icon_url', sa.String(255), nullable=True),
        sa.Column('is_enabled', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('sort_order', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_table(
        'delivery_vehicles',
        sa.Column('code', sa.String(30), primary_key=True),
        sa.Column('name', sa.String(60), nullable=False),
        sa.Column('capacity_kg', sa.Integer(), nullable=False),
        sa.Column('volume_m3', sa.Numeric(6, 2), nullable=True),
        sa.Column('base_fee', sa.Numeric(12, 2), nullable=False, server_default='0'),
        sa.Column('price_per_km', sa.Numeric(12, 2), nullable=True),
        sa.Column('is_enabled', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('sort_order', sa.Integer(), nullable=False, server_default='0'),
        sa.CheckConstraint('capacity_kg > 0', name='check_delivery_vehicle_capacity'),
        sa.CheckConstraint('base_fee >= 0', name='check_delivery_vehicle_base_fee'),
        sa.CheckConstraint('price_per_km IS NULL OR price_per_km >= 0', name='check_delivery_vehicle_km'),
    )
    cat = sa.table('equipment_catalog', sa.column('code'), sa.column('name_uz'), sa.column('name_ru'),
                   sa.column('group_code'), sa.column('sort_order'))
    op.bulk_insert(cat, [dict(code=c, name_uz=u, name_ru=r, group_code=g, sort_order=s) for c, u, r, g, s in TYPES])
    veh = sa.table('delivery_vehicles', sa.column('code'), sa.column('name'), sa.column('capacity_kg'),
                   sa.column('volume_m3'), sa.column('sort_order'))
    op.bulk_insert(veh, [dict(code=c, name=n, capacity_kg=k, volume_m3=v, sort_order=s) for c, n, k, v, s in VEHICLES])
    op.execute("""
        INSERT INTO app_settings (key, value)
        VALUES ('materials_enabled', to_jsonb('1'::text))
        ON CONFLICT (key) DO NOTHING
    """)


def downgrade():
    op.execute("DELETE FROM app_settings WHERE key = 'materials_enabled'")
    op.drop_table('delivery_vehicles')
    op.drop_table('equipment_catalog')
