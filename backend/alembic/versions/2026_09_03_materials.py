"""Qurilish materiallari: tovar, rasm, buyurtma

Yangi bo'lim. Ijaradan farqi — tovar SOTIB olinadi: narx birlik uchun,
muddat yo'q, qaytarish yo'q. Shuning uchun alohida jadvallar: orders
aniq texnikaga va sanalarga bog'langan, unga g'ishtni tiqib bo'lmaydi.

Pul harakati esa ijaradagidek: xaridorning balansidan muzlatiladi,
yetkazilgach yechiladi, ulush sotuvchidan ushlanadi.

Tovar moderatsiyadan o'tadi — katalog xaridor birinchi ko'radigan joy.

Revision ID: d8b2f5a91e47
Revises: a7f31c9e04b8
"""
from alembic import op
import sqlalchemy as sa

revision = "d8b2f5a91e47"
down_revision = "a7f31c9e04b8"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "material_products",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("owner_id", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("material_type", sa.String(50), nullable=False),
        sa.Column("title", sa.String(150), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("unit", sa.String(10), nullable=False),
        sa.Column("unit_weight_kg", sa.Numeric(12, 3), nullable=False),
        sa.Column("price_per_unit", sa.Numeric(12, 2), nullable=False),
        sa.Column("min_quantity", sa.Numeric(12, 2), nullable=False, server_default="1"),
        sa.Column("available_quantity", sa.Numeric(12, 2), nullable=True),
        sa.Column("delivery_price_per_km", sa.Numeric(12, 2), nullable=True),
        sa.Column("address", sa.Text(), nullable=True),
        sa.Column("latitude", sa.Numeric(10, 7), nullable=True),
        sa.Column("longitude", sa.Numeric(10, 7), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("moderation_comment", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint("price_per_unit > 0", name="check_material_price"),
        sa.CheckConstraint("unit_weight_kg > 0", name="check_material_unit_weight"),
        sa.CheckConstraint("min_quantity > 0", name="check_material_min_quantity"),
        sa.CheckConstraint("available_quantity IS NULL OR available_quantity >= 0",
                           name="check_material_available"),
        sa.CheckConstraint("unit IN ('piece','bag','tonne','m3')",
                           name="check_material_unit"),
        sa.CheckConstraint("status IN ('pending','approved','rejected')",
                           name="check_material_product_status"),
    )
    op.create_index("ix_material_products_owner_id", "material_products", ["owner_id"])
    op.create_index("ix_material_products_type", "material_products", ["material_type"])
    op.create_index("ix_material_products_status", "material_products", ["status"])
    op.create_index("ix_material_products_created_at", "material_products", ["created_at"])

    op.create_table(
        "material_photos",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("product_id", sa.Integer(),
                  sa.ForeignKey("material_products.id", ondelete="CASCADE"),
                  nullable=False),
        sa.Column("url", sa.String(500), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_material_photos_product_id", "material_photos", ["product_id"])

    op.create_table(
        "material_orders",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("buyer_id", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("seller_id", sa.Integer(),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        # RESTRICT ataylab: buyurtmasi bor tovarni o'chirib bo'lmaydi, aks
        # holda pul harakatining tarixi qayerdan kelganini ko'rsatmay qolardi.
        sa.Column("product_id", sa.Integer(),
                  sa.ForeignKey("material_products.id", ondelete="RESTRICT"),
                  nullable=False),
        sa.Column("quantity", sa.Numeric(12, 2), nullable=False),
        sa.Column("unit", sa.String(10), nullable=False),
        sa.Column("price_per_unit", sa.Numeric(12, 2), nullable=False),
        sa.Column("goods_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("weight_kg", sa.Numeric(12, 2), nullable=False),
        sa.Column("vehicle_code", sa.String(20), nullable=False),
        sa.Column("trips", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("delivery_distance_km", sa.Numeric(10, 2), nullable=True),
        sa.Column("delivery_fee", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("commission", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("total_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("frozen_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("delivery_address", sa.Text(), nullable=True),
        sa.Column("delivery_latitude", sa.Numeric(10, 7), nullable=True),
        sa.Column("delivery_longitude", sa.Numeric(10, 7), nullable=True),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint("quantity > 0", name="check_material_order_quantity"),
        sa.CheckConstraint("total_amount > 0", name="check_material_order_total"),
        sa.CheckConstraint("commission >= 0", name="check_material_order_commission"),
        sa.CheckConstraint("trips > 0", name="check_material_order_trips"),
        sa.CheckConstraint(
            "status IN ('pending','confirmed','delivered','cancelled','rejected')",
            name="check_material_order_status",
        ),
    )
    op.create_index("ix_material_orders_buyer_id", "material_orders", ["buyer_id"])
    op.create_index("ix_material_orders_seller_id", "material_orders", ["seller_id"])
    op.create_index("ix_material_orders_product_id", "material_orders", ["product_id"])
    op.create_index("ix_material_orders_status", "material_orders", ["status"])
    op.create_index("ix_material_orders_created_at", "material_orders", ["created_at"])


def downgrade() -> None:
    op.drop_table("material_orders")
    op.drop_table("material_photos")
    op.drop_table("material_products")
