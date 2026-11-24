"""Admin panel: buyurtmalar ustidan amallar (Figma «Admin panel» → 02).

- admin_actions — admin nima qildi (bekor qilish, haydovchini almashtirish,
  izoh). Keyin «Audit jurnali» (09) shu jadvaldan o'qiydi;
- order_notes — «Ichki izoh»: faqat adminlar ko'radi, mijoz va haydovchi
  ko'rmaydi. kind: equipment | freight | material | request;
- bildirishnoma turi order_assigned — admin haydovchini/texnikani
  almashtirganda yangi ijrochiga.

Revision ID: a7c2e5f9b134
Revises: e6a1c3f8d297
"""
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'a7c2e5f9b134'
down_revision = 'e6a1c3f8d297'
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
)
ADDED = ("order_assigned",)


def _check(types):
    return "type IN (" + ", ".join(f"'{t}'" for t in types) + ")"


def upgrade():
    op.create_table(
        'admin_actions',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('admin_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('action', sa.String(40), nullable=False),
        sa.Column('entity', sa.String(20), nullable=False),
        sa.Column('entity_id', sa.Integer(), nullable=True),
        sa.Column('payload', postgresql.JSONB(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_admin_actions_entity', 'admin_actions', ['entity', 'entity_id'])
    op.create_index('ix_admin_actions_created', 'admin_actions', ['created_at'])

    op.create_table(
        'order_notes',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('kind', sa.String(12), nullable=False),
        sa.Column('order_id', sa.Integer(), nullable=False),
        sa.Column('admin_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('text', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint("kind IN ('equipment','freight','material','request')", name='check_order_note_kind'),
    )
    op.create_index('ix_order_notes_order', 'order_notes', ['kind', 'order_id'])

    op.add_column('freight_orders', sa.Column('cancel_reason', sa.String(30), nullable=True))
    op.add_column('material_orders', sa.Column('cancelled_by', sa.String(10), nullable=True))
    op.add_column('material_orders', sa.Column('cancel_reason', sa.String(30), nullable=True))

    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications",
                               _check(NOTIFICATION_TYPES + ADDED))


def downgrade():
    op.execute("DELETE FROM notifications WHERE type IN ('order_assigned')")
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications", _check(NOTIFICATION_TYPES))
    op.drop_column('material_orders', 'cancel_reason')
    op.drop_column('material_orders', 'cancelled_by')
    op.drop_column('freight_orders', 'cancel_reason')
    op.drop_index('ix_order_notes_order', 'order_notes')
    op.drop_table('order_notes')
    op.drop_index('ix_admin_actions_created', 'admin_actions')
    op.drop_index('ix_admin_actions_entity', 'admin_actions')
    op.drop_table('admin_actions')
