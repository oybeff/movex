"""update_transaction_type_constraint

Revision ID: 6d276423a8cf
Revises: d29c11dfba6d
Create Date: 2025-11-16 23:45:21.744230

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '6d276423a8cf'
down_revision: Union[str, Sequence[str], None] = 'd29c11dfba6d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Drop old constraint
    op.drop_constraint('check_transaction_type', 'balance_transactions', type_='check')

    # Create new constraint with 'income' and 'refund' types
    op.create_check_constraint(
        'check_transaction_type',
        'balance_transactions',
        "type IN ('topup','payment','income','refund')"
    )


def downgrade() -> None:
    """Downgrade schema."""
    # Drop new constraint
    op.drop_constraint('check_transaction_type', 'balance_transactions', type_='check')

    # Restore old constraint (without 'income' and 'refund')
    op.create_check_constraint(
        'check_transaction_type',
        'balance_transactions',
        "type IN ('topup','payment')"
    )
