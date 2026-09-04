"""
Eskiz SMS Service
Eskiz.uz SMS shlyuzi bilan ishlash uchun service
"""
import httpx
from datetime import datetime, timedelta, timezone
from sqlalchemy.orm import Session
from app.core.config import settings
from app.models.eskiz_token import EskizToken
import logging

logger = logging.getLogger(__name__)


class EskizService:
    """Eskiz SMS service for sending SMS messages"""
    
    def __init__(self, db: Session):
        self.db = db
        self.api_url = settings.ESKIZ_API_URL
        self.email = settings.ESKIZ_EMAIL
        self.password = settings.ESKIZ_PASSWORD
    
    async def get_valid_token(self) -> str:
        """
        Get valid access token from database or refresh/create new one
        Returns: Valid access token
        """
        # Try to get existing token from database
        token_record = self.db.query(EskizToken).order_by(EskizToken.created_at.desc()).first()
        
        # Check if token exists and is not expired
        if token_record and token_record.expires_at > datetime.now(timezone.utc):
            logger.info("Using existing valid token")
            return token_record.access_token
        
        # If token expired or doesn't exist, get new token
        logger.info("Token expired or doesn't exist, getting new token")
        return await self._get_new_token()
    
    async def _get_new_token(self) -> str:
        """
        Get new access token from Eskiz API
        Returns: New access token
        """
        try:
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{self.api_url}/auth/login",
                    data={
                        "email": self.email,
                        "password": self.password
                    }
                )
                
                if response.status_code != 200:
                    logger.error(f"Failed to get token: {response.status_code} - {response.text}")
                    raise Exception(f"Failed to authenticate with Eskiz: {response.text}")
                
                data = response.json()
                
                if not data.get("data") or not data["data"].get("token"):
                    logger.error(f"Invalid response from Eskiz: {data}")
                    raise Exception("Invalid response from Eskiz API")
                
                access_token = data["data"]["token"]
                
                # Save token to database (expires in 30 days by default)
                token_record = EskizToken(
                    access_token=access_token,
                    expires_at=datetime.now(timezone.utc) + timedelta(days=29)  # 29 days to be safe
                )
                self.db.add(token_record)
                self.db.commit()
                
                logger.info("Successfully obtained new token from Eskiz")
                return access_token
                
        except httpx.RequestError as e:
            logger.error(f"Network error while getting token: {str(e)}")
            raise Exception(f"Network error: {str(e)}")
        except Exception as e:
            logger.error(f"Error getting token: {str(e)}")
            raise
    
    async def send_sms(self, phone: str, message: str) -> dict:
        """
        Send SMS message to phone number
        Args:
            phone: Phone number in format 998901234567 (without +)
            message: SMS message text
        Returns:
            dict with status and message
        """
        try:
            # Get valid token
            token = await self.get_valid_token()
            
            # Clean phone number (remove + and spaces)
            clean_phone = phone.replace("+", "").replace(" ", "").replace("(", "").replace(")", "").replace("-", "")
            
            # Send SMS
            async with httpx.AsyncClient() as client:
                response = await client.post(
                    f"{self.api_url}/message/sms/send",
                    data={
                        "mobile_phone": clean_phone,
                        "message": message,
                        "from": settings.ESKIZ_SENDER,
                    },
                    headers={
                        "Authorization": f"Bearer {token}"
                    }
                )
                
                # If token is invalid (401), refresh and retry
                if response.status_code == 401:
                    logger.warning("Token invalid, refreshing and retrying...")
                    token = await self._get_new_token()
                    
                    # Retry with new token
                    response = await client.post(
                        f"{self.api_url}/message/sms/send",
                        data={
                            "mobile_phone": clean_phone,
                            "message": message,
                            "from": settings.ESKIZ_SENDER,
                        },
                        headers={
                            "Authorization": f"Bearer {token}"
                        }
                    )
                
                if response.status_code != 200:
                    logger.error(f"Failed to send SMS: {response.status_code} - {response.text}")
                    return {
                        "success": False,
                        "message": f"Failed to send SMS: {response.text}"
                    }
                
                data = response.json()
                logger.info(f"SMS sent successfully to {clean_phone}")
                
                return {
                    "success": True,
                    "message": "SMS sent successfully",
                    "data": data
                }
                
        except httpx.RequestError as e:
            logger.error(f"Network error while sending SMS: {str(e)}")
            return {
                "success": False,
                "message": f"Network error: {str(e)}"
            }
        except Exception as e:
            logger.error(f"Error sending SMS: {str(e)}")
            return {
                "success": False,
                "message": f"Error: {str(e)}"
            }
    
    async def send_otp(self, phone: str, otp_code: str) -> dict:
        """
        Send OTP code to phone number
        Args:
            phone: Phone number
            otp_code: 4-digit OTP code
        Returns:
            dict with status and message
        """
        message = f"Movex GO tasdiqlash kodi: {otp_code}\nKodni hech kimga bermang!"
        return await self.send_sms(phone, message)

