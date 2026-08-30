"""Make email optional in users table

Revision ID: c8ef10802744
Revises: d6cae9b10641
Create Date: 2025-11-08 12:37:39.439872

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c8ef10802744'
down_revision: Union[str, Sequence[str], None] = 'd6cae9b10641'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # First, update NULL phone values with default values
    op.execute("""
        UPDATE users
        SET phone = '998' || (90000000 + id)::text
        WHERE phone IS NULL
    """)

    # Then make phone NOT NULL
    op.alter_column('users', 'phone',
               existing_type=sa.VARCHAR(length=20),
               nullable=False)

    # Make email nullable (optional)
    op.alter_column('users', 'email',
               existing_type=sa.VARCHAR(length=100),
               nullable=True)


def downgrade() -> None:
    """Downgrade schema."""
    # Make email NOT NULL again
    op.alter_column('users', 'email',
               existing_type=sa.VARCHAR(length=100),
               nullable=False)

    # Make phone nullable again
    op.alter_column('users', 'phone',
               existing_type=sa.VARCHAR(length=20),
               nullable=True)
