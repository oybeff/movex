from pydantic import BaseModel
from datetime import datetime

class ChatBase(BaseModel):
    order_id: int

class ChatCreate(ChatBase):
    pass

class ChatRead(ChatBase):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True

class ChatUpdate(BaseModel):
    order_id: int  # или любые поля, которые можно обновлять

    class Config:
        from_attributes = True
