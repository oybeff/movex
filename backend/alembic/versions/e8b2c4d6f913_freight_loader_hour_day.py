"""Yuk tashish: грузчик по часам или на день (Шерзодбек, 24.11.2026).

Было: одна сумма `freight_loader_fee` за «Yuklovchi kerak». Стало: клиент
выбирает режим — по часам (`freight_loader_fee` теперь цена ЧАСА, 50 000)
или на весь день (`freight_loader_day_fee`, 120 000). Режим и часы пишутся
в заказ: смена цены в админке историю не переписывает (сумма уже лежит в
`loader_fee`).

Revision ID: e8b2c4d6f913
Revises: d4f6b8a1c357
"""
from alembic import op
import sqlalchemy as sa

revision = 'e8b2c4d6f913'
down_revision = 'd4f6b8a1c357'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('freight_orders', sa.Column('loader_mode', sa.String(4), nullable=True))
    op.add_column('freight_orders', sa.Column('loader_hours', sa.Integer(), nullable=True))
    op.create_check_constraint(
        'check_freight_loader_mode', 'freight_orders',
        "loader_mode IS NULL OR loader_mode IN ('hour', 'day')")
    # Старые заказы с грузчиком — это была почасовая цена за 1 час.
    op.execute("UPDATE freight_orders SET loader_mode = 'hour', loader_hours = 1 WHERE needs_loader")
    op.execute(
        "INSERT INTO app_settings (key, value) VALUES ('freight_loader_day_fee', to_jsonb('120000'::text)) "
        "ON CONFLICT (key) DO NOTHING")


def downgrade():
    op.execute("DELETE FROM app_settings WHERE key = 'freight_loader_day_fee'")
    op.drop_constraint('check_freight_loader_mode', 'freight_orders', type_='check')
    op.drop_column('freight_orders', 'loader_hours')
    op.drop_column('freight_orders', 'loader_mode')
