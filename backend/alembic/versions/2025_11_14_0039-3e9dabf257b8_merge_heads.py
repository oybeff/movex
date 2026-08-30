"""merge heads

Revision ID: 3e9dabf257b8
Revises: 716da266892a, add_click_fields
Create Date: 2025-11-14 00:39:12.061543

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '3e9dabf257b8'
down_revision: Union[str, Sequence[str], None] = ('716da266892a', 'add_click_fields')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
