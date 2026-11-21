"""Приложение водителя: причина отказа от быстрого заказа и «Yetib keldim».

- quick_request_declines.reason — почему водитель отказался (макет H4):
  far | low_price | busy | not_my_job | other. Пусто у старых отказов.
- orders.arrived_at — водитель нажал «Yetib keldim» (макет D1 → D2):
  между «выехал» и «начал работу».

Revision ID: a7d3f9c2e815
Revises: e4c7b1a9f023
"""
from alembic import op
import sqlalchemy as sa

revision = "a7d3f9c2e815"
down_revision = "e4c7b1a9f023"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("quick_request_declines", sa.Column("reason", sa.String(20), nullable=True))
    op.create_check_constraint(
        "check_quick_decline_reason",
        "quick_request_declines",
        "reason IS NULL OR reason IN ('far','low_price','busy','not_my_job','other')",
    )
    op.add_column("orders", sa.Column("arrived_at", sa.DateTime(timezone=True), nullable=True))


def downgrade():
    op.drop_column("orders", "arrived_at")
    op.drop_constraint("check_quick_decline_reason", "quick_request_declines", type_="check")
    op.drop_column("quick_request_declines", "reason")
