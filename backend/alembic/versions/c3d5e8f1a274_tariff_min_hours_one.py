"""Tarif: eng kam buyurtma 1 soat (Sherzodbek, 22.11.2026)

Revision ID: c3d5e8f1a274
Revises: b9e2c4d71a06
"""
from alembic import op

revision = 'c3d5e8f1a274'
down_revision = 'b9e2c4d71a06'
branch_labels = None
depends_on = None


def upgrade():
    op.alter_column('tariffs', 'min_hours', server_default='1')
    # Faqat eski standart (4) qiymatlar: admin qo'lda boshqa qo'ygan bo'lsa — tegilmaydi.
    op.execute("UPDATE tariffs SET min_hours = 1 WHERE min_hours = 4")


def downgrade():
    op.alter_column('tariffs', 'min_hours', server_default='4')
