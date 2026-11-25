"""Push водителям «Yuk mashinam»: новая доставка и новая перевозка.

delivery_job — заказ материалов перешёл в поиск водителя (продавец
подтвердил, или прежний водитель отказался).
freight_job — клиент создал перевозку груза (или водитель отказался).

Revision ID: e5a9c3f7d281
Revises: d9f2b4c6e813
Create Date: 2026-11-25
"""
from alembic import op

revision = 'e5a9c3f7d281'
down_revision = 'd9f2b4c6e813'
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
    "dispute_message", "dispute_resolved", "support_reply", "review_hidden",
)
ADDED = ("delivery_job", "freight_job")


def _in(col, values):
    return f"{col} IN (" + ", ".join(f"'{v}'" for v in values) + ")"


def upgrade():
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications",
                               _in('type', NOTIFICATION_TYPES + ADDED))


def downgrade():
    op.execute("DELETE FROM notifications WHERE type IN ('delivery_job','freight_job')")
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications",
                               _in('type', NOTIFICATION_TYPES))
