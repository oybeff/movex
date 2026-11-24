"""Картинка грузовика из админки (catalog.php): Labo, Porter, Gazel…

Дизайнер (Xusniddin) рисует иконки по моделям; админ загружает их сам,
без новой версии приложения. NULL — общая картинка грузовика в приложении.

Revision ID: a7d9c1e3f584
Revises: f1c3e5a7b924
"""
from alembic import op
import sqlalchemy as sa

revision = 'a7d9c1e3f584'
down_revision = 'f1c3e5a7b924'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('delivery_vehicles', sa.Column('icon_url', sa.String(255), nullable=True))


def downgrade():
    op.drop_column('delivery_vehicles', 'icon_url')
