"""Pul yechish arizalari

Texnika egasining balansi o'sib borardi, lekin pulni olib chiqishning
hech qanday yo'li yo'q edi — marketpleys uchun bu jiddiy kamchilik.

Shu bilan birga balance_transactions.type ro'yxatiga 'withdrawal'
qo'shiladi: to'lov o'tkazilganda shunday yozuv yaratiladi.

Revision ID: d9a3c07be514
Revises: c4d8f1a6b302
"""
from alembic import op
import sqlalchemy as sa

revision = "d9a3c07be514"
down_revision = "c4d8f1a6b302"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "payout_requests",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="pending"),
        sa.Column("card_number", sa.String(length=32), nullable=False),
        sa.Column("card_holder", sa.String(length=100), nullable=True),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("admin_comment", sa.Text(), nullable=True),
        sa.Column("processed_by", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("processed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint("amount > 0", name="check_payout_amount_positive"),
        sa.CheckConstraint("status IN ('pending','paid','rejected')", name="check_payout_status"),
    )
    op.create_index("ix_payout_requests_user_id", "payout_requests", ["user_id"])
    op.create_index("ix_payout_requests_status", "payout_requests", ["status"])

    # 'withdrawal' turini ruxsat etilganlar ro'yxatiga qo'shamiz
    op.drop_constraint("check_transaction_type", "balance_transactions", type_="check")
    op.create_check_constraint(
        "check_transaction_type",
        "balance_transactions",
        "type IN ('topup','payment','income','refund','withdrawal')",
    )


def downgrade():
    op.drop_constraint("check_transaction_type", "balance_transactions", type_="check")
    op.create_check_constraint(
        "check_transaction_type",
        "balance_transactions",
        "type IN ('topup','payment','income','refund')",
    )
    op.drop_index("ix_payout_requests_status", table_name="payout_requests")
    op.drop_index("ix_payout_requests_user_id", table_name="payout_requests")
    op.drop_table("payout_requests")
