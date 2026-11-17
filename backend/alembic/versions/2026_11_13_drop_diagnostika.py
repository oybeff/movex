"""Diagnostika butunlay olib tashlandi: narx sozlamasi va eski buyurtmalar.

Faol (pul muzlatilgan) diagnostika bo'lsa, migratsiya TO'XTAYDI: zayavka
yoki buyurtmani o'chirsak, mijozning frozen_balance i qaytarilmay qolardi.
Avval ularni bekor qilish kerak (ilova yoki adminka orqali).

Revision ID: f2a9c6d1b384
Revises: e1c7a4d95b20
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'f2a9c6d1b384'
down_revision: Union[str, Sequence[str], None] = 'e1c7a4d95b20'
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    active = conn.execute(sa.text("""
        SELECT
          (SELECT count(*) FROM equipment_requests
            WHERE equipment_type = 'diagnostika'
              AND (status = 'open' OR frozen_amount > 0))
          +
          (SELECT count(*) FROM orders o
             JOIN equipment_requests r ON r.order_id = o.id
            WHERE r.equipment_type = 'diagnostika'
              AND o.status NOT IN ('completed', 'cancelled', 'rejected'))
    """)).scalar()
    if active:
        raise RuntimeError(
            f"Faol diagnostika buyurtmalari bor ({active}) — avval bekor qiling, "
            "aks holda muzlatilgan pul mijozga qaytmaydi"
        )

    conn.execute(sa.text("""
        DELETE FROM orders WHERE id IN (
            SELECT order_id FROM equipment_requests
             WHERE equipment_type = 'diagnostika' AND order_id IS NOT NULL)
    """))
    conn.execute(sa.text("DELETE FROM equipment_requests WHERE equipment_type = 'diagnostika'"))
    conn.execute(sa.text("DELETE FROM app_settings WHERE key = 'diagnostika_price_amount'"))


def downgrade() -> None:
    # O'chirilgan ma'lumot qaytmaydi
    pass
