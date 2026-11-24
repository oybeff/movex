"""
Hisob holati: bloklangan va muzlatilgan.

Bloklash kirish paytida va get_current_user ichida tekshiriladi — bunday
odam umuman ichkariga kirmaydi.

Muzlatish esa boshqacha: odam kiradi va hammasini ko'radi, lekin PUL
QIMIRLATADIGAN yoki majburiyat tug'diradigan amallarni qila olmaydi.
Tekshiruv shu yerda, bitta joyda: har bir servisda o'z shartini yozish —
bittasini unutib qo'yish demakdir.
"""
from fastapi import HTTPException


def assert_not_frozen(user) -> None:
    """
    Muzlatilgan hisob uchun 403.

    Interfeysda tugmani yashirish yetarli emas: API'ga to'g'ridan-to'g'ri
    so'rov yuborish mumkin.
    """
    if getattr(user, "is_frozen", False):
        raise HTTPException(
            403,
            "Hisobingiz muzlatilgan. Ko'rish mumkin, lekin buyurtma berish, "
            "taklif yuborish va pul yechish vaqtincha to'xtatilgan. "
            "Administrator bilan bog'laning.",
        )


def lift_expired_block(db, user) -> bool:
    """
    Muddatli blok (Admin P4, C3): muddat o'tgan bo'lsa — blokni olib,
    True qaytaradi. Fon vazifasi yo'q: tekshiruv kirishda va har so'rovda
    (get_current_user). Doimiy blok (blocked_until IS NULL) — tegilmaydi.
    """
    from datetime import datetime, timezone

    until = getattr(user, "blocked_until", None)
    if not getattr(user, "is_blocked", False) or until is None:
        return False
    if until > datetime.now(timezone.utc):
        return False
    user.is_blocked = False
    user.blocked_reason = None
    user.blocked_until = None
    db.commit()
    return True
