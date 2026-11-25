"""
Проверка водителя (владельца техники) по документам — макет MoveX GO
Driver, страница 00 (R5–R9, V1–V3) и E5 «Hujjatlar tekshirilmoqda».

Обязательные документы — паспорт, права, техпаспорт и фото техники.
Страховка — по желанию. Статус водителя считается из документов, а не
хранится отдельной колонкой: иначе он расходился бы с ними.

Файлы — в backend/private_media/driver_docs, вне публичной media/:
это паспортные данные, и nginx не должен отдавать их по ссылке.
"""
import os
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.core.media import ALLOWED_EXTENSIONS, MAX_UPLOAD_BYTES
from app.models.driver_document import DriverDocument
from app.models.user import User

#: 24.11.2026 (Sherzodbek): har hujjat ikki tomondan, mashina 4 tomondan.
#: Eski turlar (passport … insurance) — avval topshirganlar uchun qoldi.
REQUIRED = ("id_front", "id_back", "license_front", "license_back", "tech_front", "tech_back",
            "car_front", "car_back", "car_left", "car_right")
LEGACY_REQUIRED = ("passport", "driver_license", "tech_passport", "equipment_photo")
KINDS = REQUIRED + LEGACY_REQUIRED + ("insurance",)

PRIVATE_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "private_media",
    "driver_docs",
)


def _path(file_name: str) -> str:
    return os.path.join(PRIVATE_ROOT, file_name)


def status_of(docs: list[DriverDocument]) -> str:
    """
    incomplete — не все обязательные загружены; pending — все загружены,
    ждут проверки; rejected — хоть один обязательный отклонён (V2);
    approved — все обязательные одобрены (V1).
    """
    by_kind = {d.kind: d for d in docs}
    # Yangi ro'yxatgacha tekshiruvdan o'tganlar qayta topshirmaydi:
    # eski to'rttasi tasdiqlangan bo'lsa — ular hisobga olinadi.
    legacy = [by_kind.get(k) for k in LEGACY_REQUIRED]
    if all(d is not None and d.status == "approved" for d in legacy):
        return "approved"
    required = [by_kind.get(k) for k in REQUIRED]
    if any(d is not None and d.status == "rejected" for d in required):
        return "rejected"
    if any(d is None for d in required):
        return "incomplete"
    if all(d.status == "approved" for d in required):
        return "approved"
    return "pending"


#: Muddati bor hujjatlar (Admin P4, H2): prava va texpasport. Muddat
#: old tomonga yoziladi (eski turlar — o'ziga).
EXPIRY_KINDS = ("license_front", "tech_front", "driver_license", "tech_passport")
EXPIRED_MARK = "Muddati o'tgan"


def expire_outdated(db: Session, user_id: int) -> list:
    """
    Muddati o'tgan tasdiqlangan hujjat — «rad etilgan» bo'ladi, sababi
    «Muddati o'tgan … — yangisini yuklang». Ilova buni odatdagi rad etish
    kabi ko'rsatadi (qayta yuklash), yangi holat o'ylab topilmaydi.
    Fon vazifasi yo'q — chaqirilganda (summary, navbat, buyurtma olish).
    """
    from datetime import date

    today = date.today()
    hit = (
        db.query(DriverDocument)
        .filter(DriverDocument.user_id == user_id, DriverDocument.status == "approved",
                DriverDocument.expires_on.isnot(None), DriverDocument.expires_on < today)
        .all()
    )
    for d in hit:
        d.status = "rejected"
        d.reject_reason = f"{EXPIRED_MARK} ({d.expires_on.strftime('%d.%m.%Y')}) — yangisini yuklang"
    if hit:
        db.commit()
        for d in hit:
            try:
                _notify_review(db, d, "approved")
            except Exception:  # noqa: BLE001
                db.rollback()
    return hit


def assert_docs_valid(db: Session, user: User) -> None:
    """
    Buyurtma olishdan oldin: hujjati muddati o'tgan haydovchi — 403.
    Hujjat topshirmagan ega (klient ilovasidan) bu tekshiruvga tushmaydi.
    """
    expire_outdated(db, user.id)
    bad = (
        db.query(DriverDocument)
        .filter(DriverDocument.user_id == user.id, DriverDocument.status == "rejected",
                DriverDocument.reject_reason.like(EXPIRED_MARK + "%"))
        .first()
    )
    if bad is not None:
        raise HTTPException(403, "Hujjatingiz muddati o'tgan — yangisini yuklang, tekshiruvdan so'ng buyurtma olasiz")


def documents(db: Session, user_id: int) -> list[DriverDocument]:
    return db.query(DriverDocument).filter(DriverDocument.user_id == user_id).order_by(DriverDocument.id).all()


def summary(db: Session, user: User) -> dict:
    expire_outdated(db, user.id)
    docs = documents(db, user.id)
    return {
        "status": status_of(docs),
        "required": list(REQUIRED),
        "documents": [
            {
                "kind": d.kind,
                "status": d.status,
                "reject_reason": d.reject_reason,
                "updated_at": d.updated_at,
                "expires_on": d.expires_on,
            }
            for d in docs
        ],
    }


def upload(db: Session, user: User, kind: str, file: UploadFile) -> dict:
    """
    Новое фото документа. Повторная загрузка заменяет старое и снова
    отправляет документ на проверку — так V2 «qayta yuklang» и работает.
    Одобренный документ заменить нельзя: иначе после проверки его
    подменили бы чем угодно.
    """
    if user.role != "owner":
        raise HTTPException(403, "Faqat texnika egalari uchun")
    if kind not in KINDS:
        raise HTTPException(404, "Hujjat turi noma'lum")
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(400, f"Rasm formati qo'llab-quvvatlanmaydi: {ext or '—'}")
    data = file.file.read()
    if not data:
        raise HTTPException(400, "Fayl bo'sh")
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(400, f"Rasm hajmi {MAX_UPLOAD_BYTES // (1024 * 1024)} MB dan oshmasin")

    doc = (
        db.query(DriverDocument)
        .filter(DriverDocument.user_id == user.id, DriverDocument.kind == kind)
        .with_for_update()
        .first()
    )
    if doc is not None and doc.status == "approved":
        raise HTTPException(409, "Hujjat allaqachon tasdiqlangan")

    os.makedirs(PRIVATE_ROOT, exist_ok=True)
    name = f"{uuid.uuid4().hex}{ext}"
    with open(_path(name), "wb") as out:
        out.write(data)

    old_file = None
    if doc is None:
        doc = DriverDocument(user_id=user.id, kind=kind, file_name=name, status="pending")
        db.add(doc)
    else:
        old_file = doc.file_name
        doc.file_name = name
        doc.status = "pending"
        doc.reject_reason = None
        doc.reviewed_at = None
    db.commit()
    if old_file:
        _remove(old_file)
    return summary(db, user)


def _remove(file_name: str) -> None:
    path = _path(file_name)
    if os.path.isfile(path):
        os.remove(path)


def file_of(db: Session, user_id: Optional[int], doc_id: Optional[int] = None, kind: Optional[str] = None) -> str:
    """Путь к фото для отдачи; чужой документ — 404, как несуществующий."""
    q = db.query(DriverDocument)
    if doc_id is not None:
        q = q.filter(DriverDocument.id == doc_id)
    if user_id is not None:
        q = q.filter(DriverDocument.user_id == user_id)
    if kind is not None:
        q = q.filter(DriverDocument.kind == kind)
    doc = q.first()
    if doc is None or not os.path.isfile(_path(doc.file_name)):
        raise HTTPException(404, "Hujjat topilmadi")
    return _path(doc.file_name)


def review(db: Session, doc_id: int, approve: bool, reason: Optional[str] = None,
           expires_on=None, admin_id: Optional[int] = None) -> DriverDocument:
    """
    Админ: одобрить или отклонить документ (с причиной, её увидит водитель).
    Права и техпаспорт — со сроком (expires_on), он уже прошёл — 400.
    """
    from datetime import date

    doc = db.query(DriverDocument).filter(DriverDocument.id == doc_id).with_for_update().first()
    if doc is None:
        raise HTTPException(404, "Hujjat topilmadi")
    if not approve and not (reason or "").strip():
        raise HTTPException(400, "Rad etish sababini yozing")
    if approve and expires_on is not None and expires_on < date.today():
        raise HTTPException(400, "Hujjat muddati o'tgan — tasdiqlab bo'lmaydi")
    if approve and doc.kind in EXPIRY_KINDS:
        doc.expires_on = expires_on
    doc.reviewed_by = admin_id
    before = status_of(documents(db, doc.user_id))  # до изменения: одобрение уведомляем один раз
    doc.status = "approved" if approve else "rejected"
    doc.reject_reason = None if approve else reason.strip()[:500]
    doc.reviewed_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(doc)
    _notify_review(db, doc, before)
    return doc


def _notify_review(db: Session, doc: DriverDocument, before: str) -> None:
    """
    R9 обещает «natija haqida xabar beramiz»: отказ — сразу, с причиной;
    одобрение — одно уведомление, когда одобрен последний обязательный.
    Ошибка уведомления проверку не отменяет (notification_service пишет в лог).
    """
    from app.core.messages import t
    from app.services import notification_service

    lang = notification_service.user_language(db, doc.user_id)
    if doc.status == "rejected":
        notification_service.create_localized(
            db, doc.user_id, "driver_document_rejected",
            "driver_document_rejected.title", "driver_document_rejected.body",
            language=lang, doc=t(f"driver_doc.{doc.kind}", lang), reason=doc.reject_reason or "",
        )
    elif status_of(documents(db, doc.user_id)) == "approved" and before != "approved":
        notification_service.create_localized(
            db, doc.user_id, "driver_approved", "driver_approved.title", "driver_approved.body", language=lang,
        )
        # Sovg'a — tekshiruvdan KEYIN (26.11.2026). Bir marta: muddati o'tib
        # qayta tasdiqlangan hujjat ikkinchi sovg'a bermaydi.
        from app.services import balance_service
        user = db.query(User).filter(User.id == doc.user_id).first()
        if user is not None and not balance_service.has_signup_bonus(db, user.id):
            balance_service.grant_signup_bonus(db, user)


def delete_all(db: Session, user_id: int) -> None:
    """Удаление аккаунта: фото документов стираются с диска (без commit)."""
    for d in documents(db, user_id):
        _remove(d.file_name)
        db.delete(d)
