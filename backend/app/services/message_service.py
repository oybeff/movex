from sqlalchemy.orm import Session
from app.models.message import Message
from app.schemas.message import MessageCreate, MessageUpdate


def create_message(db: Session, message: MessageCreate, user_id: int):
    """Yangi xabar yaratish"""
    message_data = message.dict()
    message_data['sender_id'] = user_id

    db_message = Message(**message_data)
    db.add(db_message)
    db.commit()
    db.refresh(db_message)
    return db_message


def get_message(db: Session, message_id: int):
    """Bitta xabarni olish"""
    return db.query(Message).filter(Message.id == message_id).first()


def get_messages(db: Session, skip: int = 0, limit: int = 100, chat_id: int = None):
    """Barcha xabarlarni olish (chat_id bo'yicha filter qilish mumkin)"""
    query = db.query(Message)

    if chat_id is not None:
        query = query.filter(Message.chat_id == chat_id)

    return query.order_by(Message.sent_at.desc()).offset(skip).limit(limit).all()


def update_message(db: Session, message_id: int, message: MessageUpdate):
    """Xabarni yangilash"""
    db_message = db.query(Message).filter(Message.id == message_id).first()
    if not db_message:
        return None
    for key, value in message.dict(exclude_unset=True).items():
        setattr(db_message, key, value)
    db.commit()
    db.refresh(db_message)
    return db_message


def delete_message(db: Session, message_id: int):
    """Xabarni o'chirish"""
    db_message = db.query(Message).filter(Message.id == message_id).first()
    if db_message:
        db.delete(db_message)
        db.commit()
    return db_message
