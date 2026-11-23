"""
Кэш справочника типов техники из админки (таблица equipment_catalog).

Зачем кэш: `is_valid_type()` и `type_name()` зовутся из десятка мест без
сессии БД (уведомления, тексты транзакций), а тип, заведённый админом,
должен проходить проверку везде одинаково. Живёт 30 секунд — после правки
в админке новый тип работает максимум через полминуты, в каждом воркере.

Если таблицы ещё нет (миграция не прошла) или база недоступна — кэш
пустой, и всё работает по списку из кода, как раньше.
"""
import logging
import time
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)

TTL_SECONDS = 30

#: Группы экрана «Barcha kategoriyalar» (макет K2). Порядок — порядок чипов.
GROUPS: List[Dict[str, str]] = [
    {"code": "earth", "name_uz": "Yer ishlari", "name_ru": "Земляные работы"},
    {"code": "lifting", "name_uz": "Ko'tarish", "name_ru": "Подъём"},
    {"code": "transport", "name_uz": "Yuk tashish", "name_ru": "Грузоперевозки"},
    {"code": "concrete", "name_uz": "Beton ishlari", "name_ru": "Бетонные работы"},
    {"code": "other", "name_uz": "Boshqa", "name_ru": "Другое"},
]
GROUP_CODES = {g["code"] for g in GROUPS}

_cache: Dict[str, object] = {"at": 0.0, "rows": {}}


def _load() -> Dict[str, dict]:
    from app.db.session import SessionLocal
    from app.models.catalog import EquipmentCatalogType

    db = SessionLocal()
    try:
        rows = db.query(EquipmentCatalogType).all()
        return {
            r.code: {
                "code": r.code,
                "name_uz": r.name_uz,
                "name_ru": r.name_ru,
                "is_enabled": bool(r.is_enabled),
            }
            for r in rows
        }
    finally:
        db.close()


def rows() -> Dict[str, dict]:
    now = time.monotonic()
    if now - float(_cache["at"]) > TTL_SECONDS:
        try:
            _cache["rows"] = _load()
        except Exception as exc:  # таблицы нет / база недоступна
            logger.warning("equipment_catalog not loaded: %s", exc)
            _cache["rows"] = _cache.get("rows") or {}
        _cache["at"] = now
    return _cache["rows"]  # type: ignore[return-value]


def invalidate() -> None:
    _cache["at"] = 0.0


def get(code: Optional[str]) -> Optional[dict]:
    if not code:
        return None
    return rows().get(code)
