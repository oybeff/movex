"""
Telegram bot orqali xabar yuborish servisi
"""
import os
import requests
from typing import Optional
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


class TelegramService:
    """Telegram bot orqali guruhga xabar yuborish"""
    
    def __init__(self):
        self.bot_token = os.getenv("TELEGRAM_BOT_TOKEN", "")
        self.group_id = os.getenv("TELEGRAM_GROUP_ID", "")
        self.topic_id = os.getenv("TELEGRAM_GROUP_TOPIC_ID", "")
        
        # Base URL
        self.base_url = f"https://api.telegram.org/bot{self.bot_token}"
    
    def send_message(self, text: str, parse_mode: str = "HTML") -> bool:
        """
        Telegram guruhga xabar yuborish
        
        Args:
            text: Yuborilishi kerak bo'lgan xabar
            parse_mode: HTML yoki Markdown
            
        Returns:
            bool: Muvaffaqiyatli yuborilsa True, aks holda False
        """
        if not self.bot_token or not self.group_id:
            logger.warning("Telegram credentials not configured")
            return False
        
        try:
            url = f"{self.base_url}/sendMessage"
            
            payload = {
                "chat_id": self.group_id,
                "text": text,
                "parse_mode": parse_mode,
            }
            
            # Agar topic ID mavjud bo'lsa (supergroup uchun)
            if self.topic_id:
                payload["message_thread_id"] = int(self.topic_id)
            
            response = requests.post(url, json=payload, timeout=10)
            
            if response.status_code == 200:
                logger.info("Telegram message sent successfully")
                return True
            else:
                logger.error(f"Telegram API error: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to send Telegram message: {str(e)}")
            return False
    
    def send_payment_notification(
        self,
        user_name: str,
        phone_number: str,
        amount: float,
        transaction_id: int,
        payment_method: str = "Click"
    ) -> bool:
        """
        To'lov haqida xabar yuborish
        
        Args:
            user_name: Foydalanuvchi ismi
            phone_number: Telefon raqam
            amount: To'lov summasi
            transaction_id: Transaction ID
            payment_method: To'lov usuli
            
        Returns:
            bool: Muvaffaqiyatli yuborilsa True
        """
        # Vaqtni formatlash
        now = datetime.now()
        time_str = now.strftime("%d.%m.%Y %H:%M:%S")
        
        # Summani formatlash (ming ajratgich bilan)
        amount_formatted = f"{amount:,.0f}".replace(",", " ")
        
        # Xabar matni
        message = f"""
💰 <b>Yangi To'lov</b>

👤 <b>Foydalanuvchi:</b> {user_name}
📱 <b>Telefon:</b> <code>{phone_number}</code>
💵 <b>Summa:</b> {amount_formatted} so'm
💳 <b>To'lov usuli:</b> {payment_method}
🆔 <b>Transaction ID:</b> #{transaction_id}
🕐 <b>Vaqt:</b> {time_str}

✅ To'lov muvaffaqiyatli amalga oshirildi!
"""
        
        return self.send_message(message.strip())
    
    def send_payment_failed_notification(
        self,
        user_name: str,
        phone_number: str,
        amount: float,
        transaction_id: int,
        reason: str = "Unknown"
    ) -> bool:
        """
        To'lov muvaffaqiyatsiz bo'lganda xabar yuborish
        """
        now = datetime.now()
        time_str = now.strftime("%d.%m.%Y %H:%M:%S")
        amount_formatted = f"{amount:,.0f}".replace(",", " ")
        
        message = f"""
❌ <b>To'lov Muvaffaqiyatsiz</b>

👤 <b>Foydalanuvchi:</b> {user_name}
📱 <b>Telefon:</b> <code>{phone_number}</code>
💵 <b>Summa:</b> {amount_formatted} so'm
🆔 <b>Transaction ID:</b> #{transaction_id}
🕐 <b>Vaqt:</b> {time_str}
⚠️ <b>Sabab:</b> {reason}
"""
        
        return self.send_message(message.strip())
    
    def test_connection(self) -> bool:
        """
        Telegram bot connection'ni test qilish
        """
        try:
            url = f"{self.base_url}/getMe"
            response = requests.get(url, timeout=10)
            
            if response.status_code == 200:
                data = response.json()
                if data.get("ok"):
                    bot_info = data.get("result", {})
                    logger.info(f"Telegram bot connected: @{bot_info.get('username')}")
                    return True
            
            logger.error(f"Telegram bot connection failed: {response.text}")
            return False
            
        except Exception as e:
            logger.error(f"Telegram connection test failed: {str(e)}")
            return False


# Singleton instance
telegram_service = TelegramService()

