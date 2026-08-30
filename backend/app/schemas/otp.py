from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class OTPSendRequest(BaseModel):
    """Request to send OTP to phone number"""
    phone: str

class OTPSendResponse(BaseModel):
    """Response after sending OTP"""
    success: bool
    message: str
    expires_in: int  # seconds

class OTPVerifyRequest(BaseModel):
    """Request to verify OTP code"""
    phone: str
    otp_code: str

class OTPVerifyResponse(BaseModel):
    """Response after verifying OTP"""
    success: bool
    message: str
    access_token: Optional[str] = None
    token_type: Optional[str] = None
    user_id: Optional[int] = None
    role: Optional[str] = None

class OTPVerificationRead(BaseModel):
    """OTP verification record"""
    id: int
    phone: str
    attempts: int
    is_verified: bool
    is_blocked: bool
    blocked_until: Optional[datetime] = None
    expires_at: datetime
    created_at: datetime

    class Config:
        from_attributes = True

