"""
Click to'lov tizimi integratsiyasi uchun service
"""
import hashlib
from typing import Optional, Dict, Any
from sqlalchemy.orm import Session
from fastapi import HTTPException
from app.core.config import settings
from app.models.balance import BalanceTransaction
from decimal import Decimal


class ClickService:
    """Click to'lov tizimi bilan ishlash uchun service"""

    # Click credentials — .env dan settings orqali (os.getenv .env ni ko'rmaydi)
    MERCHANT_ID = settings.CLICK_MERCHANT_ID
    SERVICE_ID = settings.CLICK_SERVICE_ID
    SECRET_KEY = settings.CLICK_SECRET_KEY
    MERCHANT_USER_ID = settings.CLICK_MERCHANT_USER_ID
    RETURN_URL = settings.CLICK_RETURN_URL
    
    # Click error codes
    ERROR_CODES = {
        0: "Success",
        -1: "SIGN CHECK FAILED!",
        -2: "Incorrect parameter amount",
        -3: "Action not found",
        -4: "Already paid",
        -5: "User does not exist",
        -6: "Transaction does not exist",
        -7: "Failed to update user",
        -8: "Error in request from click",
        -9: "Transaction cancelled"
    }
    
    @staticmethod
    def generate_sign_string(
        click_trans_id: int,
        service_id: str,
        secret_key: str,
        merchant_trans_id: int,
        amount: float,
        action: int,
        sign_time: str
    ) -> str:
        """
        Click signature yaratish
        
        Format: click_trans_id + service_id + secret_key + merchant_trans_id + amount + action + sign_time
        """
        sign_string = f"{click_trans_id}{service_id}{secret_key}{merchant_trans_id}{amount}{action}{sign_time}"
        return hashlib.md5(sign_string.encode('utf-8')).hexdigest()
    
    @classmethod
    def verify_sign(
        cls,
        click_trans_id: int,
        merchant_trans_id: int,
        amount: float,
        action: int,
        sign_time: str,
        sign_string: str
    ) -> bool:
        """Click'dan kelgan signature'ni tekshirish"""
        expected_sign = cls.generate_sign_string(
            click_trans_id=click_trans_id,
            service_id=cls.SERVICE_ID,
            secret_key=cls.SECRET_KEY,
            merchant_trans_id=merchant_trans_id,
            amount=amount,
            action=action,
            sign_time=sign_time
        )
        return expected_sign == sign_string
    
    @staticmethod
    def get_transaction(db: Session, transaction_id: int) -> Optional[BalanceTransaction]:
        """Transaction'ni olish"""
        return db.query(BalanceTransaction).filter(
            BalanceTransaction.id == transaction_id
        ).first()
    
    @classmethod
    def prepare(
        cls,
        db: Session,
        click_trans_id: int,
        merchant_trans_id: int,
        amount: float,
        action: int,
        sign_time: str,
        sign_string: str,
        error: int = 0,
        error_note: str = "Success"
    ) -> Dict[str, Any]:
        """
        Click Prepare - To'lovni tayyorlash
        
        Bu yerda:
        1. Signature tekshiriladi
        2. Transaction mavjudligi tekshiriladi
        3. Amount to'g'riligi tekshiriladi
        4. Transaction allaqachon to'langanmi tekshiriladi
        """
        
        # 1. Signature tekshirish
        if not cls.verify_sign(click_trans_id, merchant_trans_id, amount, action, sign_time, sign_string):
            return {
                "click_trans_id": click_trans_id,
                "merchant_trans_id": merchant_trans_id,
                "error": -1,
                "error_note": cls.ERROR_CODES[-1]
            }
        
        # 2. Transaction'ni topish
        transaction = cls.get_transaction(db, merchant_trans_id)
        if not transaction:
            return {
                "click_trans_id": click_trans_id,
                "merchant_trans_id": merchant_trans_id,
                "error": -6,
                "error_note": cls.ERROR_CODES[-6]
            }
        
        # 3. Amount tekshirish
        if float(transaction.amount) != amount:
            return {
                "click_trans_id": click_trans_id,
                "merchant_trans_id": merchant_trans_id,
                "error": -2,
                "error_note": cls.ERROR_CODES[-2]
            }
        
        # 4. Allaqachon to'langanmi tekshirish
        if transaction.status == "completed":
            return {
                "click_trans_id": click_trans_id,
                "merchant_trans_id": merchant_trans_id,
                "error": -4,
                "error_note": cls.ERROR_CODES[-4]
            }
        
        # 5. Click trans_id'ni saqlash
        transaction.click_trans_id = click_trans_id
        transaction.click_prepare_id = click_trans_id  # Prepare ID sifatida
        db.commit()
        
        # 6. Success javob
        return {
            "click_trans_id": click_trans_id,
            "merchant_trans_id": merchant_trans_id,
            "merchant_prepare_id": transaction.id,
            "error": 0,
            "error_note": "Success"
        }
    
    @classmethod
    def complete(
        cls,
        db: Session,
        click_trans_id: int,
        merchant_trans_id: int,
        amount: float,
        action: int,
        sign_time: str,
        sign_string: str,
        error: int = 0,
        error_note: str = "Success"
    ) -> Dict[str, Any]:
        """
        Click Complete - To'lovni yakunlash va balansni yangilash
        """
        # Agar Click'dan error kelsa
        if error < 0:
            transaction = cls.get_transaction(db, merchant_trans_id)
            if transaction:
                transaction.status = "failed"
                db.commit()

            return {
                "click_trans_id": click_trans_id,
                "merchant_trans_id": merchant_trans_id,
                "merchant_confirm_id": merchant_trans_id,
                "error": error,
                "error_note": error_note
            }

        # 1. Signature tekshirish
        if not cls.verify_sign(click_trans_id, merchant_trans_id, amount, action, sign_time, sign_string):
            return {
                "click_trans_id": click_trans_id,
                "merchant_trans_id": merchant_trans_id,
                "error": -1,
                "error_note": cls.ERROR_CODES[-1]
            }

        # 2. Transaction'ni topish
        transaction = cls.get_transaction(db, merchant_trans_id)
        if not transaction:
            return {
                "click_trans_id": click_trans_id,
                "merchant_trans_id": merchant_trans_id,
                "error": -6,
                "error_note": cls.ERROR_CODES[-6]
            }

        # 3. Amount tekshirish
        if float(transaction.amount) != amount:
            return {
                "click_trans_id": click_trans_id,
                "merchant_trans_id": merchant_trans_id,
                "error": -2,
                "error_note": cls.ERROR_CODES[-2]
            }

        # 4. Allaqachon to'langanmi tekshirish
        if transaction.status == "completed":
            return {
                "click_trans_id": click_trans_id,
                "merchant_trans_id": merchant_trans_id,
                "merchant_confirm_id": transaction.id,
                "error": -4,
                "error_note": cls.ERROR_CODES[-4]
            }

        # 5. Transaction'ni completed qilish
        transaction.status = "completed"
        transaction.click_trans_id = click_trans_id

        # 6. Balansni yangilash
        from app.services.balance_service import update_balance
        try:
            update_balance(db, transaction.user_id, float(transaction.amount))
        except Exception as e:
            transaction.status = "failed"
            db.commit()
            return {
                "click_trans_id": click_trans_id,
                "merchant_trans_id": merchant_trans_id,
                "error": -7,
                "error_note": f"Failed to update balance: {str(e)}"
            }

        db.commit()

        # 7. Telegram guruhga xabar yuborish
        try:
            from app.services.telegram_service import telegram_service
            from app.models.user import User

            # Foydalanuvchi ma'lumotlarini olish
            user = db.query(User).filter(User.id == transaction.user_id).first()
            if user:
                user_name = user.full_name if hasattr(user, 'full_name') else user.username
                phone_number = transaction.phone_number or "N/A"

                # Telegram notification yuborish
                telegram_service.send_payment_notification(
                    user_name=user_name,
                    phone_number=phone_number,
                    amount=float(transaction.amount),
                    transaction_id=transaction.id,
                    payment_method="Click"
                )
        except Exception as e:
            # Telegram xatosi to'lovga ta'sir qilmasligi kerak
            import logging
            logging.error(f"Failed to send Telegram notification: {str(e)}")

        # 8. Success javob
        return {
            "click_trans_id": click_trans_id,
            "merchant_trans_id": merchant_trans_id,
            "merchant_confirm_id": transaction.id,
            "error": 0,
            "error_note": "Success"
        }

    @classmethod
    def generate_payment_url(cls, transaction_id: int, amount: float) -> str:
        """
        Click to'lov URL'ini yaratish

        Args:
            transaction_id: Internal transaction ID
            amount: To'lov summasi

        Returns:
            Click to'lov URL'i
        """
        base_url = "https://my.click.uz/services/pay"

        params = {
            "service_id": cls.SERVICE_ID,
            "merchant_id": cls.MERCHANT_ID,
            "merchant_user_id": cls.MERCHANT_USER_ID,
            "amount": amount,
            "transaction_param": transaction_id,
            "return_url": cls.RETURN_URL,
        }

        # URL parametrlarini yaratish
        query_string = "&".join([f"{key}={value}" for key, value in params.items()])
        payment_url = f"{base_url}?{query_string}"

        return payment_url

