"""
OTP Service
OTP kod generatsiya qilish, tekshirish va boshqarish
"""
import random
from datetime import datetime, timedelta, timezone
from sqlalchemy.orm import Session
from app.models.otp_verification import OTPVerification
from app.models.user import User
from app.core.config import settings
from app.services.eskiz_service import EskizService
import logging
from app.utils.phone_utils import to_db_phone

logger = logging.getLogger(__name__)


def _test_phones() -> set:
    """
    Sinov raqamlari ro'yxati sozlamalardan.

    Bu raqamlarga SMS yuborilmaydi va kod javobda qaytadi. Qolganlar
    haqiqiy SMS oladi. Butun bazani test rejimiga o'tkazmaslik uchun:
    avtotestlar va demo-stendga kirish kerak, lekin haqiqiy odamlar
    SMS siz qolmasligi kerak.
    """
    raw = getattr(settings, "OTP_TEST_PHONES", "") or ""
    return {p.strip() for p in raw.split(",") if p.strip()}


def _normalize_lang(value) -> str:
    """Ilovadan kelgan tilni tekshiradi: faqat 'uz'/'ru', qolgani None."""
    if not value:
        return None
    v = str(value).strip().lower()[:2]
    return v if v in ("uz", "ru") else None


class OTPService:
    """OTP verification service"""
    
    def __init__(self, db: Session):
        self.db = db
        self.eskiz_service = EskizService(db)
    
    def generate_otp_code(self) -> str:
        """
        Generate 4-digit OTP code
        Returns: 4-digit string
        """
        return str(random.randint(1000, 9999))
    
    async def send_otp(self, phone: str, request_language: str = None) -> dict:
        """
        Send OTP code to phone number.

        Args:
            phone: Phone number
            request_language: ilovadan kelgan til ('uz'/'ru'). RO'YXATDAN
                O'TISHDA kerak: bunda foydalanuvchi hali bazada yo'q, va til
                faqat ilovadan bilinadi. Mavjud foydalanuvchida esa uning
                saqlangan tili ustuvor.
        Returns:
            dict with status and message
        """
        try:
            # Clean phone number
            clean_phone = to_db_phone(phone)
            
            # Check if phone is blocked
            existing_otp = self.db.query(OTPVerification).filter(
                OTPVerification.phone == clean_phone,
                OTPVerification.is_blocked == True,
                OTPVerification.blocked_until > datetime.now(timezone.utc)
            ).first()

            if existing_otp:
                time_left = existing_otp.blocked_until - datetime.now(timezone.utc)
                hours = int(time_left.total_seconds() // 3600)
                minutes = int((time_left.total_seconds() % 3600) // 60)
                return {
                    "success": False,
                    "message": f"Telefon raqam bloklangan. {hours} soat {minutes} daqiqadan keyin qayta urinib ko'ring.",
                    "blocked_until": existing_otp.blocked_until.isoformat()
                }
            
            now = datetime.now(timezone.utc)
            window_start = now - timedelta(hours=1)

            recent = self.db.query(OTPVerification).filter(
                OTPVerification.phone == clean_phone,
                OTPVerification.is_verified == False,
                OTPVerification.created_at >= window_start,
            ).order_by(OTPVerification.created_at.desc()).all()

            # Yuborish chastotasi. Test rejimida va sinov raqamlari uchun
            # cheklov yo'q — u yerda kod javobning o'zida qaytadi va SMS
            # umuman yuborilmaydi. Sinov raqamlari uchun bu ataylab:
            # Google Play tekshiruvchisi tugmani bir necha marta bosishi
            # mumkin, va "60 soniya kuting" uni to'xtatib qo'yardi.
            if not settings.OTP_TEST_MODE and clean_phone not in _test_phones():
                if recent:
                    since_last = (now - recent[0].created_at).total_seconds()
                    if since_last < settings.OTP_RESEND_COOLDOWN_SECONDS:
                        wait = int(settings.OTP_RESEND_COOLDOWN_SECONDS - since_last)
                        return {
                            "success": False,
                            "message": f"Yangi kodni {wait} soniyadan keyin so'rash mumkin.",
                        }

                if len(recent) >= settings.OTP_MAX_SENDS_PER_HOUR:
                    return {
                        "success": False,
                        "message": "Kod juda ko'p marta so'raldi. Bir soatdan keyin qayta urinib ko'ring.",
                    }

            # Urinishlar soni yangi kodda NOLDAN boshlanmaydi.
            # Ilgari bu yerda eski yozuvlar o'chirilardi va hisoblagich ham
            # birga ketardi: 4 marta xato kiritib, yangi kod so'rab, yana 4
            # marta urinish mumkin edi — ya'ni 4 xonali kodni tanlab olsa
            # bo'lardi. Endi soat davomidagi urinishlar saqlanadi.
            previous_attempts = max((r.attempts for r in recent), default=0)

            # Oynadan chiqib ketgan eski yozuvlarni tozalaymiz
            self.db.query(OTPVerification).filter(
                OTPVerification.phone == clean_phone,
                OTPVerification.is_verified == False,
                OTPVerification.created_at < window_start,
            ).delete()
            self.db.commit()

            # Generate new OTP code
            # Sinov raqamlari uchun kod O'ZGARMAS bo'lishi mumkin: Google
            # Play formasi bitta "parol" so'raydi, har safar yangi kod u
            # yerga sig'maydi. Haqiqiy raqamlarga bu tegmaydi.
            demo_code = (getattr(settings, "OTP_DEMO_CODE", "") or "").strip()
            if demo_code and clean_phone in _test_phones():
                otp_code = demo_code
            else:
                otp_code = self.generate_otp_code()
            
            # Create OTP record
            otp_record = OTPVerification(
                phone=clean_phone,
                otp_code=otp_code,
                # Soat davomidagi xato urinishlar hisobi davom etadi
                attempts=previous_attempts,
                is_verified=False,
                is_blocked=False,
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=settings.OTP_EXPIRY_MINUTES)
            )
            self.db.add(otp_record)
            self.db.commit()

            # SMS yuborish. Ikki holatda o'tkazib yuboriladi: butun
            # server test rejimida bo'lsa, yoki raqam sinov ro'yxatida
            # bo'lsa — ikkinchisi haqiqiy foydalanuvchilarga tegmaydi.
            is_test_phone = clean_phone in _test_phones()
            if settings.OTP_TEST_MODE or is_test_phone:
                logger.info("TEST MODE: OTP code for %s: %s", clean_phone, otp_code)

                # ADMIN uchun kod HECH QACHON javobda qaytmaydi.
                #
                # Test rejimi kodni javobga qo'yadi — ishlab chiqishda bu
                # qulay. Lekin server tashqaridan ochilganda (tunnel, demo,
                # sinov stendi) bu admin hisobini istalgan odamga topshirib
                # qo'yadi: telefon raqami ma'lum, kodni so'rab olib, admin
                # tokenini oladi va hamma foydalanuvchini telefonlari bilan
                # ko'radi hamda o'chira oladi.
                #
                # Admin mobil ilovaga kirmaydi — u PHP paneldan parol bilan
                # ishlaydi, shuning uchun bu hech narsani buzmaydi.
                from app.models.user import User

                is_admin_phone = (
                    self.db.query(User.id)
                    .filter(User.phone == clean_phone, User.role == "admin")
                    .first()
                    is not None
                )
                if is_admin_phone:
                    logger.warning(
                        "Test rejimida admin raqamiga kod so'raldi, javobda "
                        "berilmadi: %s", clean_phone
                    )
                    return {
                        "success": True,
                        "message": "Kod yuborildi",
                        "expires_in": settings.OTP_EXPIRY_MINUTES * 60,
                    }

                # Matn foydalanuvchi tilida. Hisob hali bo'lmasligi mumkin
                # (ro'yxatdan o'tish), u holda til sukut bo'yicha.
                from app.core.messages import t

                lang = (
                    self.db.query(User.language)
                    .filter(User.phone == clean_phone)
                    .scalar()
                )
                return {
                    "success": True,
                    "message": t("test_mode.code", lang, code=otp_code),
                    "expires_in": settings.OTP_EXPIRY_MINUTES * 60,
                    "otp_code": otp_code  # Only in test mode
                }

            # Avval TELEGRAM. U asosiy kanal: bepul, bir zumda va
            # shablon moderatsiyasi yo'q. Bog'lanish bo'lmasa — SMS ga
            # tushamiz, Telegrami yo'q odam ham kira olishi kerak.
            # Import shu yerda: User funksiyaning quyi qismida ham
            # lokal import qilinadi, va Python uni butun funksiya bo'yicha
            # lokal deb hisoblaydi — importdan oldin ishlatilsa yiqiladi.
            from app.models.user import User

            # Mavjud foydalanuvchida — uning saqlangan tili; yo'q bo'lsa
            # (ro'yxatdan o'tish) — ilovadan kelgan til; ikkovi ham yo'q
            # bo'lsa — o'zbekcha.
            saved_language = (
                self.db.query(User.language)
                .filter(User.phone == clean_phone)
                .scalar()
            )
            language = saved_language or _normalize_lang(request_language) or "uz"

            # Kod FAQAT SMS orqali ketadi. Ilgari avval Telegram sinalardi
            # (boti bog'langan odamga kod o'sha yerga borardi), lekin kirish
            # oqimi bitta va oldindan aytib bo'ladigan bo'lishi kerak:
            # raqamni tasdiqlash — SMS, keyin PIN kod. Telegram orqali
            # kirish butunlay olib tashlandi.
            sms_result = await self.eskiz_service.send_otp(clean_phone, otp_code, language)

            if not sms_result["success"]:
                logger.error(f"Failed to send OTP SMS: {sms_result['message']}")
                return {
                    "success": False,
                    "message": "SMS yuborishda xatolik yuz berdi. Iltimos, qayta urinib ko'ring."
                }

            logger.info(f"OTP sent successfully to {clean_phone}")
            return {
                "success": True,
                "message": "Tasdiqlash kodi yuborildi",
                "expires_in": settings.OTP_EXPIRY_MINUTES * 60  # in seconds
            }
            
        except Exception as e:
            logger.error(f"Error sending OTP: {str(e)}")
            return {
                "success": False,
                "message": f"Xatolik yuz berdi: {str(e)}"
            }
    
    def verify_otp(self, phone: str, otp_code: str) -> dict:
        """
        Verify OTP code
        Args:
            phone: Phone number
            otp_code: OTP code to verify
        Returns:
            dict with status and message
        """
        try:
            # Clean phone number
            clean_phone = to_db_phone(phone)
            
            # Check if phone is blocked
            blocked_otp = self.db.query(OTPVerification).filter(
                OTPVerification.phone == clean_phone,
                OTPVerification.is_blocked == True,
                OTPVerification.blocked_until > datetime.now(timezone.utc)
            ).first()

            if blocked_otp:
                time_left = blocked_otp.blocked_until - datetime.now(timezone.utc)
                hours = int(time_left.total_seconds() // 3600)
                minutes = int((time_left.total_seconds() % 3600) // 60)
                return {
                    "success": False,
                    "message": f"Telefon raqam bloklangan. {hours} soat {minutes} daqiqadan keyin qayta urinib ko'ring.",
                    "blocked": True
                }
            
            # Get latest OTP record
            otp_record = self.db.query(OTPVerification).filter(
                OTPVerification.phone == clean_phone,
                OTPVerification.is_verified == False
            ).order_by(OTPVerification.created_at.desc()).first()
            
            if not otp_record:
                return {
                    "success": False,
                    "message": "Tasdiqlash kodi topilmadi. Iltimos, qaytadan kod so'rang."
                }
            
            # Check if OTP expired
            if otp_record.expires_at < datetime.now(timezone.utc):
                return {
                    "success": False,
                    "message": "Tasdiqlash kodi muddati tugagan. Iltimos, qaytadan kod so'rang."
                }
            
            # Verify OTP code
            if otp_record.otp_code != otp_code:
                # Increment attempts
                otp_record.attempts += 1
                
                # Check if max attempts reached
                if otp_record.attempts >= settings.OTP_MAX_ATTEMPTS:
                    otp_record.is_blocked = True
                    otp_record.blocked_until = datetime.now(timezone.utc) + timedelta(hours=settings.OTP_BLOCK_DURATION_HOURS)
                    self.db.commit()
                    
                    return {
                        "success": False,
                        "message": f"Siz {settings.OTP_MAX_ATTEMPTS} marta noto'g'ri kod kiritdingiz. Telefon raqam {settings.OTP_BLOCK_DURATION_HOURS} soatga bloklandi.",
                        "blocked": True
                    }
                
                self.db.commit()
                attempts_left = settings.OTP_MAX_ATTEMPTS - otp_record.attempts
                return {
                    "success": False,
                    "message": f"Noto'g'ri tasdiqlash kodi. Qolgan urinishlar: {attempts_left}",
                    "attempts_left": attempts_left
                }
            
            # OTP is correct
            otp_record.is_verified = True
            self.db.commit()
            
            logger.info(f"OTP verified successfully for {clean_phone}")
            return {
                "success": True,
                "message": "Telefon raqam tasdiqlandi"
            }
            
        except Exception as e:
            logger.error(f"Error verifying OTP: {str(e)}")
            return {
                "success": False,
                "message": f"Xatolik yuz berdi: {str(e)}"
            }
    
    def is_phone_verified(self, phone: str) -> bool:
        """
        Check if phone number is verified
        Args:
            phone: Phone number
        Returns:
            True if verified, False otherwise
        """
        clean_phone = to_db_phone(phone)
        
        verified_otp = self.db.query(OTPVerification).filter(
            OTPVerification.phone == clean_phone,
            OTPVerification.is_verified == True
        ).first()
        
        return verified_otp is not None

