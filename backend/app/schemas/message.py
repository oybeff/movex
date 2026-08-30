from pydantic import BaseModel
from datetime import datetime

# Общая схема сообщения
class MessageBase(BaseModel):
    message_text: str

# Схема для создания
class MessageCreate(MessageBase):
    chat_id: int  # к какому чату относится

# Схема для обновления
class MessageUpdate(BaseModel):
    message_text: str | None = None  # необязательное поле, чтобы можно было частично обновлять

# Схема для вывода
class Message(MessageBase):
    id: int
    chat_id: int
    sender_id: int
    sent_at: datetime

    class Config:
        from_attributes = True
