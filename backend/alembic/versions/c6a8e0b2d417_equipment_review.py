"""Admin P4 (T1/T2): texnika tekshiruvi — kim va qachon ko'rib chiqdi.

Ko'rinishga ta'sir qilmaydi: tekshirilmagan texnika ham katalogda bor
(egalar uchun yangi to'siq qo'yilmadi). Bu admin navbati uchun belgi.

Revision ID: c6a8e0b2d417
Revises: b3e5f7a9c126
"""
from alembic import op
import sqlalchemy as sa

revision = 'c6a8e0b2d417'
down_revision = 'b3e5f7a9c126'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('equipment', sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('equipment', sa.Column('reviewed_by', sa.Integer(),
                                         sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True))
    # Mavjud texnika allaqachon ishlab turibdi — navbatga faqat yangilari tushadi.
    op.execute("UPDATE equipment SET reviewed_at = created_at WHERE reviewed_at IS NULL AND created_at < NOW() - INTERVAL '3 days'")


def downgrade():
    op.drop_column('equipment', 'reviewed_by')
    op.drop_column('equipment', 'reviewed_at')
