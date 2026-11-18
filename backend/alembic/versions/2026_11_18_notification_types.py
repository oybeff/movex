"""Xabarnoma turlari: buyurtma bosqichlari va yo'qolgan turlar

Revision ID: c5e1a7d2f904
Revises: b4c8e2f17a39
Create Date: 2026-11-18

Ikki sabab:

1. Mijoz «Texnika yo'lda», «Ish boshlandi», «Ish yakunlandi — tasdiqlang»,
   «Kechikmoqda» va uzaytirish haqida xabar olmasdi (maket M5). Yangi
   turlar: order_departed, order_started, order_finished, order_delayed,
   order_extend_requested, order_extend_approved, order_extend_declined.

2. Kod yozadigan, lekin CHECK qabul qilmaydigan turlar: listing_offer va
   material_* beshtasi. INSERT yiqilar, xato yutilar edi — xabarnoma
   jimgina yo'qolardi (faqat server jurnalida ko'rinardi).
"""
from typing import Sequence, Union

from alembic import op

revision: str = "c5e1a7d2f904"
down_revision: Union[str, Sequence[str], None] = "b4c8e2f17a39"
branch_labels = None
depends_on = None

OLD = (
    "order_created", "order_confirmed", "order_rejected", "order_cancelled",
    "order_completed", "balance_topup", "payout_paid", "payout_rejected", "system",
    "request_created", "request_offer", "request_offer_accepted", "request_offer_rejected",
    "request_cancelled", "listing_taken", "listing_confirmed", "listing_cancelled",
    "listing_done", "quick_request",
)
ADDED = (
    "order_departed", "order_started", "order_finished", "order_delayed",
    "order_extend_requested", "order_extend_approved", "order_extend_declined",
    "listing_offer",
    "material_order", "material_confirmed", "material_cancelled",
    "material_delivered", "material_moderated",
)


def _check(types) -> str:
    return "type IN (" + ",".join(f"'{t}'" for t in types) + ")"


def upgrade() -> None:
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications", _check(OLD + ADDED))


def downgrade() -> None:
    op.execute(
        "DELETE FROM notifications WHERE type IN (" + ",".join(f"'{t}'" for t in ADDED) + ")"
    )
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint("check_notification_type", "notifications", _check(OLD))
