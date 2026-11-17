"""Профиль клиента по макету: фото (Pr2) и сохранённые адреса (Pr4).

Revision ID: a7d3e9c41b56
Revises: f2a9c6d1b384
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'a7d3e9c41b56'
down_revision: Union[str, Sequence[str], None] = 'f2a9c6d1b384'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('avatar_url', sa.Text(), nullable=True))
    op.create_table(
        'user_addresses',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'),
                  nullable=False, index=True),
        sa.Column('kind', sa.String(10), nullable=False, server_default='other'),
        sa.Column('title', sa.String(60), nullable=False),
        sa.Column('address', sa.Text(), nullable=False),
        sa.Column('latitude', sa.Numeric(10, 7), nullable=False),
        sa.Column('longitude', sa.Numeric(10, 7), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint("kind IN ('home','work','site','other')", name='check_address_kind'),
    )


def downgrade() -> None:
    op.drop_table('user_addresses')
    op.drop_column('users', 'avatar_url')
