"""Документы водителя: проверка перед выходом на линию (макет 00, R5–R9).

Revision ID: b9e2c4d71a06
Revises: a7d3f9c2e815
"""
from alembic import op
import sqlalchemy as sa

revision = "b9e2c4d71a06"
down_revision = "a7d3f9c2e815"
branch_labels = None
depends_on = None


def upgrade():
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
    op.drop_index("ix_driver_documents_user_id", table_name="driver_documents")
    op.drop_table("driver_documents")
