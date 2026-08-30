"""Texnika turlarini erkin matndan kodga o'tkazish

Ilgari equipment.type erkin matn edi ("Ekskavator", "экскаватор",
"Ekskavator-pogruzchik"), shuning uchun turga ikonka biriktirib ham,
katalogda normal filtr qilib ham bo'lmasdi.

Bu migratsiya mavjud yozuvlarni ma'lumotnomadagi kodlarga o'tkazadi
(app/core/equipment_types.py). Tanib bo'lmagan qiymat 'other' bo'ladi,
lekin asl matn yo'qolmasligi uchun avval type_legacy ustuniga ko'chiriladi —
migratsiyani orqaga qaytarish yoki qo'lda tekshirish mumkin bo'lsin.

Revision ID: b7c1e2a45d90
Revises: a1b2c3d4e5f6
"""
from alembic import op
import sqlalchemy as sa

from app.core.equipment_types import normalize_type

revision = "b7c1e2a45d90"
down_revision = "a1b2c3d4e5f6"
branch_labels = None
depends_on = None


def upgrade():
    # Asl qiymatni saqlab qo'yamiz
    op.add_column("equipment", sa.Column("type_legacy", sa.String(length=50), nullable=True))

    connection = op.get_bind()
    connection.execute(sa.text("UPDATE equipment SET type_legacy = type"))

    rows = connection.execute(
        sa.text("SELECT DISTINCT type FROM equipment WHERE type IS NOT NULL")
    ).fetchall()

    for (raw_type,) in rows:
        code = normalize_type(raw_type)
        if code != raw_type:
            connection.execute(
                sa.text("UPDATE equipment SET type = :code WHERE type = :raw"),
                {"code": code, "raw": raw_type},
            )


def downgrade():
    connection = op.get_bind()
    connection.execute(
        sa.text("UPDATE equipment SET type = type_legacy WHERE type_legacy IS NOT NULL")
    )
    op.drop_column("equipment", "type_legacy")
