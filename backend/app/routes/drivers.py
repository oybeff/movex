"""
Проверка водителя по документам (MoveX GO Driver, макет 00).

Водителю: свой статус, загрузка фото документа, просмотр своего фото.
Админке (PHP, X-Admin-Secret): очередь на проверку, фото, одобрить/отклонить.
Фото отдаются только так — в публичной /static их нет.
"""
from typing import Optional

from fastapi import APIRouter, Depends, File, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.internal_auth import require_internal_admin
from app.db.session import get_db
from app.models.driver_document import DriverDocument
from app.models.user import User
from app.routes.auth import get_current_user
from app.services import driver_service

router = APIRouter()


@router.get("/me")
def my_verification(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Статус проверки и документы (без файлов): R5, E5, V1–V3."""
    return driver_service.summary(db, current_user)


@router.post("/me/documents/{kind}")
def upload_document(
    kind: str,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return driver_service.upload(db, current_user, kind, file)


@router.get("/me/documents/{kind}/file")
def my_document_file(kind: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return FileResponse(driver_service.file_of(db, current_user.id, kind=kind), headers={"Cache-Control": "private, no-store"})


# ------------------------------------------------------------- админка

class _ReviewIn(BaseModel):
    approve: bool
    reason: Optional[str] = Field(None, max_length=500)


@router.get("/internal/queue", dependencies=[Depends(require_internal_admin)])
def queue(db: Session = Depends(get_db)):
    """Водители с документами: сначала те, у кого есть непроверенные."""
    rows = (
        db.query(DriverDocument, User)
        .join(User, User.id == DriverDocument.user_id)
        .order_by(DriverDocument.updated_at.desc())
        .all()
    )
    by_user: dict[int, dict] = {}
    for doc, user in rows:
        item = by_user.setdefault(user.id, {
            "user_id": user.id, "full_name": user.full_name, "phone": user.phone, "documents": [],
        })
        item["documents"].append({
            "id": doc.id, "kind": doc.kind, "status": doc.status,
            "reject_reason": doc.reject_reason, "updated_at": doc.updated_at,
        })
    out = []
    for item in by_user.values():
        docs = [d for d, _ in rows if d.user_id == item["user_id"]]
        item["status"] = driver_service.status_of(docs)
        out.append(item)
    out.sort(key=lambda i: (i["status"] != "pending", i["status"] != "rejected"))
    return out


@router.get("/internal/documents/{doc_id}/file", dependencies=[Depends(require_internal_admin)])
def document_file(doc_id: int, db: Session = Depends(get_db)):
    return FileResponse(driver_service.file_of(db, None, doc_id=doc_id), headers={"Cache-Control": "private, no-store"})


@router.post("/internal/documents/{doc_id}/review", dependencies=[Depends(require_internal_admin)])
def review_document(doc_id: int, data: _ReviewIn, db: Session = Depends(get_db)):
    doc = driver_service.review(db, doc_id, data.approve, data.reason)
    return {"id": doc.id, "status": doc.status, "reject_reason": doc.reject_reason}
