from sqlalchemy.orm import Session
from app.models.equipment import Equipment
from app.schemas.equipment import EquipmentCreate, EquipmentUpdate


def create_equipment(db: Session, equipment: EquipmentCreate):
    """Yangi texnika yaratish"""
    db_equipment = Equipment(**equipment.dict())
    db.add(db_equipment)
    db.commit()
    db.refresh(db_equipment)
    return db_equipment


def get_equipment(db: Session, equipment_id: int):
    """Bitta texnikani olish"""
    return db.query(Equipment).filter(Equipment.id == equipment_id).first()


def get_all_equipment(db: Session, skip: int = 0, limit: int = 100):
    """Barcha texnikalarni olish"""
    return db.query(Equipment).offset(skip).limit(limit).all()


def update_equipment(db: Session, equipment_id: int, equipment: EquipmentUpdate):
    """Texnikani yangilash"""
    db_equipment = db.query(Equipment).filter(Equipment.id == equipment_id).first()
    if not db_equipment:
        return None
    for key, value in equipment.dict(exclude_unset=True).items():
        setattr(db_equipment, key, value)
    db.commit()
    db.refresh(db_equipment)
    return db_equipment


def delete_equipment(db: Session, equipment_id: int):
    """Texnikani o'chirish"""
    db_equipment = db.query(Equipment).filter(Equipment.id == equipment_id).first()
    if db_equipment:
        db.delete(db_equipment)
        db.commit()
    return db_equipment
