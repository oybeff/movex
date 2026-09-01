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

MUHIM: bu yerda PUL YO'Q. E'lon tanishtiradi, kelishuvdan keyin tomonlar
bir-birining telefonini oladi. Eskrou buyurtmalarda ishlaydi va u aniq
texnikaga bog'langan, e'londa esa texnika umuman bo'lmasligi mumkin.

Telefon raqami e'londa hammaga ko'rinmaydi: uni faqat muallif va TASDIQLANGAN
ijrochi ko'radi. Aks holda taxta raqamlarni yig'ish uchun ochiq manba bo'lib
qolardi.
"""
import logging
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session, selectinload

from app.core import media
from app.core.account_state import assert_not_frozen
from app.core.equipment_types import is_valid_type
from app.models.listing import (
    LISTING_TTL_DAYS,
    MAX_LISTING_PHOTOS,
    MAX_OPEN_LISTINGS_PER_CLIENT,
    Listing,
    ListingPhoto,
)
from app.models.user import User
from app.services import notification_service

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
