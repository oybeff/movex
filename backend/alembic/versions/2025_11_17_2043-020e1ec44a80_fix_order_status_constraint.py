"""fix_order_status_constraint

Revision ID: 020e1ec44a80
Revises: 6d276423a8cf
Create Date: 2025-11-17 20:43:52.177584

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '020e1ec44a80'
down_revision: Union[str, Sequence[str], None] = '6d276423a8cf'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema - fix order status constraint."""
    # Drop old constraint
    op.drop_constraint('check_order_status', 'orders', type_='check')

    # Add new constraint with all statuses
    op.create_check_constraint(
        'check_order_status',
        'orders',
        "status IN ('pending','confirmed','rejected','cancelled','completed')"
    )


def downgrade() -> None:
    """Downgrade schema."""
    # Drop new constraint
    op.drop_constraint('check_order_status', 'orders', type_='check')

    # Add old constraint (without rejected)
    op.create_check_constraint(
        'check_order_status',
        'orders',
        "status IN ('pending','confirmed','cancelled','completed')"
    )
