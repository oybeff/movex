"""Telegram orqali kirish olib tashlandi — jadvallari ham

Kirish oqimi bitta bo'lib qoldi: raqamni SMS kodi bilan tasdiqlash, so'ng
PIN kod. Telegram bilan kirish (bot orqali tasdiqlash) butunlay olib
tashlandi, shuning uchun uning ikki jadvali ham keraksiz:

  telegram_login_requests — kirish so'rovlari (bir martalik, vaqtinchalik);
  telegram_accounts       — raqam va Telegram hisobi bog'lanishi.

Guruhga xabarnoma yuborish (telegram_service) QOLADI — u botdan javob
kutmaydi va bu jadvallarga tegmaydi.

Downgrade jadvallarni qaytaradi, lekin MA'LUMOTSIZ: bog'lanishlar
tiklanmaydi. Bu ataylab — kirish usuli qaytarilsa, odamlar botga qayta
ulanishi kerak, eski bog'lanishga ishonib bo'lmaydi.

Revision ID: d4e7a1c93f52
Revises: b6d1f38a52c9
Create Date: 2026-10-04
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "d4e7a1c93f52"
down_revision: Union[str, Sequence[str], None] = "b6d1f38a52c9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_table(name: str) -> bool:
    bind = op.get_bind()
    return name in sa.inspect(bind).get_table_names()


def upgrade() -> None:
    # Avval so'rovlar jadvali: unda accounts ga havola bo'lishi mumkin.
    for table in ("telegram_login_requests", "telegram_accounts"):
        if _has_table(table):
            op.drop_table(table)


def downgrade() -> None:
    if not _has_table("telegram_accounts"):
        op.create_table(
            "telegram_accounts",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("phone", sa.String(length=20), nullable=False, index=True),
            sa.Column("chat_id", sa.String(length=50), nullable=False),
            sa.Column("username", sa.String(length=100), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
        )

    if not _has_table("telegram_login_requests"):
        op.create_table(
            "telegram_login_requests",
            sa.Column("id", sa.Integer(), primary_key=True),
            sa.Column("token", sa.String(length=64), nullable=False, unique=True, index=True),
            sa.Column("phone", sa.String(length=20), nullable=True),
            sa.Column("is_used", sa.Boolean(), nullable=False, server_default=sa.text("false")),
            sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        )
