# app/db/session.py

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from app.core.config import settings


def sqlalchemy_url(url: str) -> str:
    """
    Драйвер указывается явно. SQLAlchemy 2.1 для голого `postgresql://`
    берёт psycopg 3, а в requirements стоит psycopg2: на чистой установке
    сервер падал при старте. В .env схема остаётся `postgresql://` —
    её же читают pg_dump в backup.sh и restore.sh.
    """
    if url.startswith("postgresql://"):
        return "postgresql+psycopg2://" + url[len("postgresql://"):]
    return url


engine = create_engine(
    sqlalchemy_url(str(settings.DATABASE_URL)),  # <-- обязательно str()
    pool_pre_ping=True
)


SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

# Генератор сессий для зависимостей FastAPI
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
