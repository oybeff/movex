from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class ReviewBase(BaseModel):
    equipment_id: Optional[int]
    user_id: int
    rating: int
    comment: Optional[str]

class ReviewCreate(ReviewBase):
    pass

class ReviewUpdate(BaseModel):
    rating: Optional[int]
    comment: Optional[str]

class ReviewRead(ReviewBase):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True
