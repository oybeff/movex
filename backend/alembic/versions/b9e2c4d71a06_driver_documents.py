"""Документы водителя: проверка перед выходом на линию (макет 00, R5–R9).

Плюс типы уведомлений driver_approved / driver_document_rejected —
экран R9 обещает «natija haqida xabar beramiz».

Revision ID: b9e2c4d71a06
Revises: a7d3f9c2e815
"""
from alembic import op
import sqlalchemy as sa

revision = "b9e2c4d71a06"
down_revision = "a7d3f9c2e815"
branch_labels = None
depends_on = None


TYPES = (
    "order_created", "order_confirmed", "order_rejected", "order_cancelled",
    "order_completed", "balance_topup", "payout_paid", "payout_rejected", "system",
    "request_created", "request_offer", "request_offer_accepted", "request_offer_rejected",
    "request_cancelled", "listing_taken", "listing_confirmed", "listing_cancelled",
    "listing_done", "quick_request",
    "order_departed", "order_arrived", "order_started", "order_finished", "order_delayed",
    "order_extend_requested", "order_extend_approved", "order_extend_declined",
    "listing_offer",
    "material_order", "material_confirmed", "material_cancelled",
    "material_delivered", "material_moderated",
)
ADDED = ("driver_approved", "driver_document_rejected")


def _check(types) -> str:
    return "type IN (" + ",".join(f"'{t}'" for t in types) + ")"


def upgrade():
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications", _check(TYPES + ADDED))
    op.create_table(
        "driver_documents",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("kind", sa.String(20), nullable=False),
        sa.Column("file_name", sa.String(80), nullable=False),
        sa.Column("status", sa.String(10), nullable=False, server_default="pending"),
        sa.Column("reject_reason", sa.Text(), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "kind", name="uq_driver_document_kind"),
        sa.CheckConstraint(
            "kind IN ('passport','driver_license','tech_passport','equipment_photo','insurance')",
            name="check_driver_document_kind",
        ),
        sa.CheckConstraint("status IN ('pending','approved','rejected')", name="check_driver_document_status"),
    )
    op.create_index("ix_driver_documents_user_id", "driver_documents", ["user_id"])


def downgrade():
    op.execute("DELETE FROM notifications WHERE type IN ('driver_approved','driver_document_rejected')")
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications", _check(TYPES))
    op.drop_index("ix_driver_documents_user_id", table_name="driver_documents")
    op.drop_table("driver_documents")
