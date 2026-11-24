"""Nizolar, yordam chati, sharhlar moderatsiyasi (Figma «Admin panel» 07).

- order_problems — endi HAMMA turdagi buyurtma uchun nizo: kind
  (equipment | freight | material), ochgan tomon (client | performer),
  mas'ul admin, birinchi javob va yechim vaqti (SLA), qaror va qaytarilgan
  summa. order_id endi orders'ga FK emas — buyurtma uch xil jadvalda.
- dispute_messages — uch tomonlama muloqot: visibility all | client |
  performer | internal (ichki izoh faqat adminlarga).
- support_threads / support_messages — ilovadagi «Yordam» chati.
- reviews.hidden — yashirilgan sharh reytingga kirmaydi.
- bildirishnoma turlari: dispute_message, dispute_resolved, support_reply,
  review_hidden.

Revision ID: b8d3f1a6c425
Revises: a7c2e5f9b134
"""
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'b8d3f1a6c425'
down_revision = 'a7c2e5f9b134'
branch_labels = None
depends_on = None

NOTIFICATION_TYPES = (
    "order_created", "order_confirmed", "order_rejected", "order_cancelled",
    "order_completed", "balance_topup", "payout_paid", "payout_rejected", "system",
    "request_created", "request_offer", "request_offer_accepted", "request_offer_rejected",
    "request_cancelled", "listing_taken", "listing_confirmed", "listing_cancelled",
    "listing_done", "quick_request", "order_departed", "order_arrived", "order_started",
    "order_finished", "order_delayed", "order_extend_requested", "order_extend_approved",
    "order_extend_declined", "listing_offer", "material_order", "material_confirmed",
    "material_cancelled", "material_delivered", "material_moderated", "driver_approved",
    "driver_document_rejected", "material_driver_found", "material_picked_up",
    "material_driver_arrived",
    "freight_driver_found", "freight_loaded", "freight_arrived", "freight_cancelled",
    "order_assigned",
)
ADDED = ("dispute_message", "dispute_resolved", "support_reply", "review_hidden")

OLD_REASONS = ('not_arrived', 'wrong_equipment', 'poor_quality', 'price_differs', 'other')
NEW_REASONS = OLD_REASONS + ('damaged', 'wrong_quantity', 'client_no_pay', 'client_absent')


def _in(col, values):
    return f"{col} IN (" + ", ".join(f"'{v}'" for v in values) + ")"


def upgrade():
    # ---------------------------------------------------------- nizolar
    op.drop_constraint('order_problems_order_id_fkey', 'order_problems', type_='foreignkey')
    op.add_column('order_problems', sa.Column('kind', sa.String(12), nullable=False, server_default='equipment'))
    op.add_column('order_problems', sa.Column('opened_role', sa.String(10), nullable=False, server_default='client'))
    op.add_column('order_problems', sa.Column('assigned_admin_id', sa.Integer(),
                                              sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True))
    op.add_column('order_problems', sa.Column('first_response_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('order_problems', sa.Column('resolved_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('order_problems', sa.Column('resolved_by', sa.Integer(),
                                              sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True))
    op.add_column('order_problems', sa.Column('resolution', sa.String(12), nullable=True))
    op.add_column('order_problems', sa.Column('refund_amount', sa.Numeric(14, 2), nullable=True))
    op.create_index('ix_order_problems_kind_order', 'order_problems', ['kind', 'order_id'])
    op.drop_constraint('check_problem_reason', 'order_problems', type_='check')
    op.create_check_constraint('check_problem_reason', 'order_problems', _in('reason', NEW_REASONS))
    op.create_check_constraint('check_problem_kind', 'order_problems', _in('kind', ('equipment', 'freight', 'material')))
    op.create_check_constraint('check_problem_role', 'order_problems', _in('opened_role', ('client', 'performer')))
    op.create_check_constraint('check_problem_resolution', 'order_problems',
                               "resolution IS NULL OR " + _in('resolution', ('client', 'partial', 'performer', 'close')))
    # Eski shikoyatlar bo'yicha birinchi javob yo'q edi — hal qilinganlari
    # uchun yechim vaqti noma'lum; SLA hisobida ular «hal qilingan» bo'lib qoladi.

    op.create_table(
        'dispute_messages',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('problem_id', sa.Integer(), sa.ForeignKey('order_problems.id', ondelete='CASCADE'), nullable=False),
        sa.Column('author_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('author_role', sa.String(10), nullable=False),
        sa.Column('visibility', sa.String(10), nullable=False, server_default='all'),
        sa.Column('text', sa.Text(), nullable=True),
        sa.Column('photos', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint(_in('author_role', ('client', 'performer', 'admin')), name='check_dm_role'),
        sa.CheckConstraint(_in('visibility', ('all', 'client', 'performer', 'internal')), name='check_dm_visibility'),
    )
    op.create_index('ix_dispute_messages_problem', 'dispute_messages', ['problem_id', 'created_at'])

    # ---------------------------------------------------------- yordam chati
    op.create_table(
        'support_threads',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('app', sa.String(10), nullable=False, server_default='client'),
        sa.Column('status', sa.String(10), nullable=False, server_default='open'),
        sa.Column('assigned_admin_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('last_message_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('user_read_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('admin_read_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint(_in('status', ('open', 'closed')), name='check_support_status'),
        sa.CheckConstraint(_in('app', ('client', 'driver')), name='check_support_app'),
    )
    op.create_index('ix_support_threads_user', 'support_threads', ['user_id'])
    op.create_index('ix_support_threads_status', 'support_threads', ['status', 'last_message_at'])
    op.create_table(
        'support_messages',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('thread_id', sa.Integer(), sa.ForeignKey('support_threads.id', ondelete='CASCADE'), nullable=False),
        sa.Column('author_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('is_admin', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('text', sa.Text(), nullable=True),
        sa.Column('photo', sa.String(300), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_support_messages_thread', 'support_messages', ['thread_id', 'created_at'])

    # ---------------------------------------------------------- sharhlar
    op.add_column('reviews', sa.Column('hidden', sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column('reviews', sa.Column('hidden_reason', sa.String(30), nullable=True))
    op.add_column('reviews', sa.Column('moderated_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('reviews', sa.Column('moderated_by', sa.Integer(),
                                       sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True))

    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications", _in('type', NOTIFICATION_TYPES + ADDED))


def downgrade():
    op.execute("DELETE FROM notifications WHERE type IN ('dispute_message','dispute_resolved','support_reply','review_hidden')")
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications", _in('type', NOTIFICATION_TYPES))
    for c in ('moderated_by', 'moderated_at', 'hidden_reason', 'hidden'):
        op.drop_column('reviews', c)
    op.drop_table('support_messages')
    op.drop_table('support_threads')
    op.drop_table('dispute_messages')
    op.execute("DELETE FROM order_problems WHERE kind <> 'equipment'")
    for name in ('check_problem_resolution', 'check_problem_role', 'check_problem_kind', 'check_problem_reason'):
        op.drop_constraint(name, 'order_problems', type_='check')
    op.execute("UPDATE order_problems SET reason = 'other' WHERE " + "NOT " + _in('reason', OLD_REASONS))
    op.create_check_constraint('check_problem_reason', 'order_problems', _in('reason', OLD_REASONS))
    op.drop_index('ix_order_problems_kind_order', 'order_problems')
    for c in ('refund_amount', 'resolution', 'resolved_by', 'resolved_at', 'first_response_at',
              'assigned_admin_id', 'opened_role', 'kind'):
        op.drop_column('order_problems', c)
    op.create_foreign_key('order_problems_order_id_fkey', 'order_problems', 'orders', ['order_id'], ['id'], ondelete='CASCADE')
