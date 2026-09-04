"""E'lonlarga taklif, yoqtirish va saqlash

Uchta narsa qo'shiladi, hammasi e'lonlar atrofida:

1. listing_offers — ijrochi o'z narxini aytadi. "Olaman" tugmasi joyida
   qoladi: u muallifning byudjetiga rozilik, taklif esa o'z summasi.
   Bitta odamdan bitta taklif — fikrini o'zgartirsa, o'sha qator
   yangilanadi.

2. listing_reactions — yoqtirish va saqlash bitta jadvalda, farqi `kind`
   da. Ikkalasining mantiqi bir xil, alohida jadval kodni ikki marta
   yozishga majbur qilardi.

Sanoq uchun ustun qo'shilmaydi (likes_count va hokazo): e'lonlar kam, va
denormalizatsiya qilingan sanoq ertami-kechmi haqiqatdan ajralib qoladi.
views_count esa avvaldan bor, u tegilmaydi.

Revision ID: a7f31c9e04b8
Revises: c4a8e2f7b913
"""
from alembic import op
import sqlalchemy as sa

revision = "a7f31c9e04b8"
down_revision = "c4a8e2f7b913"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "listing_offers",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("listing_id", sa.Integer(),
                  sa.ForeignKey("listings.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("price", sa.Numeric(12, 2), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("listing_id", "user_id", name="uq_listing_offer_once"),
        sa.CheckConstraint("price > 0", name="check_listing_offer_price"),
        sa.CheckConstraint(
            "status IN ('pending','accepted','declined','withdrawn')",
            name="check_listing_offer_status",
        ),
    )
    op.create_index("ix_listing_offers_listing_id", "listing_offers", ["listing_id"])
    op.create_index("ix_listing_offers_user_id", "listing_offers", ["user_id"])
    op.create_index("ix_listing_offers_status", "listing_offers", ["status"])
    op.create_index("ix_listing_offers_created_at", "listing_offers", ["created_at"])

    op.create_table(
        "listing_reactions",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("listing_id", sa.Integer(),
                  sa.ForeignKey("listings.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("kind", sa.String(10), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("listing_id", "user_id", "kind",
                            name="uq_listing_reaction_once"),
        sa.CheckConstraint("kind IN ('like','save')", name="check_listing_reaction_kind"),
    )
    op.create_index("ix_listing_reactions_listing_id", "listing_reactions", ["listing_id"])
    op.create_index("ix_listing_reactions_user_id", "listing_reactions", ["user_id"])
    op.create_index("ix_listing_reactions_kind", "listing_reactions", ["kind"])
    op.create_index("ix_listing_reactions_created_at", "listing_reactions", ["created_at"])


def downgrade() -> None:
    op.drop_table("listing_reactions")
    op.drop_table("listing_offers")
