from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.staticfiles import StaticFiles
from app.routes import (
    auth,
    users,
    companies,
    equipment,
    orders,
    requests as request_routes,
    listings,
    materials,
    chats,
    messages,
    reviews,
    payments,
    payouts,
    notifications,
    balance,
    admin,
)
from app.routes import settings as settings_routes
from app.db.base import Base
from app.db.session import engine
from app.core import media
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

# Настройки берутся из settings, а не из os.getenv: .env читает
# pydantic-settings и в os.environ его значения НЕ попадают. Через os.getenv
# всё это работало только при запуске из systemd с EnvironmentFile —
# на этом уже обжигались с ключами Click.
IS_PRODUCTION = (settings.APP_ENV or "development") == "production"

app = FastAPI(
    title="Movex GO API",
    description="Backend для Movex GO - платформа для аренды строительной техники",
    version="1.0.0",
    docs_url=None if IS_PRODUCTION else "/docs",
    redoc_url=None if IS_PRODUCTION else "/redoc",
)

# CORS.
# allow_origins=["*"] вместе с allow_credentials=True — плохое сочетание:
# Starlette в этом случае отражает Origin запроса, то есть разрешает
# кому угодно. Раньше именно так и было по умолчанию.
allowed_origins = [
    origin.strip()
    for origin in (settings.CORS_ORIGINS or "*").split(",")
    if origin.strip()
]
allow_any_origin = "*" in allowed_origins

if IS_PRODUCTION and allow_any_origin:
    raise RuntimeError(
        "CORS_ORIGINS='*' в production. Укажите домены через запятую, "
        "например: https://movex.004.uz,https://bluepos.uz"
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    # Авторизация идёт Bearer-токеном, cookie не используются, поэтому
    # credentials нужны только если список доменов задан явно.
    allow_credentials=not allow_any_origin,
    allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH"],
    allow_headers=["*"],
    expose_headers=["*"],
    max_age=3600,
)

# GZip compression
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Trusted host — защита от подмены заголовка Host.
# Здесь тоже был os.getenv: ALLOWED_HOSTS из .env не читался, а
# "".split(",") даёт [""] — список непустой, поэтому middleware
# включался со списком из одной пустой строки и отбивал ВСЕ запросы.
if IS_PRODUCTION:
    allowed_hosts = [
        host.strip()
        for host in (settings.ALLOWED_HOSTS or "").split(",")
        if host.strip()
    ]
    if allowed_hosts:
        app.add_middleware(TrustedHostMiddleware, allowed_hosts=allowed_hosts)

# Подключаем все роуты
app.include_router(auth.router, prefix="/auth", tags=["Auth"])
app.include_router(users.router, prefix="/users", tags=["Users"])
app.include_router(companies.router, prefix="/companies", tags=["Companies"])
app.include_router(equipment.router, prefix="/equipment", tags=["Equipment"])
app.include_router(orders.router, prefix="/orders", tags=["Orders"])
app.include_router(request_routes.router, prefix="/requests", tags=["Requests"])
app.include_router(listings.router, prefix="/listings", tags=["Listings"])
app.include_router(materials.router, prefix="/materials", tags=["Materials"])
app.include_router(chats.router, prefix="/chats", tags=["Chats"])
app.include_router(messages.router, prefix="/messages", tags=["Messages"])
app.include_router(reviews.router, prefix="/reviews", tags=["Reviews"])
app.include_router(payments.router, prefix="/payments", tags=["Payments"])
app.include_router(payouts.router, prefix="/payouts", tags=["Payouts"])
app.include_router(notifications.router, prefix="/notifications", tags=["Notifications"])
app.include_router(balance.router, prefix="/balance", tags=["Balance"])
app.include_router(settings_routes.router, prefix="/settings", tags=["Settings"])
app.include_router(admin.router, prefix="/admin", tags=["Admin"])

# Раздача загруженных файлов.
#
# Загрузка фото техники писала файл в media/equipment/, а в базу клала ссылку
# /static/equipment/<файл> — и рядом стоял комментарий «настрой статику».
# Её так и не настроили: раздачи не было вообще, и КАЖДОЕ загруженное фото
# было битой ссылкой. Заметно это не сразу — загрузка отвечает 200.
#
# Каталог один на всё, подпапки по разделам: equipment/, listings/.
# Путь и правила задаются в app/core/media.py — там же, где файлы кладутся.
media.folder("equipment")
media.folder("listings")
media.folder("materials")
app.mount("/static", StaticFiles(directory=media.MEDIA_ROOT), name="static")

# Telegramdan yangiliklarni so'rash — kirish shu orqali tasdiqlanadi.
#
# Vebhuk emas, chunki unga ochiq HTTPS manzil kerak, prod esa hali
# ko'tarilmagan. TELEGRAM_POLLING=false bo'lsa hech narsa boshlanmaydi:
# bitta botni ikki joydan so'rab bo'lmaydi, Telegram 409 qaytaradi.
@app.on_event("startup")
async def _start_telegram_polling():
    from app.services import telegram_poller
    telegram_poller.start()


@app.on_event("shutdown")
async def _stop_telegram_polling():
    from app.services import telegram_poller
    await telegram_poller.stop()


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
        "docs": "disabled" if IS_PRODUCTION else "/docs"
    }
