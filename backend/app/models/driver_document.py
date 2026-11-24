"""
Документы водителя (владельца техники) — проверка перед выходом на линию.

Макет MoveX GO Driver, страница 00 (R5–R9, V1–V3): водитель фотографирует
паспорт, права, техпаспорт и технику, админ проверяет каждый документ.

Фото лежат НЕ в публичной media/ (её nginx отдаёт как /static), а в
backend/private_media/driver_docs: это паспортные данные. Отдаются
только самому водителю и админке через X-Admin-Secret.
"""
from sqlalchemy import CheckConstraint, Column, Date, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.sql import func

from app.db.base import Base


class DriverDocument(Base):
    __tablename__ = "driver_documents"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    # passport | driver_license | tech_passport | equipment_photo | insurance
    kind = Column(String(20), nullable=False)
    # Имя файла в private_media/driver_docs — задаёт сервер, не клиент
    file_name = Column(String(80), nullable=False)
    # pending — ждёт проверки, approved, rejected (+ reject_reason)
    status = Column(String(10), nullable=False, default="pending", server_default="pending")
    reject_reason = Column(Text, nullable=True)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)
    #: Prava va texpasport muddati (admin tekshiruvda kiritadi). O'tgan —
    #: haydovchi buyurtma ololmaydi.
    expires_on = Column(Date, nullable=True)
    reviewed_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        UniqueConstraint("user_id", "kind", name="uq_driver_document_kind"),
        CheckConstraint(
            "kind IN ('passport','driver_license','tech_passport','equipment_photo','insurance',"
            "'id_front','id_back','license_front','license_back','tech_front','tech_back',"
            "'car_front','car_back','car_left','car_right')",
            name="check_driver_document_kind",
        ),
        CheckConstraint("status IN ('pending','approved','rejected')", name="check_driver_document_status"),
    )
