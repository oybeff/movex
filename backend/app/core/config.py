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
    # ------------------------------------------------------------ Telegram
    #
    # Kirish uchun ASOSIY kanal. SMS zaxira bo'lib qoladi: Telegramsiz
    # odam ham kira olishi kerak.
    #
    # DIQQAT: bu qiymatlar shu yerda, settings da e'lon qilinishi SHART.
    # telegram_service.py ilgari ularni os.getenv orqali o'qirdi va HECH
    # QACHON topmasdi: .env ni pydantic-settings o'qiydi va qiymatlar
    # os.environ ga tushmaydi. Click kalitlari bilan aynan shunday
    # bo'lgan — to'lov xabarnomalari jimgina yuborilmay turgan.
    TELEGRAM_BOT_TOKEN: str = ""
    #: Bot logini @ siz — chuqur havola shundan yig'iladi
    TELEGRAM_BOT_USERNAME: str = ""
    TELEGRAM_GROUP_ID: str = ""
    TELEGRAM_GROUP_TOPIC_ID: str = ""

    #: Bot yangiliklarini so'rab turadigan fon vazifasi. Vebhukdan farqi —
    #: ochiq HTTPS manzil kerak emas, ya'ni tunnel o'lsa ham ishlaydi.
    TELEGRAM_POLLING: bool = False

    #: Vebhuk maxfiy so'zi. Bo'sh bo'lsa — /auth/telegram/webhook YO'Q
    #: (404), ya'ni so'rab turish rejimi ishlaydi. To'ldirilgan bo'lsa
    #: manzil ochiladi va HAR BIR so'rov shu so'z bilan tekshiriladi:
    #: aks holda manzilni bilgan har kim soxta yangilik yuborib,
    #: istalgan raqamdan kirishni tasdiqlagan bo'lardi.
    TELEGRAM_WEBHOOK_SECRET: str = ""

    ESKIZ_API_URL: str = "https://notify.eskiz.uz/api"

    # SMS jo'natuvchi nomi. 4546 — Eskiz ning sinov raqami, u hammada
    # ishlaydi. O'z nomi (masalan MOVEXGO) Eskiz kabinetida tasdiqlangach,
    # shu yerga yoziladi — kodga tegmasdan.
    ESKIZ_SENDER: str = "4546"

    # Click to'lov tizimi.
    # Ilgari bu qiymatlar click_service ichida os.getenv orqali o'qilardi, ya'ni
    # .env fayldan KELMASDI (pydantic-settings faylni o'qiydi, lekin os.environ'ga
    # yozmaydi) — Click faqat systemd EnvironmentFile bilan ishga tushganda ishlardi.
    CLICK_MERCHANT_ID: str = ""
    CLICK_SERVICE_ID: str = ""
    CLICK_SECRET_KEY: str = ""
    CLICK_MERCHANT_USER_ID: str = ""
    CLICK_RETURN_URL: str = "movexgo://payment/success"

    @property
    def click_configured(self) -> bool:
        """Click bilan ishlash uchun barcha kerakli kalitlar bormi."""
        return bool(self.CLICK_SERVICE_ID and self.CLICK_SECRET_KEY and self.CLICK_MERCHANT_ID)

    # Payme (Paycom) Merchant API.
    # PAYME_KEY — kassa kaliti, Payme kabinetidan olinadi. Payme bizga
    # murojaat qilganda "Authorization: Basic base64('Paycom:' + PAYME_KEY)"
    # sarlavhasini yuboradi.
    PAYME_MERCHANT_ID: str = ""
    PAYME_KEY: str = ""
    # Payme test rejimida boshqa kalit ishlatiladi
    PAYME_TEST_KEY: str = ""
    PAYME_TEST_MODE: bool = False
    # Payme kabinetida sozlangan hisob maydonining nomi
    PAYME_ACCOUNT_FIELD: str = "transaction_id"
    PAYME_CHECKOUT_URL: str = "https://checkout.paycom.uz"
    PAYME_RETURN_URL: str = "movexgo://payment/success"

    @property
    def payme_active_key(self) -> str:
        """Test rejimida test kaliti, aks holda asosiy kalit."""
        if self.PAYME_TEST_MODE and self.PAYME_TEST_KEY:
            return self.PAYME_TEST_KEY
        return self.PAYME_KEY

    @property
    def payme_configured(self) -> bool:
        return bool(self.PAYME_MERCHANT_ID and self.payme_active_key)

    # To'lovni bo'lish (split).
    #   escrow     — pul to'liq platformaga tushadi, buyurtma yakunlangach
    #                texnika egasiga o'tkaziladi. Mijoz uchun xavfsizroq.
    #   on_payment — Payme to'lovni darhol bo'ladi: egasiga 90%, platformaga 10%.
    #                Pul platformada turmaydi, lekin escrow himoyasi yo'qoladi.
    # Batafsil: docs/backend/PAYMENTS.md
    SPLIT_MODE: str = "escrow"

    # OTP Settings
    # Kodni qayta so'rash oralig'i va soatiga eng ko'p yuborish soni.
    # Ikkalasi ham kerak: kodni cheksiz so'rash mumkin bo'lsa, har safar
    # yangi urinishlar oynasi ochiladi va 4 xonali kodni tanlab olsa
    # bo'ladi. Bundan tashqari har bir SMS pul turadi.
    # OTP_TEST_MODE yoqilganda cheklovlar ishlamaydi.
    OTP_RESEND_COOLDOWN_SECONDS: int = 60
    OTP_MAX_SENDS_PER_HOUR: int = 5

    OTP_EXPIRY_MINUTES: int = 5
    OTP_MAX_ATTEMPTS: int = 5
    OTP_BLOCK_DURATION_HOURS: int = 1
    OTP_TEST_MODE: bool = False  # Set to True to skip SMS sending

    # Sinov raqamlari: vergul bilan, masalan "998901110001,998901110002".
    #
    # Bu raqamlarga SMS YUBORILMAYDI, kod javobda qaytadi — xuddi test
    # rejimidagidek, lekin faqat ular uchun. Qolgan hamma odam haqiqiy SMS
    # oladi.
    #
    # Nega kerak: avtotestlar va demo-stend kirish uchun kodni biladigan
    # yo'lni talab qiladi, lekin butun bazani test rejimiga o'tkazish
    # haqiqiy foydalanuvchilarni SMS siz qoldiradi.
    #
    # ADMIN raqami bu ro'yxatga qo'shilsa ham kod javobda qaytmaydi —
    # tekshiruv quyida, send_otp ichida.
    OTP_TEST_PHONES: str = ""

    # Push-bildirishnomalar (Firebase Cloud Messaging, HTTP v1).
    #
    # FCM_CREDENTIALS_FILE — Firebase konsolidan yuklab olingan xizmat
    # akkaunti kaliti (JSON). Fayl serverda yotadi va git ga TUSHMAYDI.
    # FCM_PROJECT_ID — Firebase loyihasining identifikatori.
    #
    # Ikkalasi bo'sh bo'lsa push umuman yuborilmaydi va hech narsa
    # buzilmaydi: xabarnomalar odatdagidek ilova ichida ko'rinadi.
    # Sozlash tartibi: docs/backend/NOTIFICATIONS.md
    FCM_PROJECT_ID: str | None = None
    FCM_CREDENTIALS_FILE: str | None = None

    @property
    def fcm_configured(self) -> bool:
        return bool(self.FCM_PROJECT_ID and self.FCM_CREDENTIALS_FILE)

    # qo‘shimcha .env maydonlar uchun (xatolik chiqmasligi uchun)
    APP_ENV: str | None = None
    DEBUG: bool | None = None
    CORS_ORIGINS: str | None = None
    # Домены, с которых принимаются запросы в production (заголовок Host).
    # Пусто — проверка не включается.
    ALLOWED_HOSTS: str | None = None

    # pydantic 2.x uchun to‘g‘ri sozlama
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",  # 👈 qo‘shimcha maydonlar xato bermaydi
    )

settings = Settings()

