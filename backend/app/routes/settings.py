from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from app.db.session import get_db
from app.models.app_settings import AppSettings, ContactMethod
from app.schemas.app_settings import (
    AppSettingsCreate,
    AppSettingsRead,
    AppSettingsUpdate,
    ContactMethodCreate,
    ContactMethodRead,
    ContactMethodUpdate,
    TermsAndPrivacyResponse,
    ContactMethodsResponse,
)
from app.routes.auth import get_current_user
from app.models.user import User

router = APIRouter()

# ==================== APP SETTINGS ====================

@router.post("/app-settings/", response_model=AppSettingsRead)
def create_app_setting(
    setting_in: AppSettingsCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Yangi app setting yaratish (faqat admin)"""
    if current_user.role != "admin":
        raise HTTPException(403, "Only admin can create settings")
    
    # Mavjudligini tekshirish
    existing = db.query(AppSettings).filter(AppSettings.key == setting_in.key).first()
    if existing:
        raise HTTPException(400, f"Setting with key '{setting_in.key}' already exists")
    
    new_setting = AppSettings(
        key=setting_in.key,
        value=setting_in.value,
        description=setting_in.description
    )
    db.add(new_setting)
    db.commit()
    db.refresh(new_setting)
    return new_setting


@router.get("/app-settings/", response_model=List[AppSettingsRead])
def list_app_settings(db: Session = Depends(get_db)):
    """Barcha app settings'larni olish"""
    return db.query(AppSettings).all()


@router.get("/app-settings/{key}", response_model=AppSettingsRead)
def get_app_setting(key: str, db: Session = Depends(get_db)):
    """Bitta app setting'ni olish"""
    setting = db.query(AppSettings).filter(AppSettings.key == key).first()
    if not setting:
        raise HTTPException(404, f"Setting with key '{key}' not found")
    return setting


@router.put("/app-settings/{key}", response_model=AppSettingsRead)
def update_app_setting(
    key: str,
    setting_in: AppSettingsUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """App setting'ni yangilash (faqat admin)"""
    if current_user.role != "admin":
        raise HTTPException(403, "Only admin can update settings")
    
    setting = db.query(AppSettings).filter(AppSettings.key == key).first()
    if not setting:
        raise HTTPException(404, f"Setting with key '{key}' not found")
    
    for field, value in setting_in.dict(exclude_unset=True).items():
        setattr(setting, field, value)
    
    db.commit()
    db.refresh(setting)
    return setting


@router.delete("/app-settings/{key}")
def delete_app_setting(
    key: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """App setting'ni o'chirish (faqat admin)"""
    if current_user.role != "admin":
        raise HTTPException(403, "Only admin can delete settings")
    
    setting = db.query(AppSettings).filter(AppSettings.key == key).first()
    if not setting:
        raise HTTPException(404, f"Setting with key '{key}' not found")
    
    db.delete(setting)
    db.commit()
    return {"detail": "Setting deleted"}


# ==================== CONTACT METHODS ====================

@router.post("/contact-methods/", response_model=ContactMethodRead)
def create_contact_method(
    method_in: ContactMethodCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Yangi contact method yaratish (faqat admin)"""
    if current_user.role != "admin":
        raise HTTPException(403, "Only admin can create contact methods")
    
    new_method = ContactMethod(**method_in.dict())
    db.add(new_method)
    db.commit()
    db.refresh(new_method)
    return new_method


@router.get("/contact-methods/", response_model=ContactMethodsResponse)
def list_contact_methods(db: Session = Depends(get_db)):
    """Barcha faol contact methods'larni olish"""
    methods = db.query(ContactMethod).filter(
        ContactMethod.is_active == 1
    ).order_by(ContactMethod.order).all()
    return {"methods": methods}


@router.get("/contact-methods/{method_id}", response_model=ContactMethodRead)
def get_contact_method(method_id: int, db: Session = Depends(get_db)):
    """Bitta contact method'ni olish"""
    method = db.query(ContactMethod).filter(ContactMethod.id == method_id).first()
    if not method:
        raise HTTPException(404, "Contact method not found")
    return method


@router.put("/contact-methods/{method_id}", response_model=ContactMethodRead)
def update_contact_method(
    method_id: int,
    method_in: ContactMethodUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Contact method'ni yangilash (faqat admin)"""
    if current_user.role != "admin":
        raise HTTPException(403, "Only admin can update contact methods")
    
    method = db.query(ContactMethod).filter(ContactMethod.id == method_id).first()
    if not method:
        raise HTTPException(404, "Contact method not found")
    
    for field, value in method_in.dict(exclude_unset=True).items():
        setattr(method, field, value)
    
    db.commit()
    db.refresh(method)
    return method


@router.delete("/contact-methods/{method_id}")
def delete_contact_method(
    method_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Contact method'ni o'chirish (faqat admin)"""
    if current_user.role != "admin":
        raise HTTPException(403, "Only admin can delete contact methods")
    
    method = db.query(ContactMethod).filter(ContactMethod.id == method_id).first()
    if not method:
        raise HTTPException(404, "Contact method not found")
    
    db.delete(method)
    db.commit()
    return {"detail": "Contact method deleted"}


# ==================== TERMS AND PRIVACY ====================

@router.get("/terms-and-privacy/", response_model=TermsAndPrivacyResponse)
def get_terms_and_privacy(db: Session = Depends(get_db)):
    """Foydalanish shartlari va Maxfiylik siyosatini olish"""
    terms_uz = db.query(AppSettings).filter(AppSettings.key == "terms_uz").first()
    terms_ru = db.query(AppSettings).filter(AppSettings.key == "terms_ru").first()
    privacy_uz = db.query(AppSettings).filter(AppSettings.key == "privacy_uz").first()
    privacy_ru = db.query(AppSettings).filter(AppSettings.key == "privacy_ru").first()
    
    return {
        "terms_uz": terms_uz.value if terms_uz else None,
        "terms_ru": terms_ru.value if terms_ru else None,
        "privacy_uz": privacy_uz.value if privacy_uz else None,
        "privacy_ru": privacy_ru.value if privacy_ru else None,
    }


# Matn hali yuklanmagan bo'lsa ko'rsatiladigan zaxira javob
PLACEHOLDER_TERMS = {
    "uz": "Foydalanish shartlari hali yuklanmagan.",
    "ru": "Условия использования пока не загружены.",
}
PLACEHOLDER_PRIVACY = {
    "uz": "Maxfiylik siyosati hali yuklanmagan.",
    "ru": "Политика конфиденциальности пока не загружена.",
}


@router.get("/terms/{lang}")
def get_terms(lang: str, db: Session = Depends(get_db)):
    """Foydalanish shartlarini olish (uz yoki ru)"""
    if lang not in ["uz", "ru"]:
        raise HTTPException(400, "Language must be 'uz' or 'ru'")
    
    key = f"terms_{lang}"
    setting = db.query(AppSettings).filter(AppSettings.key == key).first()
    
    if not setting or not setting.value:
        # Zaxira matn ham foydalanuvchi tilida bo'lishi kerak: ilgari
        # ru so'ralganda ham o'zbekcha matn qaytardi
        return {"content": PLACEHOLDER_TERMS[lang]}
    
    return {"content": setting.value}


@router.get("/privacy/{lang}")
def get_privacy(lang: str, db: Session = Depends(get_db)):
    """Maxfiylik siyosatini olish (uz yoki ru)"""
    if lang not in ["uz", "ru"]:
        raise HTTPException(400, "Language must be 'uz' or 'ru'")
    
    key = f"privacy_{lang}"
    setting = db.query(AppSettings).filter(AppSettings.key == key).first()
    
    if not setting or not setting.value:
        return {"content": PLACEHOLDER_PRIVACY[lang]}
    
    return {"content": setting.value}

