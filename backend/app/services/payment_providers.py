"""
To'lov tizimlari ro'yxati — bitta joyda.

Hozir ro'yxatda BITTA tizim: Rahmat (Multicard). Click va Payme uchun
yozilgan o'z integratsiyalari OLIB TASHLANDI — Multicard chekaut sahifasida
Payme, Click, Uzum, Anorbank, Oson, Alif, Xazna, Beepul, Trastpay va karta
orqali to'lash allaqachon bor. Ikki mustaqil integratsiya bir xil pulni
ikki xil yo'l bilan hisoblab, ertami-kechmi ikki xil natija berardi.

Ro'yxat bitta bo'lsa ham saqlanadi: u SELF_SERVICE_PAYMENT_METHODS ning
yagona manbasi, ya'ni "qaysi usul balansni to'ldira oladi" degan savolga
javob shu yerda. Ilgari bu ro'yxat uch joyga tarqalgan edi.

Yangi tizim qo'shish tartibi:
  1. uning servisini yozing (rahmat_service.py ga o'xshab);
  2. shu yerga bitta PaymentProvider qo'shing;
  3. balance_transactions.payment_method cheklovi ro'yxatiga kodini
     qo'shadigan migratsiya yozing;
  4. callback uchun route qo'shing va main.py ga ulang.

MUHIM: bu ro'yxatga faqat to'lovni TASDIQLAB beradigan tizim tushadi.
Tasdiq kelmaydigan usul (naqd pul, oddiy karta) balansni to'ldira olmaydi —
aynan shundan pulni yo'qdan bor qilish teshigi chiqqan edi.
"""
from dataclasses import dataclass
from typing import Callable, Dict, List

from app.core.config import settings


@dataclass(frozen=True)
class PaymentProvider:
    #: balance_transactions.payment_method da saqlanadigan qiymat
    code: str
    #: foydalanuvchiga ko'rsatiladigan nom
    title: str
    #: kalitlar sozlanganmi
    is_configured: Callable[[], bool]
    #: To'lov sahifasini boshlash: (db, tranzaksiya) -> URL.
    #:
    #: Ilgari bu yerda (id, summa) -> URL turardi, chunki Click havolani
    #: shunchaki satrdan yasardi. Rahmat esa shlyuzga murojaat qiladi va
    #: javobdagi uuid'ni tranzaksiyaga YOZIB QO'YISHI kerak — usiz keyin
    #: kelgan callback qaysi to'lov ekanini aniqlash imkoni bo'lmaydi.
    #: Shuning uchun imzoda db ham bor.
    start_payment: Callable[..., str]


def _start_rahmat(db, transaction, payment_system=None) -> str:
    # Import shu yerda: modul yuklanishida halqa bo'lmasin
    # (balance_service -> payment_providers -> balance_service).
    from app.services import rahmat_payment

    return rahmat_payment.start_topup(db, transaction, payment_system)


PROVIDERS: List[PaymentProvider] = [
    PaymentProvider(
        code="rahmat",
        title="Rahmat",
        is_configured=lambda: settings.rahmat_configured,
        start_payment=_start_rahmat,
    ),
]

BY_CODE: Dict[str, PaymentProvider] = {p.code: p for p in PROVIDERS}

#: Foydalanuvchi ilova orqali tanlay oladigan usullar
SELF_SERVICE_PAYMENT_METHODS = set(BY_CODE)

#: Tarixda qolgan usullar. Ular BILAN YANGI to'lov qilinmaydi, lekin
#: bazadagi eski satrlar o'chirilmaydi: "click" deb to'langan pul
#: haqiqatan Click orqali kelgan, uni "rahmat" deb qayta yozish tarixni
#: buzish bo'lardi. CHECK cheklovi shuning uchun ularni ham qabul qiladi.
LEGACY_PAYMENT_METHODS = {"click", "payme", "uzum", "card", "cash"}


def get(code: str) -> PaymentProvider | None:
    return BY_CODE.get(code)


def configured_codes() -> List[str]:
    """Kalitlari haqiqatan sozlangan tizimlar — ilovaga shu ro'yxat beriladi."""
    return [p.code for p in PROVIDERS if p.is_configured()]
