"""
E'lonlar: kimdir yozadi, boshqasi oladi, muallif tasdiqlaydi.

E'lon IKKI TOMONLAMA va rolga bog'liq emas. Mijoz "yuk ortish uchun 3 kishi
kerak" deb yozadi; ega "ertaga ekskavator bo'sh, arzonroq" deb yozadi.
Shuning uchun bu faylda "mijoz"/"ega" emas, MUALLIF va IJROCHI deyiladi:
bitta odam bir e'londa muallif, boshqasida ijrochi bo'lishi mumkin.

Holatlar zanjiri:

    open  --(kimdir "olaman" dedi)---->  taken
    taken --(muallif tasdiqladi)------>  confirmed
    taken --(muallif rad etdi)-------->  open   (yana hammaga ko'rinadi)
    confirmed --(ish tugadi)---------->  done
    open/taken --(muallif bekor qildi)-> cancelled

PUL buyurtmalardagi bilan BIR XIL ishlaydi:

    tasdiqlash  -> muallifning balansida kelishilgan summa MUZLAYDI
    yakunlash   -> summa muallifdan yechiladi, ijrochiga ulush ayirilib o'tadi
    rad etish / bekor qilish -> faqat muzlatish olib tashlanadi

Ulush IJROCHIDAN ushlanadi — buyurtmada ham pulni oladigan tomon to'laydi.
Stavka bitta: adminkadagi commission_mode / commission_fixed / commission_percent,
buyurtmalar bilan umumiy. Ikkinchi stavka kiritilsa, ular ertami-kechmi
ajralib ketardi.

Kelishilgan summa: "olaman" yo'lida — e'lon byudjeti, taklif yo'lida —
qabul qilingan taklif narxi. U tasdiqlash paytida listings.agreed_price ga
yoziladi, chunki stavka keyin o'zgarishi mumkin.

Telefon raqami e'londa hammaga ko'rinmaydi: uni faqat muallif va TASDIQLANGAN
ijrochi ko'radi. Aks holda taxta raqamlarni yig'ish uchun ochiq manba bo'lib
qolardi.
"""
import logging
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import List, Optional

from fastapi import HTTPException
from sqlalchemy import func, or_
from sqlalchemy.orm import Session, selectinload

from app.core import media
from app.core.messages import t
from app.core.account_state import assert_not_frozen
from app.core.equipment_types import is_valid_type
from app.models.listing import (
    LISTING_TTL_DAYS,
    MAX_LISTING_PHOTOS,
    MAX_OPEN_LISTINGS_PER_CLIENT,
    Listing,
    ListingOffer,
    ListingPhoto,
    ListingReaction,
)
from app.models.balance import Balance, BalanceTransaction
from app.models.budget_reserve import BudgetReserve
from app.models.user import User
from app.services import notification_service, pricing_service

logger = logging.getLogger(__name__)

OPEN_STATUSES = ("open", "taken", "confirmed")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def expire_stale(db: Session) -> int:
    stale = (
        db.query(Listing)
        .filter(
            Listing.status == "open",
            Listing.expires_at.isnot(None),
            Listing.expires_at < _now(),
        )
        .all()
    )
    for listing in stale:
        listing.status = "expired"
    if stale:
        db.commit()
    return len(stale)


# ------------------------------------------------------------------ yozish

def create_listing(db: Session, client: User, data) -> Listing:
    assert_not_frozen(client)

    title = (data.title or "").strip()
    if not title:
        raise HTTPException(400, "Sarlavha bo'sh bo'lishi mumkin emas")

    equipment_type = (data.equipment_type or "").strip() or None
    if equipment_type and not is_valid_type(equipment_type):
        raise HTTPException(400, f"Texnika turi noto'g'ri: {equipment_type!r}")

    if data.needed_from and data.needed_to and data.needed_to < data.needed_from:
        raise HTTPException(400, "Tugash sanasi boshlanish sanasidan oldin bo'lmasin")

    open_count = (
        db.query(Listing)
        .filter(Listing.client_id == client.id, Listing.status.in_(("open", "taken")))
        .count()
    )
    if open_count >= MAX_OPEN_LISTINGS_PER_CLIENT:
        raise HTTPException(
            400,
            f"Ochiq e'lonlar soni {MAX_OPEN_LISTINGS_PER_CLIENT} tadan oshmasligi kerak",
        )

    photos = list(data.photos or [])
    if len(photos) > MAX_LISTING_PHOTOS:
        raise HTTPException(400, f"Rasmlar soni {MAX_LISTING_PHOTOS} tadan oshmasin")

    # Rasm manzili faqat SHU serverdan bo'lishi mumkin: ro'yxat oddiy satrlar
    # bo'lgani uchun u yerga istalgan havolani yozib yuborsa bo'lardi. Ikki
    # oqibati bor edi — begona saytdagi rasm e'londa ko'rsatilardi (uni
    # istalgan payt boshqasiga almashtirish mumkin), va manzil orqali
    # o'chirish katalogdan tashqariga chiqib ketishi mumkin edi.
    for url in photos:
        if not media.is_own_media(url):
            raise HTTPException(400, f"Rasm manzili noto'g'ri: {url[:80]!r}")

    listing = Listing(
        client_id=client.id,
        title=title[:120],
        description=(data.description or None),
        equipment_type=equipment_type,
        budget=data.budget,
        address=(data.address or None),
        latitude=data.latitude,
        longitude=data.longitude,
        needed_from=data.needed_from,
        needed_to=data.needed_to,
        # Telefon ko'rsatilmasa — profildagisi
        contact_phone=(data.contact_phone or client.phone),
        status="open",
        expires_at=_now() + timedelta(days=LISTING_TTL_DAYS),
    )
    db.add(listing)
    db.flush()

    for url in photos:
        db.add(ListingPhoto(listing_id=listing.id, url=url))

    db.commit()
    db.refresh(listing)
    return listing



# ----------------------------------------------------------------- pul
#
# Buyurtmalardagi bilan bir xil tartib. Farqi faqat shundaki, e'londa
# texnika bo'lmasligi mumkin, shuning uchun summa byudjetdan yoki qabul
# qilingan taklif narxidan olinadi.


def _language(db: Session, user_id: int) -> Optional[str]:
    user = db.query(User).filter(User.id == user_id).first()
    return user.language if user else None


def _lock_balance(db: Session, user_id: int) -> Balance:
    """Balansni QATOR BLOKI bilan oladi — bo'lmasa yaratadi.

    Blok shart: muallif ikki e'lonni bir vaqtda tasdiqlasa, bloksiz ikkalasi
    ham bitta pulni muzlatib qo'yardi.
    """
    balance = (
        db.query(Balance).filter(Balance.user_id == user_id).with_for_update().first()
    )
    if balance is None:
        balance = Balance(user_id=user_id, balance=Decimal("0"), frozen_balance=Decimal("0"))
        db.add(balance)
        db.flush()
        balance = (
            db.query(Balance).filter(Balance.user_id == user_id).with_for_update().one()
        )
    return balance


def _freeze_for_listing(db: Session, listing: Listing, amount: Decimal) -> None:
    """
    Muallifning balansida summani muzlatadi va kelishuvni e'longa yozadi.

    Pul yetmasa — 400. Ilgari tekshiruv umuman yo'q edi: balansi nol bo'lgan
    odam ham ijrochini tasdiqlay olardi, ya'ni ish boshlanardi, to'lov esa
    hech qayerdan kelmasdi.
    """
    if amount is None or Decimal(str(amount)) <= 0:
        # Byudjetsiz e'lon ham bo'ladi ("narxni ayting"). Unda summa faqat
        # taklif orqali paydo bo'ladi, "olaman" yo'li bilan tasdiqlab
        # bo'lmaydi — muzlatadigan summa yo'q.
        raise HTTPException(
            400,
            "E'londa byudjet ko'rsatilmagan. Ijrochi narx taklif qilsin, "
            "keyin taklifni tanlang",
        )

    amount = Decimal(str(amount))
    balance = _lock_balance(db, listing.client_id)
    available = Decimal(str(balance.balance)) - Decimal(str(balance.frozen_balance))
    if available < amount:
        raise HTTPException(
            400,
            f"Hisobingizda yetarli mablag' yo'q. "
            f"Mavjud: {float(available)} so'm, Kerak: {float(amount)} so'm",
        )

    balance.frozen_balance = Decimal(str(balance.frozen_balance)) + amount
    listing.agreed_price = amount
    # Ulush TASDIQLASH paytida hisoblanadi va yoziladi: adminkada stavka
    # keyin o'zgarsa, bu e'lon eski shart bo'yicha yopilishi kerak.
    listing.commission = pricing_service.calculate_commission(db, amount, amount)


def _unfreeze_listing(db: Session, listing: Listing) -> None:
    """Muzlatishni olib tashlaydi. Pul muallifda qoladi.

    Rad etish va bekor qilishda AYNAN shu bo'ladi — pul hech qayerga
    ketmaydi. Buni yakunlash bilan adashtirish = pulni yo'qdan bor qilish.
    """
    if listing.agreed_price is None:
        return
    amount = Decimal(str(listing.agreed_price))
    balance = _lock_balance(db, listing.client_id)
    current = Decimal(str(balance.frozen_balance))
    balance.frozen_balance = current - amount if current >= amount else Decimal("0")
    listing.agreed_price = None
    listing.commission = None


def _settle_listing(db: Session, listing: Listing) -> None:
    """
    Ish yakunlandi: pul muallifdan CHIQADI va ijrochiga o'tadi.

    Muzlatishni olib tashlashning o'zi yetarli emas — summa balansdan ham
    yechilishi kerak, aks holda pul yo'qdan bor bo'lardi.
    """
    if listing.agreed_price is None or not listing.taken_by:
        return

    amount = Decimal(str(listing.agreed_price))
    commission = Decimal(str(listing.commission or 0))
    if commission > amount:          # ehtiyot chorasi: ijrochi minusga ketmasin
        commission = amount
    payout = amount - commission

    author_balance = _lock_balance(db, listing.client_id)
    author_balance.frozen_balance = Decimal(str(author_balance.frozen_balance)) - amount
    author_balance.balance = Decimal(str(author_balance.balance)) - amount

    taker_balance = _lock_balance(db, listing.taken_by)
    taker_balance.balance = Decimal(str(taker_balance.balance)) + payout

    db.add(BalanceTransaction(
        user_id=listing.client_id,
        amount=amount,
        type="payment",
        status="completed",
        description=t("tx.listing_payment", _language(db, listing.client_id),
                      listing_id=listing.id, title=listing.title),
    ))
    db.add(BalanceTransaction(
        user_id=listing.taken_by,
        amount=payout,
        type="income",
        status="completed",
        description=t("tx.listing_income", _language(db, listing.taken_by),
                      listing_id=listing.id, title=listing.title),
    ))

    # Nol summani jadval qabul qilmaydi (check_budget_reserve_amount).
    if commission > 0:
        db.add(BudgetReserve(
            listing_id=listing.id,
            amount=commission,
            description=t("tx.listing_commission", None,
                          listing_id=listing.id, title=listing.title),
        ))

def take_listing(db: Session, listing_id: int, taker: User) -> Listing:
    """
    E'lonni olish. Rol muhim emas — mijoz ham, ega ham javob bera oladi.

    Qator BLOKLANADI: ikki kishi bir vaqtda "olaman" bosishi mumkin, va
    blokirovkasiz ikkalasi ham muvaffaqiyat javobini olardi.
    """
    assert_not_frozen(taker)

    listing = (
        db.query(Listing).filter(Listing.id == listing_id).with_for_update().first()
    )
    if listing is None:
        raise HTTPException(404, "E'lon topilmadi")
    if listing.client_id == taker.id:
        raise HTTPException(400, "O'z e'loningizni ola olmaysiz")
    if listing.status != "open":
        raise HTTPException(400, "E'lon allaqachon olingan yoki yopilgan")

    listing.status = "taken"
    listing.taken_by = taker.id
    listing.taken_at = _now()
    db.commit()
    db.refresh(listing)

    notification_service.create_localized(
        db, listing.client_id, "listing_taken",
        "listing_taken.title", "listing_taken.body",
        None, listing.equipment_type, None,
        title=listing.title, who=taker.full_name,
    )
    return listing


def confirm_listing(db: Session, listing_id: int, client: User) -> Listing:
    """Mijoz egasini tasdiqlaydi — shundan keyin ikkalasi telefonni ko'radi."""
    assert_not_frozen(client)

    listing = db.query(Listing).filter(Listing.id == listing_id).first()
    if listing is None:
        raise HTTPException(404, "E'lon topilmadi")
    if listing.client_id != client.id:
        raise HTTPException(403, "Bu e'lon sizniki emas")
    if listing.status != "taken":
        raise HTTPException(400, "Tasdiqlash uchun avval kimdir e'lonni olishi kerak")

    # Pul TASDIQLASHDA muzlatiladi, "olaman"da emas: aks holda tasodifiy
    # bosilgan tugma begona odamning pulini bog'lab qo'yardi.
    _freeze_for_listing(db, listing, listing.budget)

    listing.status = "confirmed"
    listing.confirmed_at = _now()
    db.commit()
    db.refresh(listing)

    if listing.taken_by:
        notification_service.create_localized(
            db, listing.taken_by, "listing_confirmed",
            "listing_confirmed.title", "listing_confirmed.body",
            None, listing.equipment_type, None,
            title=listing.title,
        )
    return listing


def reject_taker(db: Session, listing_id: int, client: User) -> Listing:
    """Mijozga ega yoqmadi — e'lon yana ochiq bo'ladi."""
    assert_not_frozen(client)

    listing = db.query(Listing).filter(Listing.id == listing_id).first()
    if listing is None:
        raise HTTPException(404, "E'lon topilmadi")
    if listing.client_id != client.id:
        raise HTTPException(403, "Bu e'lon sizniki emas")
    if listing.status != "taken":
        raise HTTPException(400, "E'lon hozir olinmagan")

    rejected_owner = listing.taken_by
    _unfreeze_listing(db, listing)
    listing.status = "open"
    listing.taken_by = None
    listing.taken_at = None
    db.commit()
    db.refresh(listing)

    if rejected_owner:
        notification_service.create_localized(
            db, rejected_owner, "listing_cancelled",
            "listing_rejected.title", "listing_rejected.body",
            None, listing.equipment_type, None,
            title=listing.title,
        )
    return listing


def finish_listing(db: Session, listing_id: int, user: User) -> Listing:
    """Ish yakunlandi. Ikkala tomon ham belgilay oladi."""
    listing = db.query(Listing).filter(Listing.id == listing_id).first()
    if listing is None:
        raise HTTPException(404, "E'lon topilmadi")
    if user.id not in (listing.client_id, listing.taken_by) and user.role != "admin":
        raise HTTPException(403, "Bu e'longa ruxsat yo'q")
    if listing.status != "confirmed":
        raise HTTPException(400, "Faqat tasdiqlangan e'lonni yakunlash mumkin")

    _settle_listing(db, listing)

    listing.status = "done"
    listing.finished_at = _now()
    db.commit()
    db.refresh(listing)

    other = listing.taken_by if user.id == listing.client_id else listing.client_id
    if other:
        notification_service.create_localized(
            db, other, "listing_done",
            "listing_done.title", "listing_done.body",
            None, listing.equipment_type, None,
            title=listing.title,
        )
    return listing


def cancel_listing(db: Session, listing_id: int, user: User) -> Listing:
    listing = db.query(Listing).filter(Listing.id == listing_id).first()
    if listing is None:
        raise HTTPException(404, "E'lon topilmadi")
    if listing.client_id != user.id and user.role != "admin":
        raise HTTPException(403, "Bu e'lon sizniki emas")
    if listing.status in ("done", "cancelled"):
        raise HTTPException(400, "E'lon allaqachon yopilgan")

    taker = listing.taken_by
    # Bekor qilishda pul MUALLIFDA qoladi — faqat muzlatish olib tashlanadi.
    _unfreeze_listing(db, listing)
    listing.status = "cancelled"
    db.commit()
    db.refresh(listing)

    if taker:
        notification_service.create_localized(
            db, taker, "listing_cancelled",
            "listing_cancelled.title", "listing_cancelled.body",
            None, listing.equipment_type, None,
            title=listing.title,
        )
    return listing


# ------------------------------------------------------- takliflar (narx)

def make_offer(db: Session, listing_id: int, user: User, price, comment=None) -> ListingOffer:
    """
    O'z narxini aytish.

    "Olaman" dan farqi: u muallifning byudjetiga rozilik bildiradi, taklif
    esa boshqa summani taklif qiladi. Muallif kelganlardan birini tanlaydi.

    Faqat OCHIQ e'longa taklif berish mumkin. Kimdir e'lonni olib bo'lgan
    bo'lsa, muallif avval u bilan ish ko'rsin: aks holda "olingan" e'londa
    parallel savdo ketardi va muallif ikki tomonga va'da bergan bo'lardi.
    """
    assert_not_frozen(user)

    listing = db.query(Listing).filter(Listing.id == listing_id).first()
    if listing is None:
        raise HTTPException(404, "E'lon topilmadi")
    if listing.client_id == user.id:
        raise HTTPException(400, "O'z e'loningizga taklif bera olmaysiz")
    if listing.status != "open":
        raise HTTPException(400, "E'lon ochiq emas")

    try:
        amount = Decimal(str(price)).quantize(Decimal("0.01"))
    except (ArithmeticError, TypeError, ValueError):
        raise HTTPException(400, "Narx noto'g'ri")
    if amount <= 0:
        raise HTTPException(400, "Narx noldan katta bo'lishi kerak")

    # Bir odamdan bitta taklif. Fikrini o'zgartirsa — o'sha qator
    # yangilanadi, aks holda bitta odam ro'yxatni to'ldirib tashlardi.
    offer = (
        db.query(ListingOffer)
        .filter(ListingOffer.listing_id == listing_id, ListingOffer.user_id == user.id)
        .first()
    )
    if offer is None:
        offer = ListingOffer(listing_id=listing_id, user_id=user.id)
        db.add(offer)

    offer.price = amount
    offer.comment = (comment or None)
    offer.status = "pending"

    db.commit()
    db.refresh(offer)

    notification_service.create_localized(
        db, listing.client_id, "listing_offer",
        "listing_offer.title", "listing_offer.body",
        None, listing.equipment_type, None,
        title=listing.title, who=user.full_name, price=f"{int(amount):,}".replace(",", " "),
    )
    return offer


def withdraw_offer(db: Session, listing_id: int, user: User) -> None:
    """Ijrochi taklifini qaytarib oladi."""
    offer = (
        db.query(ListingOffer)
        .filter(ListingOffer.listing_id == listing_id, ListingOffer.user_id == user.id)
        .first()
    )
    if offer is None:
        raise HTTPException(404, "Taklif topilmadi")
    if offer.status == "accepted":
        raise HTTPException(400, "Qabul qilingan taklifni qaytarib bo'lmaydi")

    db.delete(offer)
    db.commit()


def accept_offer(db: Session, listing_id: int, offer_id: int, author: User) -> Listing:
    """
    Muallif taklifni tanladi.

    Natija "olaman"dagi bilan bir xil: e'lon TASDIQLANGAN holatga o'tadi va
    ikkala tomon telefonni ko'radi. Oraliq "taken" holati kerak emas —
    tanlashning o'zi muallifning tasdig'i.

    Qator BLOKLANADI: muallif ikki taklifni bir vaqtda bosib yuborishi
    mumkin, blokirovkasiz ikkalasi ham "qabul qilindi" javobini olardi.
    """
    assert_not_frozen(author)

    listing = (
        db.query(Listing).filter(Listing.id == listing_id).with_for_update().first()
    )
    if listing is None:
        raise HTTPException(404, "E'lon topilmadi")
    if listing.client_id != author.id:
        raise HTTPException(403, "Bu e'lon sizniki emas")
    if listing.status != "open":
        raise HTTPException(400, "E'lon ochiq emas")

    offer = (
        db.query(ListingOffer)
        .filter(ListingOffer.id == offer_id, ListingOffer.listing_id == listing_id)
        .first()
    )
    if offer is None:
        raise HTTPException(404, "Taklif topilmadi")
    if offer.status != "pending":
        raise HTTPException(400, "Taklif allaqachon ko'rib chiqilgan")

    offer.status = "accepted"

    # Qolganlari rad etilgan deb belgilanadi — ijrochilar javobni kutib
    # o'tirmasin.
    (
        db.query(ListingOffer)
        .filter(
            ListingOffer.listing_id == listing_id,
            ListingOffer.id != offer.id,
            ListingOffer.status == "pending",
        )
        .update({ListingOffer.status: "declined"}, synchronize_session=False)
    )

    listing.taken_by = offer.user_id
    _freeze_for_listing(db, listing, offer.price)

    listing.status = "confirmed"
    listing.taken_at = _now()
    listing.confirmed_at = _now()

    db.commit()
    db.refresh(listing)

    notification_service.create_localized(
        db, offer.user_id, "listing_confirmed",
        "listing_offer_accepted.title", "listing_offer_accepted.body",
        None, listing.equipment_type, None,
        title=listing.title,
    )
    return listing


def list_offers(db: Session, listing_id: int, viewer: User) -> List[ListingOffer]:
    """
    Takliflar ro'yxati.

    Hammasini faqat MUALLIF (va admin) ko'radi: aks holda ijrochilar
    bir-birining narxini ko'rib, bir-birini arzonlatishga tushardi.
    Ijrochiga faqat o'zinikisi qaytadi.
    """
    listing = db.query(Listing).filter(Listing.id == listing_id).first()
    if listing is None:
        raise HTTPException(404, "E'lon topilmadi")

    query = db.query(ListingOffer).filter(ListingOffer.listing_id == listing_id)
    if viewer.role != "admin" and viewer.id != listing.client_id:
        query = query.filter(ListingOffer.user_id == viewer.id)

    return query.order_by(ListingOffer.price.asc(), ListingOffer.created_at.asc()).all()


# --------------------------------------------- yoqtirish va saqlash

def set_reaction(db: Session, listing_id: int, user: User, kind: str, on: bool) -> None:
    """Yoqtirish yoki saqlashni qo'yish/olib tashlash."""
    if kind not in (ListingReaction.LIKE, ListingReaction.SAVE):
        raise HTTPException(400, f"Noma'lum turi: {kind!r}")

    listing = db.query(Listing).filter(Listing.id == listing_id).first()
    if listing is None:
        raise HTTPException(404, "E'lon topilmadi")

    existing = (
        db.query(ListingReaction)
        .filter(
            ListingReaction.listing_id == listing_id,
            ListingReaction.user_id == user.id,
            ListingReaction.kind == kind,
        )
        .first()
    )

    if on and existing is None:
        db.add(ListingReaction(listing_id=listing_id, user_id=user.id, kind=kind))
    elif not on and existing is not None:
        db.delete(existing)
    else:
        return  # allaqachon shu holatda — bekorga yozmaymiz

    db.commit()


def reaction_counts(db: Session, listing_ids: List[int]) -> dict:
    """
    {listing_id: {"likes": n, "saves": n, "offers": n}} — BITTA so'rovda.

    Har bir e'lon uchun alohida sanash 20 ta kartochkada 60 ta so'rov
    berardi. Shuning uchun sahifadagi hamma id bo'yicha guruhlab olinadi.
    """
    result = {i: {"likes": 0, "saves": 0, "offers": 0} for i in listing_ids}
    if not listing_ids:
        return result

    rows = (
        db.query(
            ListingReaction.listing_id,
            ListingReaction.kind,
            func.count(ListingReaction.id),
        )
        .filter(ListingReaction.listing_id.in_(listing_ids))
        .group_by(ListingReaction.listing_id, ListingReaction.kind)
        .all()
    )
    for listing_id, kind, count in rows:
        key = "likes" if kind == ListingReaction.LIKE else "saves"
        result[listing_id][key] = count

    offer_rows = (
        db.query(ListingOffer.listing_id, func.count(ListingOffer.id))
        .filter(
            ListingOffer.listing_id.in_(listing_ids),
            ListingOffer.status.in_(("pending", "accepted")),
        )
        .group_by(ListingOffer.listing_id)
        .all()
    )
    for listing_id, count in offer_rows:
        result[listing_id]["offers"] = count

    return result


def viewer_marks(db: Session, user_id: int, listing_ids: List[int]) -> dict:
    """{listing_id: {"liked": bool, "saved": bool, "offered": bool}} — ko'ruvchi uchun."""
    marks = {
        i: {"liked": False, "saved": False, "offered": False} for i in listing_ids
    }
    if not listing_ids:
        return marks

    for listing_id, kind in (
        db.query(ListingReaction.listing_id, ListingReaction.kind)
        .filter(
            ListingReaction.listing_id.in_(listing_ids),
            ListingReaction.user_id == user_id,
        )
        .all()
    ):
        marks[listing_id]["liked" if kind == ListingReaction.LIKE else "saved"] = True

    for (listing_id,) in (
        db.query(ListingOffer.listing_id)
        .filter(
            ListingOffer.listing_id.in_(listing_ids),
            ListingOffer.user_id == user_id,
            ListingOffer.status.in_(("pending", "accepted")),
        )
        .all()
    ):
        marks[listing_id]["offered"] = True

    return marks


def list_saved(db: Session, user: User, skip: int = 0, limit: int = 50) -> List[Listing]:
    """Saqlanganlar — ijrochi keyin qaytib kelishi uchun."""
    expire_stale(db)
    return (
        _with_photos(db.query(Listing))
        .join(ListingReaction, ListingReaction.listing_id == Listing.id)
        .filter(
            ListingReaction.user_id == user.id,
            ListingReaction.kind == ListingReaction.SAVE,
        )
        .order_by(ListingReaction.created_at.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )


# ------------------------------------------------------------------ o'qish

def _with_photos(query):
    return query.options(selectinload(Listing.photos))


def list_feed(
    db: Session,
    viewer: User,
    equipment_type: Optional[str] = None,
    skip: int = 0,
    limit: int = 50,
) -> List[Listing]:
    """
    Taxta: begona ochiq e'lonlar va ko'ruvchi olgan, hali TUGAMAGAN e'lonlar.

    Rolga bog'liq emas — mijoz ham, ega ham bir xil taxtani ko'radi va
    bir-birining e'loniga javob bera oladi.

    O'z e'lonlari taxtaga tushmaydi — ularni "Mening e'lonlarim" da ko'radi.

    Tugagan va bekor qilinganlar ham chiqmaydi. Avval "u olgan hamma e'lon"
    qaytardi va taxta bajarilgan ishlar bilan to'lib borardi: brauzerda
    tekshirganda ekranning yuqorisi butunlay "Yakunlangan" kartochkalar edi,
    yangi e'lonni ko'rish uchun pastga aylantirish kerak bo'lardi.
    """
    expire_stale(db)

    # Taxtada — faqat begonalarning OCHIQ e'lonlari.
    #
    # Ilgari bu yerga o'zi olgan e'lonlar ham tushardi, va ijrochining javob
    # bergan ishlari begonalarning e'lonlari orasida yo'qolib ketardi: ularni
    # ro'yxat bo'lib ko'radigan joy umuman yo'q edi. Endi ular "Mening"
    # ichida, shuning uchun taxtadan olib tashlandi — aks holda ikki joyda
    # takrorlanardi.
    query = _with_photos(db.query(Listing)).filter(
        Listing.status == "open",
        Listing.client_id != viewer.id,
    )
    if equipment_type:
        query = query.filter(Listing.equipment_type == equipment_type)

    return (
        query.order_by(Listing.created_at.desc()).offset(skip).limit(limit).all()
    )


def list_mine(db: Session, user: User, skip: int = 0, limit: int = 50) -> List[Listing]:
    """
    "Mening" — odamning O'Z ishlari: joylashtirgani ham, javob bergani ham.

    E'lon ikki tomonlama, shuning uchun bitta odam bir e'londa muallif,
    boshqasida ijrochi bo'ladi. Ilgari bu yerda faqat muallifligi qaytardi,
    va javob berganini ro'yxat bo'lib ko'rish mumkin emas edi.
    """
    expire_stale(db)
    return (
        _with_photos(db.query(Listing))
        .filter(or_(Listing.client_id == user.id, Listing.taken_by == user.id))
        .order_by(Listing.created_at.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )


def get_listing(db: Session, listing_id: int, viewer: User) -> Listing:
    listing = (
        _with_photos(db.query(Listing)).filter(Listing.id == listing_id).first()
    )
    if listing is None:
        raise HTTPException(404, "E'lon topilmadi")

    # Ko'rishlar soni — faqat begona odam ochganda va faqat ochiq e'londa
    if listing.client_id != viewer.id and listing.status in OPEN_STATUSES:
        listing.views_count = (listing.views_count or 0) + 1
        db.commit()
        db.refresh(listing)

    return listing


def can_see_phone(listing: Listing, viewer: User) -> bool:
    """
    Telefon faqat ishtirokchilarga ko'rinadi.

    Aks holda taxta telefon raqamlarini yig'ish uchun ochiq manba bo'lib
    qolardi: ro'yxatdan o'tib, hamma e'lonni ochib chiqish yetarli.
    """
    if viewer.role == "admin":
        return True
    if viewer.id == listing.client_id:
        return True
    # DIQQAT: "taken" holati ro'yxatda YO'Q.
    #
    # Egasi e'lonni olgani — bu hali kelishuv emas, mijoz uni tasdiqlashi
    # kerak. Agar telefon "olaman" bosilishi bilanoq ochilsa, tasdiqlashning
    # ma'nosi qolmaydi: raqamni olish uchun tugmani bosish yetarli bo'lardi.
    return listing.taken_by == viewer.id and listing.status in ("confirmed", "done")
