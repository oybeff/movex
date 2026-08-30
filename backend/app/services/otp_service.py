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

logger = logging.getLogger(__name__)


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
    
    async def send_otp(self, phone: str) -> dict:
        """
        Send OTP code to phone number
        Args:
            phone: Phone number
        Returns:
            dict with status and message
        """
        try:
            # Clean phone number
            clean_phone = phone.replace("+", "").replace(" ", "").replace("(", "").replace(")", "").replace("-", "")
            
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
            
            # Delete old unverified OTP records for this phone
            self.db.query(OTPVerification).filter(
                OTPVerification.phone == clean_phone,
                OTPVerification.is_verified == False
            ).delete()
            self.db.commit()
            
            # Generate new OTP code
            otp_code = self.generate_otp_code()
            
            # Create OTP record
            otp_record = OTPVerification(
                phone=clean_phone,
                otp_code=otp_code,
                attempts=0,
                is_verified=False,
                is_blocked=False,
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=settings.OTP_EXPIRY_MINUTES)
            )
            self.db.add(otp_record)
            self.db.commit()

            # Send SMS (skip if test mode)
            if settings.OTP_TEST_MODE:
                logger.info(f"TEST MODE: OTP code for {clean_phone}: {otp_code}")
                return {
                    "success": True,
                    "message": f"TEST MODE: Tasdiqlash kodi: {otp_code}",
                    "expires_in": settings.OTP_EXPIRY_MINUTES * 60,
                    "otp_code": otp_code  # Only in test mode
                }

            sms_result = await self.eskiz_service.send_otp(clean_phone, otp_code)

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
            clean_phone = phone.replace("+", "").replace(" ", "").replace("(", "").replace(")", "").replace("-", "")
            
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
        clean_phone = phone.replace("+", "").replace(" ", "").replace("(", "").replace(")", "").replace("-", "")
        
        verified_otp = self.db.query(OTPVerification).filter(
            OTPVerification.phone == clean_phone,
            OTPVerification.is_verified == True
        ).first()
        
        return verified_otp is not None

