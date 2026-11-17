"""Buyurtmani bekor qilish sababi (maket E6)

Revision ID: d6f2b8e3a015
Revises: c5e1a7d2f904
Create Date: 2026-11-18

Mijoz bekor qilganda sababni tanlaydi (Rejalar o'zgardi, Juda uzoq kutish,
Manzil xato, Boshqa) — ilgari tanlov ekranda bor edi, lekin hech qayerga
yozilmasdi. Endi orders.cancel_reason da saqlanadi va adminkada ko'rinadi.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "d6f2b8e3a015"
down_revision: Union[str, Sequence[str], None] = "c5e1a7d2f904"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("orders", sa.Column("cancel_reason", sa.String(30), nullable=True))


def downgrade() -> None:
    op.drop_column("orders", "cancel_reason")
