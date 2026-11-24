"""Tarif paketlari: «Tezkor» — 6 soat, «Kun davomida» — 12 soat (Sherzodbek, 24.11.2026).

Paketli tarifda narx PAKET uchun (6 yoki 12 soat), soatlar o'zgarmaydi.
«Ekonom» — avvalgidek soatbay. Admin ko'rsatgan joriy narx Sherzodbek
aytganidek paket narxi deb olinadi: «6 soat uchun shu narx»; soatlik narx
(uzaytirish uchun) undan hisoblanadi.

Revision ID: d4f6b8a1c357
Revises: c2e4a7d9f163
"""
import sqlalchemy as sa
from alembic import op

revision = 'd4f6b8a1c357'
down_revision = 'c2e4a7d9f163'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('tariffs', sa.Column('package_hours', sa.Integer(), nullable=True))
    op.add_column('tariffs', sa.Column('package_price', sa.Numeric(12, 2), nullable=True))
    op.execute("""
        UPDATE tariffs SET package_hours = CASE tier WHEN 'fast' THEN 6 WHEN 'day' THEN 12 END,
                           package_price = price_per_hour
         WHERE tier IN ('fast', 'day')
    """)
    op.execute("""
        UPDATE tariffs SET price_per_hour = ROUND(package_price / package_hours), min_hours = package_hours
         WHERE package_hours IS NOT NULL
    """)
    op.create_check_constraint('check_tariff_package', 'tariffs',
                               "(package_hours IS NULL) = (package_price IS NULL)")


def downgrade():
    op.execute("UPDATE tariffs SET price_per_hour = package_price, min_hours = 1 WHERE package_hours IS NOT NULL")
    op.drop_constraint('check_tariff_package', 'tariffs', type_='check')
    op.drop_column('tariffs', 'package_price')
    op.drop_column('tariffs', 'package_hours')
