# app/db/session.py

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from app.core.config import settings

engine = create_engine(
    str(settings.DATABASE_URL),  # <-- обязательно str()
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
