"""Haydovchi hujjatlari ikki tomondan, mashina 4 tomondan (Sherzodbek, 24.11.2026).

ID karta, haydovchilik guvohnomasi, texpasport — old va orqa; mashina —
old, orqa, chap, o'ng. Eski turlar qoladi: avval tekshiruvdan o'tganlar
qayta topshirmaydi (driver_service.status_of).

Revision ID: c2e4a7d9f163
Revises: b8d3f1a6c425
"""
from alembic import op

revision = 'c2e4a7d9f163'
down_revision = 'b8d3f1a6c425'
branch_labels = None
depends_on = None

OLD = ('passport', 'driver_license', 'tech_passport', 'equipment_photo', 'insurance')
NEW = OLD + ('id_front', 'id_back', 'license_front', 'license_back', 'tech_front', 'tech_back',
             'car_front', 'car_back', 'car_left', 'car_right')


def _in(values):
    return "kind IN (" + ", ".join(f"'{v}'" for v in values) + ")"


def upgrade():
    op.drop_constraint('check_driver_document_kind', 'driver_documents', type_='check')
    op.create_check_constraint('check_driver_document_kind', 'driver_documents', _in(NEW))


def downgrade():
    op.execute("DELETE FROM driver_documents WHERE NOT " + _in(OLD))
    op.drop_constraint('check_driver_document_kind', 'driver_documents', type_='check')
    op.create_check_constraint('check_driver_document_kind', 'driver_documents', _in(OLD))
