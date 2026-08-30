import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from app.routes import (
    auth,
    users,
    companies,
    equipment,
    orders,
    chats,
    messages,
    reviews,
    payments,
    payme,
    payouts,
    notifications,
    balance,
    admin,
)
from app.routes import settings as settings_routes
from app.db.base import Base
from app.db.session import engine
from app.core.config import settings
# Import all models to register them with Base
from app.models import (
    User,
    Company,
    Equipment,
    Order,
    Chat,
    Message,
    Review,
    Payment,
    AppSettings,
    ContactMethod,
)
from app.models.balance import Balance, BalanceTransaction

# СХЕМА ЗДЕСЬ НЕ СОЗДАЁТСЯ.
#
# Раньше на старте вызывался Base.metadata.create_all(bind=engine). Из-за
# этого база создавалась мимо Alembic, и `alembic upgrade head` на чистой
# базе падал: миграции меняли таблицы, которых ни одна миграция не создаёт.
# Развернуться по документации из репозитория было невозможно.
#
# Теперь источник правды один — миграции:
#   первая установка:  python scripts/init_db.py
#   обновление:        alembic upgrade head

app = FastAPI(
    title="Movex GO API",
    description="Backend для Movex GO - платформа для аренды строительной техники",
    version="1.0.0",
    docs_url="/docs" if os.getenv("APP_ENV", "development") != "production" else None,
    redoc_url="/redoc" if os.getenv("APP_ENV", "development") != "production" else None,
)

# CORS middleware - настройка для production
allowed_origins = os.getenv("CORS_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH"],
    allow_headers=["*"],
    expose_headers=["*"],
    max_age=3600,
)

# GZip compression
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Trusted host middleware (для production)
if os.getenv("APP_ENV") == "production":
    allowed_hosts = os.getenv("ALLOWED_HOSTS", "").split(",")
    if allowed_hosts:
        app.add_middleware(TrustedHostMiddleware, allowed_hosts=allowed_hosts)

# Подключаем все роуты
app.include_router(auth.router, prefix="/auth", tags=["Auth"])
app.include_router(users.router, prefix="/users", tags=["Users"])
app.include_router(companies.router, prefix="/companies", tags=["Companies"])
app.include_router(equipment.router, prefix="/equipment", tags=["Equipment"])
app.include_router(orders.router, prefix="/orders", tags=["Orders"])
app.include_router(chats.router, prefix="/chats", tags=["Chats"])
app.include_router(messages.router, prefix="/messages", tags=["Messages"])
app.include_router(reviews.router, prefix="/reviews", tags=["Reviews"])
app.include_router(payments.router, prefix="/payments", tags=["Payments"])
# Payme Merchant API — Payme kabinetida ko'rsatiladigan manzil: /payments/payme
app.include_router(payme.router, prefix="/payments", tags=["Payme"])
app.include_router(payouts.router, prefix="/payouts", tags=["Payouts"])
app.include_router(notifications.router, prefix="/notifications", tags=["Notifications"])
app.include_router(balance.router, prefix="/balance", tags=["Balance"])
app.include_router(settings_routes.router, prefix="/settings", tags=["Settings"])
app.include_router(admin.router, prefix="/admin", tags=["Admin"])

# Health check endpoint
@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "service": "Movex GO API",
        "version": "1.0.0"
    }

# Корневая страница
@app.get("/")
def root():
    return {
        "message": "Welcome to Movex GO API",
        "version": "1.0.0",
        "docs": "/docs" if os.getenv("APP_ENV", "development") != "production" else "disabled"
    }
