"""Admin P4: блок с причиной и сроком, срок документов, замок проверки.

- users.blocked_until / blocked_at / blocked_by / block_reason_code /
  block_note — C3/C4 (причина, срок 24 ч / 7 / 30 дней / навсегда, кто).
  По истечении срока блок снимается лениво — при следующем запросе.
- driver_documents.expires_on — срок прав и техпаспорта (вводит админ при
  проверке); reviewed_by — кто проверил (H2).
- doc_review_locks — V4: двое админов не проверяют одного водителя сразу.

Revision ID: b3e5f7a9c126
Revises: a7d9c1e3f584
"""
from alembic import op
import sqlalchemy as sa

revision = 'b3e5f7a9c126'
down_revision = 'a7d9c1e3f584'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('users', sa.Column('blocked_until', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('blocked_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('blocked_by', sa.Integer(),
                                     sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True))
    op.add_column('users', sa.Column('block_reason_code', sa.String(20), nullable=True))
    op.add_column('users', sa.Column('block_note', sa.Text(), nullable=True))
    op.add_column('driver_documents', sa.Column('expires_on', sa.Date(), nullable=True))
    op.add_column('driver_documents', sa.Column('reviewed_by', sa.Integer(),
                                                sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True))
    op.create_table(
        'doc_review_locks',
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('admin_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('locked_until', sa.DateTime(timezone=True), nullable=False),
    )


def downgrade():
    op.drop_table('doc_review_locks')
    op.drop_column('driver_documents', 'reviewed_by')
    op.drop_column('driver_documents', 'expires_on')
    for c in ('block_note', 'block_reason_code', 'blocked_by', 'blocked_at', 'blocked_until'):
        op.drop_column('users', c)
