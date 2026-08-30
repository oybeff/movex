from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.schemas import message as message_schema
from app.services import chat_service, message_service
from app.dependencies import get_db, get_current_user
from app.core.access import assert_chat_access

router = APIRouter()


def _chat_or_404(db: Session, chat_id: int):
    chat = chat_service.get_chat(db, chat_id)
    if not chat:
        raise HTTPException(status_code=404, detail="Chat not found")
    return chat


@router.post("/", response_model=message_schema.Message)
def create_message(message: message_schema.MessageCreate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Xabar faqat o'zi ishtirok etayotgan chatga yoziladi."""
    chat = _chat_or_404(db, message.chat_id)
    assert_chat_access(db, chat, current_user)
    return message_service.create_message(db, message, current_user.id)


@router.get("/", response_model=list[message_schema.Message])
def get_messages(chat_id: int = None, skip: int = 0, limit: int = 100, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """
    Chat xabarlari. chat_id majburiy: usiz ilgari tizimdagi BARCHA
    yozishmalar qaytarilardi.
    """
    if chat_id is None:
        raise HTTPException(status_code=400, detail="chat_id ko'rsatilishi shart")
    chat = _chat_or_404(db, chat_id)
    assert_chat_access(db, chat, current_user)
    return message_service.get_messages(db, skip, limit, chat_id)


@router.get("/{message_id}", response_model=message_schema.Message)
def get_message(message_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    db_msg = message_service.get_message(db, message_id)
    if not db_msg:
        raise HTTPException(status_code=404, detail="Message not found")
    assert_chat_access(db, _chat_or_404(db, db_msg.chat_id), current_user)
    return db_msg


@router.put("/{message_id}", response_model=message_schema.Message)
def update_message(message_id: int, message: message_schema.MessageUpdate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """O'z xabarini tahrirlash. Begonasini — yo'q."""
    db_msg = message_service.get_message(db, message_id)
    if not db_msg:
        raise HTTPException(status_code=404, detail="Message not found")
    if db_msg.sender_id != current_user.id and getattr(current_user, "role", None) != "admin":
        raise HTTPException(status_code=403, detail="Faqat o'z xabaringizni tahrirlashingiz mumkin")
    return message_service.update_message(db, message_id, message)


@router.delete("/{message_id}", response_model=dict)
def delete_message(message_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """O'z xabarini o'chirish. Begonasini — yo'q."""
    db_msg = message_service.get_message(db, message_id)
    if not db_msg:
        raise HTTPException(status_code=404, detail="Message not found")
    if db_msg.sender_id != current_user.id and getattr(current_user, "role", None) != "admin":
        raise HTTPException(status_code=403, detail="Faqat o'z xabaringizni o'chirishingiz mumkin")
    message_service.delete_message(db, message_id)
    return {"message": "Message deleted successfully"}
