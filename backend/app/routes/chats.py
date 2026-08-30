from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.schemas import chat as chat_schema
from app.services import chat_service
from app.dependencies import get_db, get_current_user

router = APIRouter()

# POST создаём
@router.post("/", response_model=chat_schema.ChatRead)
def create_chat(chat: chat_schema.ChatCreate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return chat_service.create_chat(db, chat, current_user.id)

# GET все чаты
@router.get("/", response_model=list[chat_schema.ChatRead])
def get_chats(skip: int = 0, limit: int = 100, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return chat_service.get_chats(db, skip, limit)

# GET один чат
@router.get("/{chat_id}", response_model=chat_schema.ChatRead)
def get_chat(chat_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    db_chat = chat_service.get_chat(db, chat_id)
    if not db_chat:
        raise HTTPException(status_code=404, detail="Chat not found")
    return db_chat

# PUT обновление
@router.put("/{chat_id}", response_model=chat_schema.ChatRead)
def update_chat(chat_id: int, chat: chat_schema.ChatUpdate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    return chat_service.update_chat(db, chat_id, chat)

@router.delete("/{chat_id}", response_model=dict)
def delete_chat(chat_id: int, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    chat_service.delete_chat(db, chat_id)
    return {"message": "Chat deleted successfully"}
