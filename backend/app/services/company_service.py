from sqlalchemy.orm import Session
from app.models.company import Company
from app.schemas.company import CompanyCreate, CompanyUpdate


def create_company(db: Session, company: CompanyCreate):
    """Yangi kompaniya yaratish"""
    db_company = Company(**company.dict())
    db.add(db_company)
    db.commit()
    db.refresh(db_company)
    return db_company


def get_company(db: Session, company_id: int):
    """Bitta kompaniyani olish"""
    return db.query(Company).filter(Company.id == company_id).first()


def get_companies(db: Session, skip: int = 0, limit: int = 100):
    """Barcha kompaniyalarni olish"""
    return db.query(Company).offset(skip).limit(limit).all()


def update_company(db: Session, company_id: int, company: CompanyUpdate):
    """Kompaniyani yangilash"""
    db_company = db.query(Company).filter(Company.id == company_id).first()
    if not db_company:
        return None
    for key, value in company.dict(exclude_unset=True).items():
        setattr(db_company, key, value)
    db.commit()
    db.refresh(db_company)
    return db_company


def delete_company(db: Session, company_id: int):
    """Kompaniyani o'chirish"""
    db_company = db.query(Company).filter(Company.id == company_id).first()
    if db_company:
        db.delete(db_company)
        db.commit()
    return db_company
