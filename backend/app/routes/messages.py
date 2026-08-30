from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.schemas import message as message_schema
from app.services import message_service
from app.dependencies import get_db, get_current_user
router = APIRouter()

@router.post("/", response_model=message_schema.Message)
def create_message(message: message_schema.MessageCreate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return message_service.create_message(db, message, current_user.id)

@router.get("/", response_model=list[message_schema.Message])
def get_messages(chat_id: int = None, skip: int = 0, limit: int = 100, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return message_service.get_messages(db, skip, limit, chat_id)

@router.get("/{message_id}", response_model=message_schema.Message)
def get_message(message_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    db_msg = message_service.get_message(db, message_id)
    if not db_msg:
        raise HTTPException(status_code=404, detail="Message not found")
    return db_msg

@router.put("/{message_id}", response_model=message_schema.Message)
def update_message(message_id: int, message: message_schema.MessageUpdate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return message_service.update_message(db, message_id, message)

@router.delete("/{message_id}", response_model=dict)
def delete_message(message_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    message_service.delete_message(db, message_id)
    return {"message": "Message deleted successfully"}