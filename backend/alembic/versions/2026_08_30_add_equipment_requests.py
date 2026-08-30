"""Zayavkalar, takliflar va qidiruv radiusi

Katalogga qo'shimcha ikkinchi yo'l: mijoz aniq mashinani emas, TURNI
so'raydi, radiusdagi egalar o'z narxi bilan javob beradi, mijoz bittasini
tanlaydi. Tanlangandan keyin odatdagi buyurtma yaratiladi — pul harakati
o'zgarmaydi.

Radius users jadvalida: egaga zayavka xabarlarini, mijozga esa katalogni
filtrlash uchun kerak.

Revision ID: a8f2c31d5e07
Revises: c4d1e9f70b32
"""
from alembic import op
import sqlalchemy as sa

revision = "a8f2c31d5e07"
down_revision = "c4d1e9f70b32"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # --- qidiruv radiusi -------------------------------------------------
    op.add_column("users", sa.Column("search_latitude", sa.Numeric(10, 7), nullable=True))
    op.add_column("users", sa.Column("search_longitude", sa.Numeric(10, 7), nullable=True))
    op.add_column(
        "users",
        sa.Column("search_radius_km", sa.Integer(), nullable=False, server_default="100"),
    )
    op.create_check_constraint(
        "check_search_radius", "users", "search_radius_km > 0 AND search_radius_km <= 1000"
    )

    # --- zayavkalar ------------------------------------------------------
    op.create_table(
        "equipment_requests",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "client_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("equipment_type", sa.String(50), nullable=False),
        sa.Column("start_date", sa.Date(), nullable=False),
        sa.Column("end_date", sa.Date(), nullable=False),
        sa.Column("delivery_latitude", sa.String(50), nullable=False),
        sa.Column("delivery_longitude", sa.String(50), nullable=False),
        sa.Column("delivery_address", sa.Text(), nullable=True),
        sa.Column("budget", sa.Numeric(12, 2), nullable=True),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="open"),
        sa.Column("selected_offer_id", sa.Integer(), nullable=True),
        sa.Column(
            "order_id", sa.Integer(), sa.ForeignKey("orders.id", ondelete="SET NULL"), nullable=True
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint(
            "status IN ('open','assigned','cancelled','expired')", name="check_request_status"
        ),
        sa.CheckConstraint("end_date >= start_date", name="check_request_dates"),
        sa.CheckConstraint("budget IS NULL OR budget > 0", name="check_request_budget"),
    )
    op.create_index("ix_equipment_requests_client_id", "equipment_requests", ["client_id"])
    op.create_index("ix_equipment_requests_status", "equipment_requests", ["status"])
    op.create_index("ix_equipment_requests_created_at", "equipment_requests", ["created_at"])
    op.create_index("ix_equipment_requests_expires_at", "equipment_requests", ["expires_at"])
    # Egaga ko'rsatiladigan ro'yxat aynan shu ikki ustun bo'yicha tanlanadi
    op.create_index(
        "ix_equipment_requests_open_by_type",
        "equipment_requests",
        ["status", "equipment_type"],
    )

    # --- takliflar -------------------------------------------------------
    op.create_table(
        "request_offers",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "request_id",
            sa.Integer(),
            sa.ForeignKey("equipment_requests.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "owner_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "equipment_id",
            sa.Integer(),
            sa.ForeignKey("equipment.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("price_per_day", sa.Numeric(12, 2), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("request_id", "equipment_id", name="uq_offer_request_equipment"),
        sa.CheckConstraint(
            "status IN ('pending','accepted','rejected','withdrawn')", name="check_offer_status"
        ),
        sa.CheckConstraint("price_per_day > 0", name="check_offer_price"),
    )
    op.create_index("ix_request_offers_request_id", "request_offers", ["request_id"])
    op.create_index("ix_request_offers_owner_id", "request_offers", ["owner_id"])
    op.create_index("ix_request_offers_status", "request_offers", ["status"])
    op.create_index("ix_request_offers_created_at", "request_offers", ["created_at"])

    # --- yangi xabarnoma turlari ----------------------------------------
    # Cheklovni qayta yozamiz: ENUM emas, CHECK bo'lgani uchun almashtirish
    # kerak.
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint(
        "check_notification_type",
        "notifications",
        "type IN ('order_created','order_confirmed','order_rejected','order_cancelled',"
        "'order_completed','balance_topup','payout_paid','payout_rejected','system',"
        "'request_created','request_offer','request_offer_accepted','request_offer_rejected',"
        "'request_cancelled')",
    )


def downgrade() -> None:
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint(
        "check_notification_type",
        "notifications",
        "type IN ('order_created','order_confirmed','order_rejected','order_cancelled',"
        "'order_completed','balance_topup','payout_paid','payout_rejected','system')",
    )
    op.drop_table("request_offers")
    op.drop_table("equipment_requests")
    op.drop_constraint("check_search_radius", "users", type_="check")
    op.drop_column("users", "search_radius_km")
    op.drop_column("users", "search_longitude")
    op.drop_column("users", "search_latitude")
