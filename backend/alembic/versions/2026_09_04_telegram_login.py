"""Telegram orqali kirish: hisob bog'lanishi va kirish so'rovlari

Telegram boti odamga birinchi bo'lib yoza olmaydi va uni telefon raqami
bo'yicha topa olmaydi. Shuning uchun birinchi kirish chuqur havola orqali:
odam Start bosadi va raqamini ulashadi, biz chat_id ni bilib olamiz va
saqlaymiz. Keyingi kirishlarda kod to'g'ridan-to'g'ri Telegramga ketadi.

Revision ID: e2c7d4a91f35
Revises: d8b2f5a91e47
"""
from alembic import op
import sqlalchemy as sa

revision = "e2c7d4a91f35"
down_revision = "d8b2f5a91e47"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "telegram_accounts",
        sa.Column("id", sa.Integer(), primary_key=True),
        # BigInteger ataylab: Telegram id lari int32 dan oshib ketgan
        sa.Column("chat_id", sa.BigInteger(), nullable=False, unique=True),
        sa.Column("phone", sa.String(20), nullable=False, unique=True),
        sa.Column("username", sa.String(64), nullable=True),
        sa.Column("first_name", sa.String(100), nullable=True),
        sa.Column("user_id", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_telegram_accounts_chat_id", "telegram_accounts", ["chat_id"])
    op.create_index("ix_telegram_accounts_phone", "telegram_accounts", ["phone"])
    op.create_index("ix_telegram_accounts_user_id", "telegram_accounts", ["user_id"])

    op.create_table(
        "telegram_login_requests",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("token", sa.String(48), nullable=False, unique=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("phone", sa.String(20), nullable=True),
        sa.Column("chat_id", sa.BigInteger(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("status IN ('pending','confirmed','used')",
                           name="check_tg_login_status"),
    )
    op.create_index("ix_tg_login_token", "telegram_login_requests", ["token"])
    op.create_index("ix_tg_login_status", "telegram_login_requests", ["status"])
    op.create_index("ix_tg_login_phone", "telegram_login_requests", ["phone"])
    op.create_index("ix_tg_login_expires", "telegram_login_requests", ["expires_at"])


def downgrade() -> None:
    op.drop_table("telegram_login_requests")
    op.drop_table("telegram_accounts")
