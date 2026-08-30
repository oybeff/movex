# Импорт всех схем
from .user import UserCreate, UserRead, UserUpdate
from .company import CompanyCreate, CompanyRead, CompanyUpdate
from .equipment import EquipmentCreate, EquipmentRead, EquipmentUpdate
from .order import OrderCreate, OrderRead, OrderUpdate
from .chat import ChatCreate, ChatRead
# в app/schemas/__init__.py
from .message import MessageCreate, MessageUpdate, Message
from .review import ReviewCreate, ReviewRead, ReviewUpdate
from .payment import PaymentCreate, PaymentRead, PaymentUpdate
