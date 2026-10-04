# app/core/config.py

from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import PostgresDsn

class Settings(BaseSettings):
    # База данных
    DATABASE_URL: PostgresDsn

    # JWT
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    #: 0 — token muddatsiz. Telefonni PIN kod va barmoq izi himoya qiladi,
    #: shuning uchun har kuni qaytadan kirishning hojati yo'q.
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 0

    # Eskiz SMS Service
    ESKIZ_EMAIL: str
    ESKIZ_PASSWORD: str
    # ------------------------------------------------------------ Telegram
    #
    # Faqat XABARNOMA uchun: to'lov va buyurtmalar haqida guruhga yoziladi.
    # Telegram orqali KIRISH olib tashlandi (04.10.2026) — kod endi faqat
    # SMS bilan ketadi, shuning uchun bot logini, polling va vebhuk
    # sozlamalari ham kerak emas, ular o'chirildi.
    #
    # DIQQAT: bu qiymatlar shu yerda, settings da e'lon qilinishi SHART.
    # telegram_service.py ilgari ularni os.getenv orqali o'qirdi va HECH
    # QACHON topmasdi: .env ni pydantic-settings o'qiydi va qiymatlar
    # os.environ ga tushmaydi.
    TELEGRAM_BOT_TOKEN: str = ""
    TELEGRAM_GROUP_ID: str = ""
    TELEGRAM_GROUP_TOPIC_ID: str = ""

    ESKIZ_API_URL: str = "https://notify.eskiz.uz/api"

    # SMS jo'natuvchi nomi. 4546 — Eskiz ning sinov raqami, u hammada
    # ishlaydi. O'z nomi (masalan MOVEXGO) Eskiz kabinetida tasdiqlangach,
    # shu yerga yoziladi — kodga tegmasdan.
    ESKIZ_SENDER: str = "4546"

    # ------------------------------------------------- Rahmat (Multicard)
    #
    # LOYIHADAGI YAGONA to'lov tizimi. Click va Payme o'z integratsiyalari
    # bilan OLIB TASHLANGAN: Multicard shlyuzining o'z chekaut sahifasida
    # Payme, Click, Uzum, Anorbank, Oson, Alif, Xazna, Beepul va Trastpay
    # allaqachon bor. Ikkinchi marta o'zimiz yozish — bir xil pulni ikki
    # xil yo'l bilan hisoblash, ya'ni ertami-kechmi ikki xil natija.
    #
    # Kalitlar Multicard kabinetidan olinadi. Ular .env da e'lon qilinishi
    # SHART: servis ularni faqat settings orqali o'qiydi, os.getenv .env
    # faylini KO'RMAYDI — aynan shu narsa Click bilan uzoq vaqt sezilmay
    # turgan xato edi.
    RAHMAT_APPLICATION_ID: str = ""
    RAHMAT_SECRET: str = ""
    #: Kassa (store) raqami yoki UUID'i — Multicard beradi
    RAHMAT_STORE_ID: str = ""
    #: true — sinov stendi (dev-mesh), false — jangovar (mesh).
    #: Stend manzili KODDA emas, shu tumblerda: sinovdan jangga o'tish
    #: kalitlarni almashtirish bilan cheklanishi kerak.
    RAHMAT_TEST_MODE: bool = True
    RAHMAT_SANDBOX_URL: str = "https://dev-mesh.multicard.uz"
    RAHMAT_PRODUCTION_URL: str = "https://mesh.multicard.uz"

    #: Multicard callback va webhook yuboradigan OCHIQ manzilimiz, sxemasi
    #: bilan va oxirida "/" siz. Mahalliy ishda bu tunnel manzili
    #: (ngrok/cloudflared), jangda — https://movexgo.uz.
    #: Bo'sh bo'lsa to'lov havolasi yasalmaydi: Multicard to'lov haqida
    #: xabar bera olmasa, pul kartadan yechilib, balans to'lmay qolardi.
    RAHMAT_CALLBACK_BASE_URL: str = ""

    #: To'lovdan keyin odam qaytadigan manzil. Ilova sxemasi — shuning
    #: uchun brauzer ilovaga qaytaradi.
    RAHMAT_RETURN_URL: str = "movexgo://payment/success"
    RAHMAT_RETURN_ERROR_URL: str = "movexgo://payment/failed"

    #: So'rovlar uchun kutish vaqti. Multicard javob bermasa, biz ham
    #: cheksiz kutmasligimiz kerak — uvicorn ishchisi band bo'lib qoladi.
    RAHMAT_TIMEOUT_SECONDS: int = 30

    @property
    def rahmat_base_url(self) -> str:
        """Sinov yoki jangovar stend — tumblerga qarab."""
        url = self.RAHMAT_SANDBOX_URL if self.RAHMAT_TEST_MODE else self.RAHMAT_PRODUCTION_URL
        return url.rstrip("/")

    @property
    def rahmat_configured(self) -> bool:
        """
        Kalitlar ham, ochiq manzil ham bormi.

        Callback manzili ham SHARTLAR ro'yxatida: usiz to'lov o'tadi, lekin
        balans to'lmaydi — foydalanuvchi uchun bu "pulim yo'qoldi" degani.
        """
        return bool(
            self.RAHMAT_APPLICATION_ID
            and self.RAHMAT_SECRET
            and self.RAHMAT_STORE_ID
            and self.RAHMAT_CALLBACK_BASE_URL
        )

    #: Adminka (PHP) bilan backend orasidagi maxfiy so'z.
    #:
    #: Kartaga pul o'tkazish endi Multicard orqali o'tadi, ya'ni buni
    #: bajaradigan kod BITTA bo'lishi kerak — payout_service. Panel shu
    #: so'z bilan backend'ga murojaat qiladi va o'zi pul harakatlantirmaydi.
    #: Bo'sh bo'lsa ichki manzil YO'Q (404): imzosiz manzil orqali
    #: istalgan odam chet kartaga pul jo'natishni buyurgan bo'lardi.
    ADMIN_INTERNAL_SECRET: str = ""

    #: Panel backend'ga qanday manzildan boradi. Bir mashinada turadi,
    #: shuning uchun localhost yetarli.
    INTERNAL_API_URL: str = "http://127.0.0.1:8000"

    # SPLIT_MODE olib tashlandi.
    #
    # U faqat Payme integratsiyasida ishlatilardi: 'on_payment' rejimida
    # to'lov darhol bo'linib, egasiga 90% ketardi. Payme ketgach sozlama
    # HECH QAYERDA o'qilmay qoldi — ya'ni .env dagi qiymat hech narsaga
    # ta'sir qilmasdi. Bunday sozlama eng yomoni: uni o'zgartirgan odam
    # tizim boshqacha ishlaydi deb o'ylaydi.
    #
    # Pul hozir FAQAT escrow bo'yicha yuradi: to'liq summa platformaga
    # tushadi, buyurtma yakunlangach egasiga o'tkaziladi. Multicard'da
    # split bor (splitRequest), kerak bo'lsa alohida ish sifatida
    # qo'shiladi — batafsil docs/backend/PAYMENTS.md.

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
    #: Sinov raqamlari uchun O'ZGARMAS kod. Bo'sh bo'lsa — tasodifiy, ya'ni
    #: har safar yangi. Google Play tekshiruvchisiga o'zgarmas kerak: ular
    #: formada bitta parol so'raydi va uni qayta kiritadi.
    OTP_DEMO_CODE: str = ""

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

