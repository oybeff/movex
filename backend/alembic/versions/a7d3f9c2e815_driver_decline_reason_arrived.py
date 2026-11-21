"""Приложение водителя: причина отказа от быстрого заказа и «Yetib keldim».

- quick_request_declines.reason — почему водитель отказался (макет H4):
  far | low_price | busy | not_my_job | other. Пусто у старых отказов.
- orders.arrived_at — водитель нажал «Yetib keldim» (макет D1 → D2):
  между «выехал» и «начал работу».
- тип уведомления order_arrived — клиенту «Texnika yetib keldi».
  Без него в CHECK INSERT упал бы, а ошибка проглотилась.

Revision ID: a7d3f9c2e815
Revises: e4c7b1a9f023
"""
from alembic import op
import sqlalchemy as sa

revision = "a7d3f9c2e815"
down_revision = "e4c7b1a9f023"
branch_labels = None
depends_on = None


TYPES = (
    "order_created", "order_confirmed", "order_rejected", "order_cancelled",
    "order_completed", "balance_topup", "payout_paid", "payout_rejected", "system",
    "request_created", "request_offer", "request_offer_accepted", "request_offer_rejected",
    "request_cancelled", "listing_taken", "listing_confirmed", "listing_cancelled",
    "listing_done", "quick_request",
    "order_departed", "order_started", "order_finished", "order_delayed",
    "order_extend_requested", "order_extend_approved", "order_extend_declined",
    "listing_offer",
    "material_order", "material_confirmed", "material_cancelled",
    "material_delivered", "material_moderated",
)


def _check(types) -> str:
    return "type IN (" + ",".join(f"'{t}'" for t in types) + ")"


def upgrade():
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications", _check(TYPES + ("order_arrived",)))
    op.add_column("quick_request_declines", sa.Column("reason", sa.String(20), nullable=True))
    op.create_check_constraint(
        "check_quick_decline_reason",
        "quick_request_declines",
        "reason IS NULL OR reason IN ('far','low_price','busy','not_my_job','other')",
    )
    op.add_column("orders", sa.Column("arrived_at", sa.DateTime(timezone=True), nullable=True))


def downgrade():
    op.execute("DELETE FROM notifications WHERE type = 'order_arrived'")
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications", _check(TYPES))
    op.drop_column("orders", "arrived_at")
    op.drop_constraint("check_quick_decline_reason", "quick_request_declines", type_="check")
    op.drop_column("quick_request_declines", "reason")
