from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime

# Balance Schemas
class BalanceBase(BaseModel):
    user_id: int
    balance: float = Field(ge=0, description="Balance must be non-negative")

class BalanceCreate(BaseModel):
    user_id: int

class BalanceUpdate(BaseModel):
    balance: Optional[float] = Field(None, ge=0)

class BalanceRead(BaseModel):
    id: int
    user_id: int
    balance: float
    frozen_balance: float
    #: Sovg'aning ishlatilmagan qismi. Ilova ichida ishlatiladi, kartaga
    #: yechilmaydi — shuning uchun ilovaga ham ayta olishimiz kerak, aks
    #: holda u yechish ekranida yechib bo'lmaydigan pulni ko'rsatardi.
    bonus_balance: float = 0
    created_at: datetime
    updated_at: Optional[datetime] = None

    @property
    def available_balance(self) -> float:
        """Mavjud balans (muzlatilmagan)"""
        return self.balance - self.frozen_balance

    class Config:
        from_attributes = True


# Balance Transaction Schemas
class BalanceTransactionBase(BaseModel):
    amount: float = Field(gt=0, description="Amount must be positive")
    #: Ruxsat etilgan qiymatlar ro'yxati payment_providers da — hozir
    #: bittasi: "rahmat". Tekshiruv balance_service da, chunki xato matni
    #: mavjud usullarni sanab berishi kerak.
    payment_method: str = Field("rahmat", description="Payment method code (rahmat)")

class BalanceTransactionCreate(BalanceTransactionBase):
    #: To'lov havolasini SMS bilan yuborish uchun. Majburiy emas —
    #: berilmasa, profildagi raqam olinadi.
    phone_number: Optional[str] = Field(None, description="Phone number for the payment SMS")

    #: Qaysi ILOVADA to'lanadi: payme, click, uzum, alif va h.k.
    #:
    #: Berilsa — javobdagi havola o'sha ilovani ochadi. Berilmasa —
    #: Multicard'ning umumiy sahifasi (karta bilan to'lash ham o'sha
    #: yerda). Ro'yxat /balance/methods da keladi.
    payment_system: Optional[str] = Field(
        None, description="payme | click | uzum | alif | anorbank | oson | xazna | beepul | trastpay"
    )

class BalanceTransactionUpdate(BaseModel):
    status: Optional[str] = None
    description: Optional[str] = None

class BalanceTransactionRead(BaseModel):
    id: int
    user_id: int
    amount: float
    type: str
    status: str
    payment_method: Optional[str] = None
    description: Optional[str] = None
    #: Chek havolasi — to'lov tizimi beradi. Ilovada "chekni ko'rish"
    #: tugmasi shundan ishlaydi.
    rahmat_receipt_url: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class BalanceTopUpResponse(BaseModel):
    """Hisob to'ldirish javobi — chekaut sahifasiga havola bilan."""
    transaction_id: int
    amount: float
    payment_method: str
    status: str
    #: To'lov sahifasi. Ilova uni tashqi brauzerda ochadi.
    payment_url: Optional[str] = None

    class Config:
        from_attributes = True


class PaymentSystemRead(BaseModel):
    """To'lov ilovasi: kodi va ekrandagi nomi."""
    code: str
    title: str


class PaymentMethodRead(BaseModel):
    """
    Ilovaga beriladigan to'lov usuli.

    Ro'yxat serverdan keladi: yig'ilgan APK'dagi qotib qolgan ro'yxat
    sozlama o'zgarganda yolg'on bo'lib qolardi.
    """
    code: str
    title: str

    #: Shu usul ichida tanlash mumkin bo'lgan ilovalar.
    #:
    #: Ilova ularni tugma qilib ko'rsatadi: bosilganda Payme yoki Click
    #: ILOVASI ochiladi. Bo'sh ro'yxat — faqat umumiy sahifa.
    systems: List[PaymentSystemRead] = []

