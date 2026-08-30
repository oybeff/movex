"""Ishlash tezligi uchun indekslar

migrations/add_indexes.sql fayli repozitoriyda yotardi, lekin migratsiyaga
aylanmagan — ya'ni bazada bu indekslarning birortasi ham yo'q edi.

Eng muhimi equipment(owner_id): kirish huquqini tekshirish endi har bir
buyurtma va chat so'rovida "shu texnika kimniki" degan savolni beradi.
Indekssiz bu butun equipment jadvalini skanerlashga aylanadi.

Indekslar yozishni sekinlashtiradi, shuning uchun bu yerda faqat haqiqiy
so'rovlar bo'yicha keraklilari.

Revision ID: f5b7d21c8a40
Revises: e1f2a8c94d67
"""
from alembic import op

revision = "f5b7d21c8a40"
down_revision = "e1f2a8c94d67"
branch_labels = None
depends_on = None

# (nom, jadval, ustunlar, izoh)
INDEXES = [
    # Kirish huquqi: "bu texnika shu foydalanuvchinikimi"
    ("ix_equipment_owner_id", "equipment", ["owner_id"]),
    # Katalog: bo'sh texnikani turi bo'yicha filtrlash
    ("ix_equipment_status", "equipment", ["status"]),
    ("ix_equipment_type", "equipment", ["type"]),
    # O'chirilgan texnika har bir so'rovda chiqarib tashlanadi
    ("ix_equipment_deleted_at", "equipment", ["deleted_at"]),

    # Sana bo'yicha bandlikni tekshirish: equipment_id + status
    ("ix_orders_equipment_status", "orders", ["equipment_id", "status"]),
    ("ix_orders_status", "orders", ["status"]),
    # Buyurtmalar ro'yxati yangisidan eskisiga
    ("ix_orders_user_created", "orders", ["user_id", "created_at"]),

    # Chat buyurtma bo'yicha topiladi
    ("ix_chats_order_id", "chats", ["order_id"]),
    # Xabarlar: chat bo'yicha, vaqt tartibida
    ("ix_messages_chat_sent", "messages", ["chat_id", "sent_at"]),
    ("ix_messages_sender_id", "messages", ["sender_id"]),

    ("ix_reviews_equipment_id", "reviews", ["equipment_id"]),
    ("ix_reviews_user_id", "reviews", ["user_id"]),

    ("ix_payments_order_id", "payments", ["order_id"]),

    # Tranzaksiyalar tarixi
    ("ix_balance_transactions_user_created", "balance_transactions", ["user_id", "created_at"]),
    # Adminkadagi budjet sahifasi sana bo'yicha filtrlaydi
    ("ix_budget_reserves_created_at", "budget_reserves", ["created_at"]),
]


def upgrade():
    for name, table, columns in INDEXES:
        op.create_index(name, table, columns, if_not_exists=True)


def downgrade():
    for name, table, _columns in reversed(INDEXES):
        op.drop_index(name, table_name=table, if_exists=True)
