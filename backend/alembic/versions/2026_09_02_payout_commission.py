"""Pul yechish komissiyasi

Texnika egasi pul yechganda platforma ulushi ushlab qolinadi. Sabab: bir
buyurtmadan atigi 5 000 so'm olinadi, va bu summa to'lov tizimining pul
o'tkazish uchun oladigan foizini qoplamaydi — ya'ni platforma o'z zarariga
ishlardi.

Ikkita ustun qo'shiladi va IKKALASI ham saqlanadi:
  commission     — ushlab qolingan summa
  payout_amount  — kartaga haqiqatan o'tkaziladigan summa

Hisoblab olish ham mumkin edi, lekin sozlama keyin o'zgarsa, eski
arizalarning tarixi yolg'on ko'rsatardi: 5 000 da berilgan ariza 10% bilan
qayta hisoblanib ketardi. Shuning uchun ariza berilgan paytdagi qiymat
o'sha holicha yozib qo'yiladi.

Mavjud arizalar: komissiya 0, kartaga to'liq summa — ular komissiyasiz
davrda berilgan, ularga yangi qoidani orqaga qarab qo'llash noto'g'ri.

Revision ID: c4a8e2f7b913
Revises: e91c4a7b2d36
"""
from alembic import op
import sqlalchemy as sa

revision = "c4a8e2f7b913"
down_revision = "e91c4a7b2d36"
branch_labels = None
depends_on = None


# Sozlamalar buyurtma komissiyasi bilan bir xil tuzilishda: rejim + ikkala
# qiymat. Ikkovi birga ishlamaydi — rejim qaysi biri amal qilishini
# belgilaydi.
DEFAULT_SETTINGS = [
    ("payout_commission_mode", "fixed",
     "Pul yechish komissiyasi rejimi: fixed yoki percent"),
    ("payout_commission_fixed", "5000",
     "Pul yechishdan qat'iy ushlanadigan summa, so'm"),
    ("payout_commission_percent", "10",
     "Pul yechishdan ushlanadigan foiz"),
]


def upgrade() -> None:
    op.add_column(
        "payout_requests",
        sa.Column("commission", sa.Numeric(12, 2), nullable=True),
    )
    op.add_column(
        "payout_requests",
        sa.Column("payout_amount", sa.Numeric(12, 2), nullable=True),
    )

    # Eski arizalar: komissiyasiz, kartaga to'liq summa ketgan.
    op.execute(
        "UPDATE payout_requests "
        "   SET commission = 0, payout_amount = amount "
        " WHERE commission IS NULL"
    )

    op.alter_column("payout_requests", "commission", nullable=False)
    op.alter_column("payout_requests", "payout_amount", nullable=False)

    op.create_check_constraint(
        "check_payout_commission_not_negative",
        "payout_requests",
        "commission >= 0",
    )
    # Kartaga ketadigan summa musbat bo'lishi shart: aks holda ega ariza
    # berib, hech narsa olmasdan balansidan ayrilardi.
    op.create_check_constraint(
        "check_payout_amount_positive_net",
        "payout_requests",
        "payout_amount > 0",
    )

    # app_settings.value — json ustun, oddiy matn yozib bo'lmaydi.
    # CAST(... AS text) yozuvi ataylab: ":value::text" ko'rinishini
    # SQLAlchemy o'z parametri deb o'qib, migratsiyani yiqitadi.
    for key, value, description in DEFAULT_SETTINGS:
        op.execute(
            sa.text(
                "INSERT INTO app_settings (key, value, description) "
                "VALUES (:key, to_jsonb(CAST(:value AS text)), :description) "
                "ON CONFLICT (key) DO NOTHING"
            ).bindparams(key=key, value=value, description=description)
        )


def downgrade() -> None:
    op.drop_constraint("check_payout_amount_positive_net", "payout_requests", type_="check")
    op.drop_constraint("check_payout_commission_not_negative", "payout_requests", type_="check")
    op.drop_column("payout_requests", "payout_amount")
    op.drop_column("payout_requests", "commission")

    for key, _value, _description in DEFAULT_SETTINGS:
        op.execute(
            sa.text("DELETE FROM app_settings WHERE key = :key").bindparams(key=key)
        )
