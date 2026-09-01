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
