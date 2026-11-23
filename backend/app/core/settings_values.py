"""Флажки из app_settings, которые читают сразу несколько мест."""
from sqlalchemy.orm import Session


def _raw(db: Session, key: str):
    from app.models.app_settings import AppSettings

    row = db.query(AppSettings).filter(AppSettings.key == key).first()
    return None if row is None else row.value


def materials_enabled(db: Session) -> bool:
    """
    Раздел «Qurilish materiallari» включён. Выключает админ
    (commission.php): плитка на главной и кнопка в объявлениях пропадают,
    заказать нельзя. Настройки нет — включено.
    """
    v = _raw(db, "materials_enabled")
    return v in (None, "") or str(v) not in ("0", "false", "False")
