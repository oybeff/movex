"""notifications.equipment_model + eski sarlavhalardagi kodni tuzatish

Xabarnoma sarlavhasi serverda tayyor matn sifatida saqlanardi va unga
texnika turining KODI tushib qolgan edi: "Yangi buyurtma: backhoe_loader
JCB 3CX". Ikki muammo:

  1. foydalanuvchi kodni ko'radi;
  2. sarlavha bitta tilda qotib qoladi.

Yechim: equipment_model ustuni qo'shiladi va ilova sarlavhani
equipment_type + equipment_model dan o'z tilida yig'adi. Bu migratsiya
qo'shimcha ravishda allaqachon yozilgan sarlavhalardagi kodlarni
o'qiladigan nomga almashtiradi — aks holda eski xabarnomalar kod bilan
qolib ketardi.

Revision ID: c4d1e9f70b32
Revises: f5b7d21c8a40
"""
from alembic import op
import sqlalchemy as sa

revision = "c4d1e9f70b32"
down_revision = "f5b7d21c8a40"
branch_labels = None
depends_on = None

# (kod, o'zbekcha nom) — app/core/equipment_types.py bilan bir xil
TYPE_NAMES = [
    ("backhoe_loader",  "Ekskavator-yuklagich"),
    ("mini_excavator",  "Mini ekskavator"),
    ("excavator",       "Ekskavator"),
    ("front_loader",    "Frontal yuklagich"),
    ("bulldozer",       "Buldozer"),
    ("truck_crane",     "Avtokran"),
    ("manipulator",     "Manipulyator"),
    ("aerial_platform", "Avtovishka"),
    ("dump_truck",      "Samosval"),
    ("concrete_mixer",  "Beton aralashtirgich"),
    ("concrete_pump",   "Betonnasos"),
    ("grader",          "Greyder"),
    ("roller",          "Katok"),
    ("auger_drill",     "Yamobur"),
    ("tow_truck",       "Tral / Evakuator"),
    ("compressor",      "Kompressor"),
    ("other",           "Boshqa texnika"),
]


def upgrade() -> None:
    op.add_column(
        "notifications",
        sa.Column("equipment_model", sa.String(length=120), nullable=True),
    )

    conn = op.get_bind()

    # Mavjud xabarnomalarga texnika modelini buyurtma orqali tiklaymiz.
    conn.execute(sa.text("""
        UPDATE notifications n
           SET equipment_model = e.model
          FROM orders o
          JOIN equipment e ON e.id = o.equipment_id
         WHERE n.order_id = o.id
           AND n.equipment_model IS NULL
    """))

    # Sarlavhadagi kodni nomga almashtiramiz. Uzunroq kodlar oldin
    # kelishi kerak: 'excavator' 'mini_excavator' ichida ham uchraydi.
    for code, name in sorted(TYPE_NAMES, key=lambda t: -len(t[0])):
        conn.execute(
            sa.text("""
                UPDATE notifications
                   SET title = replace(title, :code, :name)
                 WHERE title LIKE :pattern
            """),
            {"code": code, "name": name, "pattern": f"%{code}%"},
        )


def downgrade() -> None:
    op.drop_column("notifications", "equipment_model")
