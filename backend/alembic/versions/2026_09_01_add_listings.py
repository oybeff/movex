"""E'lonlar taxtasi va foydalanuvchini bloklash

Ikkita mustaqil o'zgarish, bitta migratsiyada — ikkalasi ham shu ish
doirasida so'ralgan.

1. listings / listing_photos — mijozning erkin matnli e'loni. Zayavkadan
   farqi: ma'lumotnomaga bog'lanmagan, savdo yo'q, egasi "olaman" deydi va
   mijoz tasdiqlaydi.

2. users.is_blocked / is_frozen — adminka uchun. Bloklangan kira olmaydi,
   muzlatilgan kiradi va ko'radi, lekin buyurtma bera olmaydi, taklif
   yubora olmaydi va pul yecha olmaydi.

Revision ID: e91c4a7b2d36
Revises: d7e3a9b41c68
"""
from alembic import op
import sqlalchemy as sa

revision = "e91c4a7b2d36"
down_revision = "d7e3a9b41c68"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "listings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("client_id", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("title", sa.String(120), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("equipment_type", sa.String(50), nullable=True),
        sa.Column("budget", sa.Numeric(12, 2), nullable=True),
        sa.Column("address", sa.Text(), nullable=True),
        sa.Column("latitude", sa.Numeric(10, 7), nullable=True),
        sa.Column("longitude", sa.Numeric(10, 7), nullable=True),
        sa.Column("needed_from", sa.Date(), nullable=True),
        sa.Column("needed_to", sa.Date(), nullable=True),
        sa.Column("contact_phone", sa.String(20), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="open"),
        sa.Column("taken_by", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("taken_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("views_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint(
            "status IN ('open','taken','confirmed','done','cancelled','expired')",
            name="check_listing_status"),
        sa.CheckConstraint("budget IS NULL OR budget > 0", name="check_listing_budget"),
        sa.CheckConstraint(
            "needed_to IS NULL OR needed_from IS NULL OR needed_to >= needed_from",
            name="check_listing_dates"),
        sa.CheckConstraint("views_count >= 0", name="check_listing_views"),
    )
    op.create_index("ix_listings_client_id", "listings", ["client_id"])
    op.create_index("ix_listings_status", "listings", ["status"])
    op.create_index("ix_listings_taken_by", "listings", ["taken_by"])
    op.create_index("ix_listings_created_at", "listings", ["created_at"])
    op.create_index("ix_listings_expires_at", "listings", ["expires_at"])
    op.create_index("ix_listings_equipment_type", "listings", ["equipment_type"])
    # Egaga ko'rsatiladigan lenta aynan shu ikki ustun bo'yicha tanlanadi
    op.create_index("ix_listings_open_feed", "listings", ["status", "created_at"])

    op.create_table(
        "listing_photos",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("listing_id", sa.Integer(),
                  sa.ForeignKey("listings.id", ondelete="CASCADE"), nullable=False),
        sa.Column("url", sa.String(500), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_listing_photos_listing_id", "listing_photos", ["listing_id"])

    # --- bloklash va muzlatish ---
    op.add_column("users", sa.Column("is_blocked", sa.Boolean(), nullable=False,
                                     server_default=sa.false()))
    op.add_column("users", sa.Column("is_frozen", sa.Boolean(), nullable=False,
                                     server_default=sa.false()))
    op.add_column("users", sa.Column("blocked_reason", sa.Text(), nullable=True))
    op.add_column("users", sa.Column("last_login_at", sa.DateTime(timezone=True),
                                     nullable=True))
    op.create_index("ix_users_is_blocked", "users", ["is_blocked"])

    # Yangi xabarnoma turlari
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint(
        "check_notification_type", "notifications",
        "type IN ('order_created','order_confirmed','order_rejected','order_cancelled',"
        "'order_completed','balance_topup','payout_paid','payout_rejected','system',"
        "'request_created','request_offer','request_offer_accepted','request_offer_rejected',"
        "'request_cancelled',"
        "'listing_taken','listing_confirmed','listing_cancelled','listing_done')",
    )


def downgrade() -> None:
    op.drop_constraint("check_notification_type", "notifications", type_="check")
    op.create_check_constraint(
        "check_notification_type", "notifications",
        "type IN ('order_created','order_confirmed','order_rejected','order_cancelled',"
        "'order_completed','balance_topup','payout_paid','payout_rejected','system',"
        "'request_created','request_offer','request_offer_accepted','request_offer_rejected',"
        "'request_cancelled')",
    )
    op.drop_column("users", "last_login_at")
    op.drop_column("users", "blocked_reason")
    op.drop_column("users", "is_frozen")
    op.drop_column("users", "is_blocked")
    op.drop_table("listing_photos")
    op.drop_table("listings")
