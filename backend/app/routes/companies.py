from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from app.db.session import get_db
from app.models.company import Company
from app.schemas.company import CompanyCreate, CompanyRead, CompanyUpdate
from app.routes.auth import get_current_user
from app.core.roles import role_checker

router = APIRouter()

@router.post("/", response_model=CompanyRead)
def create_company(
    company_in: CompanyCreate, 
    db: Session = Depends(get_db), 
    current_user = Depends(role_checker(["owner","admin"]))):
    company = Company(**company_in.dict())
    db.add(company)
    db.commit()
    db.refresh(company)
    return company

@router.get("/", response_model=List[CompanyRead])
def list_companies(db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    return db.query(Company).all()

@router.get("/{company_id}", response_model=CompanyRead)
def get_company(company_id: int, db: Session = Depends(get_db), current_user = Depends(get_current_user)):
    company = db.query(Company).filter(Company.id==company_id).first()
    if not company:
        raise HTTPException(404, "Company not found")
    return company

@router.put("/{company_id}", response_model=CompanyRead)
def update_company(
    company_id: int, 
    company_in: CompanyUpdate, 
    db: Session = Depends(get_db), 
    current_user = Depends(role_checker(["owner","admin"]))):
    company = db.query(Company).filter(Company.id==company_id).first()
    if not company:
        raise HTTPException(404, "Company not found")
    for field, value in company_in.dict(exclude_unset=True).items():
        setattr(company, field, value)
    db.commit()
    db.refresh(company)
    return company

@router.delete("/{company_id}")
def delete_company(
    company_id: int, 
    db: Session = Depends(get_db), 
    current_user = Depends(role_checker(["owner","admin"]))):
    company = db.query(Company).filter(Company.id==company_id).first()
    if not company:
        raise HTTPException(404, "Company not found")
    db.delete(company)
    db.commit()
    return {"detail": "Company deleted"}
