"""Payme Merchant API va to'lovni bo'lish (split) uchun ustunlar

Payme protokoli tranzaksiyaning o'z holatini va vaqtlarini talab qiladi,
shuning uchun balance_transactions ga alohida ustunlar qo'shiladi (Click
ustunlari qanday qo'shilgan bo'lsa, shunday).

users.payme_receiver_id — texnika egasining Payme'dagi qabul qiluvchi
identifikatori. SPLIT_MODE='on_payment' bo'lganda Payme to'lovni shu
identifikator bo'yicha bo'ladi.

Revision ID: c4d8f1a6b302
Revises: b7c1e2a45d90
"""
from alembic import op
import sqlalchemy as sa

revision = "c4d8f1a6b302"
down_revision = "b7c1e2a45d90"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("balance_transactions", sa.Column("payme_transaction_id", sa.String(length=50), nullable=True))
    op.add_column("balance_transactions", sa.Column("payme_state", sa.Integer(), nullable=True))
    op.add_column("balance_transactions", sa.Column("payme_create_time", sa.BigInteger(), nullable=True))
    op.add_column("balance_transactions", sa.Column("payme_perform_time", sa.BigInteger(), nullable=True))
    op.add_column("balance_transactions", sa.Column("payme_cancel_time", sa.BigInteger(), nullable=True))
    op.add_column("balance_transactions", sa.Column("payme_reason", sa.Integer(), nullable=True))
    op.create_index(
        "ix_balance_transactions_payme_transaction_id",
        "balance_transactions",
        ["payme_transaction_id"],
    )

    op.add_column("users", sa.Column("payme_receiver_id", sa.String(length=50), nullable=True))


def downgrade():
    op.drop_column("users", "payme_receiver_id")
    op.drop_index("ix_balance_transactions_payme_transaction_id", table_name="balance_transactions")
    for column in (
        "payme_reason",
        "payme_cancel_time",
        "payme_perform_time",
        "payme_create_time",
        "payme_state",
        "payme_transaction_id",
    ):
        op.drop_column("balance_transactions", column)
