from sqlalchemy.orm import Session
from app.models.chat import Chat
from app.schemas.chat import ChatCreate, ChatUpdate


def create_chat(db: Session, chat: ChatCreate, user_id: int = None):
    """Yangi chat yaratish"""
    # Avval shu order_id uchun chat borligini tekshirish
    existing_chat = db.query(Chat).filter(Chat.order_id == chat.order_id).first()
    if existing_chat:
        return existing_chat

    db_chat = Chat(**chat.dict())
    db.add(db_chat)
    db.commit()
    db.refresh(db_chat)
    return db_chat


def get_chat(db: Session, chat_id: int):
    """Bitta chatni olish"""
    return db.query(Chat).filter(Chat.id == chat_id).first()


def get_chats(db: Session, skip: int = 0, limit: int = 100):
    """Barcha chatlarni olish"""
    return db.query(Chat).offset(skip).limit(limit).all()


def update_chat(db: Session, chat_id: int, chat: ChatUpdate):
    """Chatni yangilash"""
    db_chat = db.query(Chat).filter(Chat.id == chat_id).first()
    if not db_chat:
        return None
    for key, value in chat.dict(exclude_unset=True).items():
        setattr(db_chat, key, value)
    db.commit()
    db.refresh(db_chat)
    return db_chat


def delete_chat(db: Session, chat_id: int):
    """Chatni o'chirish"""
    db_chat = db.query(Chat).filter(Chat.id == chat_id).first()
    if db_chat:
        db.delete(db_chat)
        db.commit()
    return db_chat
