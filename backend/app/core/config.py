# app/core/config.py

from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import PostgresDsn

class Settings(BaseSettings):
    # База данных
    DATABASE_URL: PostgresDsn

    # JWT
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24  # 1 день

    # Eskiz SMS Service
    ESKIZ_EMAIL: str
    ESKIZ_PASSWORD: str
    ESKIZ_API_URL: str = "https://notify.eskiz.uz/api"

    # OTP Settings
    OTP_EXPIRY_MINUTES: int = 5
    OTP_MAX_ATTEMPTS: int = 5
    OTP_BLOCK_DURATION_HOURS: int = 1
    OTP_TEST_MODE: bool = False  # Set to True to skip SMS sending

    # qo‘shimcha .env maydonlar uchun (xatolik chiqmasligi uchun)
    APP_ENV: str | None = None
    DEBUG: bool | None = None
    CORS_ORIGINS: str | None = None

    # pydantic 2.x uchun to‘g‘ri sozlama
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",  # 👈 qo‘shimcha maydonlar xato bermaydi
    )

settings = Settings()

