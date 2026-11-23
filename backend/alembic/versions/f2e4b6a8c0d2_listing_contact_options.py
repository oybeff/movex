"""E'lonlar: aloqa usullari (telegram, chat) va e'lon xabarlari (listing_messages).

Revision ID: f2e4b6a8c0d2
Revises: d7e2a5c84f16
"""
import sqlalchemy as sa
from alembic import op

revision = 'f2e4b6a8c0d2'
down_revision = 'd7e2a5c84f16'
branch_labels = None
depends_on = None


def upgrade():
    # listings jadvaliga yangi ustunlar
    op.add_column('listings', sa.Column('contact_telegram', sa.String(100), nullable=True))
    op.add_column('listings', sa.Column('allow_chat', sa.Boolean(), nullable=False, server_default=sa.text('true')))

    # E'lonlar ichidagi chat xabarlari
    op.create_table(
        'listing_messages',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('listing_id', sa.Integer(), sa.ForeignKey('listings.id', ondelete='CASCADE'), nullable=False),
        sa.Column('sender_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('receiver_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('message_text', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index('ix_listing_messages_listing_id', 'listing_messages', ['listing_id'])
    op.create_index('ix_listing_messages_sender_id', 'listing_messages', ['sender_id'])
    op.create_index('ix_listing_messages_receiver_id', 'listing_messages', ['receiver_id'])


def downgrade():
    op.drop_table('listing_messages')
    op.drop_column('listings', 'allow_chat')
    op.drop_column('listings', 'contact_telegram')
