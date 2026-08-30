"""
To'lov tizimlari ro'yxati — bitta joyda.

Ilgari har bir tizim uchun kod uch joyga tarqalgan edi: ruxsat etilgan
usullar to'plami, to'lov havolasini yasashdagi if/elif, va shu tizimning
o'z servisi. Uchinchi tizim qo'shilganda uchalasini ham eslab qolish
kerak bo'lardi.

Yangi tizim qo'shish tartibi:
  1. uning servisini yozing (payme_service.py ga o'xshab);
  2. shu yerga bitta PaymentProvider qo'shing;
  3. balance_transactions.payment_method cheklovi ro'yxatiga kodini
     qo'shadigan migratsiya yozing;
  4. webhook uchun route qo'shing va main.py ga ulang.

Boshqa hech qayerda tizim nomini yozish shart emas.

MUHIM: bu ro'yxatga faqat to'lovni TASDIQLAB beradigan tizim tushadi.
Tasdiq kelmaydigan usul (naqd pul, oddiy karta) balansni to'ldira olmaydi —
aynan shundan pulni yo'qdan bor qilish teshigi chiqqan edi.
"""
from dataclasses import dataclass
from typing import Callable, Dict, List

from app.core.config import settings
from app.services.click_service import ClickService
from app.services.payme_service import PaymeService


@dataclass(frozen=True)
class PaymentProvider:
    #: balance_transactions.payment_method da saqlanadigan qiymat
    code: str
    #: foydalanuvchiga ko'rsatiladigan nom
    title: str
    #: kalitlar sozlanganmi
    is_configured: Callable[[], bool]
    #: to'lov sahifasiga havola: (tranzaksiya id, summa so'mda) -> URL
    build_checkout_url: Callable[[int, float], str]


PROVIDERS: List[PaymentProvider] = [
    PaymentProvider(
        code="click",
        title="Click",
        is_configured=lambda: settings.click_configured,
        build_checkout_url=lambda tx_id, amount: ClickService.generate_payment_url(
            transaction_id=tx_id, amount=amount
        ),
    ),
    PaymentProvider(
        code="payme",
        title="Payme",
        is_configured=lambda: settings.payme_configured,
        build_checkout_url=lambda tx_id, amount: PaymeService.build_checkout_url(
            transaction_id=tx_id, amount_sum=amount
        ),
    ),
    # Rahmat: hozircha protokol hujjatlari yo'q. Ular kelganda shu yerga
    # yana bitta PaymentProvider qo'shiladi — qolgan kod o'zgarmaydi.
]

BY_CODE: Dict[str, PaymentProvider] = {p.code: p for p in PROVIDERS}

#: Foydalanuvchi ilova orqali tanlay oladigan usullar
SELF_SERVICE_PAYMENT_METHODS = set(BY_CODE)


def get(code: str) -> PaymentProvider | None:
    return BY_CODE.get(code)


def configured_codes() -> List[str]:
    """Kalitlari haqiqatan sozlangan tizimlar — ilovaga shu ro'yxat beriladi."""
    return [p.code for p in PROVIDERS if p.is_configured()]
