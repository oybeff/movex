"""Zayavkani bekor qilish sababi (maket E6)

Revision ID: e4c7b1a9f023
Revises: d6f2b8e3a015
Create Date: 2026-11-18

Mijoz qidiruv vaqtida zayavkani bekor qilganda sababni tanlaydi (E6).
Endi equipment_requests.cancel_reason da saqlanadi.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "e4c7b1a9f023"
down_revision: Union[str, Sequence[str], None] = "d6f2b8e3a015"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("equipment_requests", sa.Column("cancel_reason", sa.String(30), nullable=True))


def downgrade() -> None:
    op.drop_column("equipment_requests", "cancel_reason")
