"""users.language — til serverda yoziladigan matnlar uchun

Xabarnoma sarlavhasi va matni serverda tuziladi va bazada tayyor satr
bo'lib yotadi. Ilova sarlavhani o'z tilida qayta yig'a oladi, lekin PUSH
uchun bu ishlamaydi: push matnini server yozadi va telefon ekranida u
o'zgarmaydi.

Shuning uchun foydalanuvchining tili bazada ham saqlanadi. Mavjud
yozuvlarga 'uz' qo'yiladi — ilovada sukut bo'yicha o'sha til.

Revision ID: d7e3a9b41c68
Revises: a8f2c31d5e07
"""
from alembic import op
import sqlalchemy as sa

revision = "d7e3a9b41c68"
down_revision = "a8f2c31d5e07"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("language", sa.String(length=5), nullable=False, server_default="uz"),
    )
    op.create_check_constraint(
        "check_user_language", "users", "language IN ('uz','ru')"
    )


def downgrade() -> None:
    op.drop_constraint("check_user_language", "users", type_="check")
    op.drop_column("users", "language")
