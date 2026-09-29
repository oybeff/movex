"""
Texnika egasining pul yechishi.

Pul harakati qat'iy: ariza berilganda summa muzlatiladi, to'langanda
balansdan yechiladi, rad etilganda muzlatish qaytariladi. Muzlatish
kerak, aks holda ega bir xil pulni bir necha marta so'rab olishi mumkin.

Pul yechishdan platforma ulushi ushlab qolinadi va uni TEXNIKA EGASI
to'laydi. Sabab oddiy: bir buyurtmadan atigi 5 000 so'm olinadi, va bu
summa pulni kartaga o'tkazish uchun to'lov tizimi oladigan foizni
qoplamaydi.

Ulush ariza summasidan ICHIDAN ushlanadi: 100 000 so'radi — balansidan
100 000 yechiladi, kartaga 95 000 tushadi. Shuning uchun ega balansini
oxirgi so'migacha yecha oladi; ustiga qo'shilganda esa to'liq balansni
yechishning iloji bo'lmasdi.
"""
import logging
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.account_state import assert_not_frozen
from app.core.messages import t
from app.models.app_settings import AppSettings
from app.models.balance import Balance, BalanceTransaction
from app.models.payout_request import PayoutRequest
from app.schemas.payout import PayoutRequestCreate
from app.services.balance_service import get_or_create_balance, withdrawable_balance

MIN_PAYOUT_SUM = Decimal("50000")

# --------------------------------------------------- avtomatik o'tkazish
#
# Pul kartaga Multicard orqali o'tadi (POST /payment/credit). Savol faqat
# shunda: o'tkazishni KIM boshlaydi.
#
#   o'chirilgan (standart) — arizani admin ko'radi va tugmani bosadi,
#                            o'tkazmani tizim bajaradi;
#   yoqilgan               — ariza berilishi bilanoq pul ketadi.
#
# Standart holda o'chirilgan ataylab: o'tkazma QAYTARILMAYDI, va yangi
# tizimni birinchi kunlarda odam ko'zi bilan kuzatish arzonga tushadi.
# Tumbler adminkada (commission.php), kodda emas.
AUTO_PAYOUT_KEY = "payout_auto_enabled"

# ------------------------------------------------------------- komissiya
#
# Tuzilishi buyurtma komissiyasi bilan bir xil (pricing_service.py):
# rejim + ikkala qiymat. Ikkovi bir vaqtda ishlamaydi — rejim qaysi biri
# amal qilishini belgilaydi. Adminkadan almashtiriladi, kodni tahrirlash
# shart emas.
PAYOUT_COMMISSION_MODE_KEY = "payout_commission_mode"
PAYOUT_COMMISSION_FIXED_KEY = "payout_commission_fixed"
PAYOUT_COMMISSION_PERCENT_KEY = "payout_commission_percent"

MODE_FIXED = "fixed"
MODE_PERCENT = "percent"

DEFAULT_PAYOUT_COMMISSION_MODE = MODE_FIXED
DEFAULT_PAYOUT_COMMISSION_FIXED = Decimal("5000")
DEFAULT_PAYOUT_COMMISSION_PERCENT = Decimal("10")


def _setting(db: Session, key: str) -> Optional[str]:
    row = db.query(AppSettings).filter(AppSettings.key == key).first()
    return None if row is None or row.value is None else str(row.value)


def is_auto_payout_enabled(db: Session) -> bool:
    """Ariza berilishi bilanoq pul ketsinmi. Sozlama yo'q bo'lsa — yo'q."""
    raw = (_setting(db, AUTO_PAYOUT_KEY) or "").strip().lower()
    return raw in ("1", "true", "yes", "on")


def get_commission_mode(db: Session) -> str:
    """'fixed' yoki 'percent'. Notanish qiymat — standart rejim."""
    raw = (_setting(db, PAYOUT_COMMISSION_MODE_KEY) or "").strip().lower()
    return raw if raw in (MODE_FIXED, MODE_PERCENT) else DEFAULT_PAYOUT_COMMISSION_MODE


def get_commission_fixed(db: Session) -> Decimal:
    """Qat'iy ushlanma, so'mda. Manfiy yoki xato qiymat — standart 5 000."""
    raw = _setting(db, PAYOUT_COMMISSION_FIXED_KEY)
    if raw is None:
        return DEFAULT_PAYOUT_COMMISSION_FIXED
    try:
        amount = Decimal(raw)
    except (ArithmeticError, TypeError, ValueError):
        return DEFAULT_PAYOUT_COMMISSION_FIXED
    return amount if amount >= 0 else DEFAULT_PAYOUT_COMMISSION_FIXED


def get_commission_percent(db: Session) -> Decimal:
    """Ushlanma foizi. Xato yoki chegaradan tashqari qiymat — standart 10%."""
    raw = _setting(db, PAYOUT_COMMISSION_PERCENT_KEY)
    if raw is None:
        return DEFAULT_PAYOUT_COMMISSION_PERCENT
    try:
        percent = Decimal(raw)
    except (ArithmeticError, TypeError, ValueError):
        return DEFAULT_PAYOUT_COMMISSION_PERCENT
    return percent if 0 <= percent <= 100 else DEFAULT_PAYOUT_COMMISSION_PERCENT


def calculate_commission(db: Session, amount: Decimal) -> Decimal:
    """
    Pul yechishdan ushlanadigan summa.

    Ushlanma ariza summasidan OSHMAYDI: aks holda kartaga manfiy summa
    tushib qolardi. Buyurtma komissiyasida ham xuddi shu qoida.
    """
    if get_commission_mode(db) == MODE_FIXED:
        commission = get_commission_fixed(db)
    else:
        commission = amount * get_commission_percent(db) / Decimal("100")

    commission = commission.quantize(Decimal("1"), rounding=ROUND_HALF_UP)
    if commission < 0:
        return Decimal("0")
    return min(commission, amount)


def _money(value: Decimal) -> str:
    """95000 -> "95 000". Izohda summa o'qiladigan ko'rinishda turishi kerak."""
    return f"{int(value):,}".replace(",", " ")


def _user_language(db: Session, user_id: int):
    """Izoh egasining tilida yoziladi — u "Amallar tarixi"da shundayligicha turadi."""
    from app.models.user import User
    user = db.query(User).filter(User.id == user_id).first()
    return user.language if user else None


def create_request(db: Session, user_id: int, data: PayoutRequestCreate) -> PayoutRequest:
    # Muzlatilgan hisob pul yecha olmaydi — nizoli holatlar aynan shuning
    # uchun muzlatiladi.
    from app.models.user import User
    assert_not_frozen(db.query(User).filter(User.id == user_id).first())
    amount = Decimal(str(data.amount)).quantize(Decimal("0.01"))

    if amount < MIN_PAYOUT_SUM:
        raise HTTPException(
            status_code=400,
            detail=f"Eng kam yechish summasi {int(MIN_PAYOUT_SUM):,} so'm".replace(",", " "),
        )

    get_or_create_balance(db, user_id)

    # Qatorni bloklaymiz: bir vaqtda kelgan ikki ariza bitta pulni
    # ikki marta band qilib qo'ymasligi kerak.
    balance = (
        db.query(Balance)
        .filter(Balance.user_id == user_id)
        .with_for_update()
        .one()
    )
    # Sovg'a pulini YECHIB BO'LMAYDI — u summadan chiqarib tashlanadi.
    available = withdrawable_balance(balance)

    if available < amount:
        bonus = Decimal(str(balance.bonus_balance or 0))
        detail = (
            f"Yetarli mablag' yo'q. Yechish mumkin: {float(available)} so'm, "
            f"so'ralgan: {float(amount)} so'm"
        )
        if bonus > 0:
            # Aks holda odam balansida 50 000 turganini ko'rib, nega
            # yechilmayotganini tushunmasdi.
            detail += (
                f". Sovg'a puli ({float(bonus)} so'm) faqat ilova ichida "
                f"ishlatiladi, kartaga yechilmaydi"
            )
        raise HTTPException(status_code=400, detail=detail)

    # Ushlanma ariza berilgan paytdagi sozlama bo'yicha hisoblanadi va
    # o'sha holicha saqlanadi: admin ertaga foizni o'zgartirsa, kecha
    # berilgan ariza qayta hisoblanib ketmasligi kerak.
    commission = calculate_commission(db, amount)
    payout_amount = amount - commission

    if payout_amount <= 0:
        # Ushlanma butun summani yeb qo'ygan holat. Bunday arizani qabul
        # qilish — egadan pulni olib, evaziga hech narsa bermaslik.
        raise HTTPException(
            status_code=400,
            detail=(
                f"Komissiya ({int(commission):,} so'm) so'ralgan summadan kam "
                f"emas. Kattaroq summa kiriting.".replace(",", " ")
            ),
        )

    balance.frozen_balance = Decimal(str(balance.frozen_balance)) + amount

    request = PayoutRequest(
        user_id=user_id,
        amount=amount,
        commission=commission,
        payout_amount=payout_amount,
        status="pending",
        card_number=data.card_number,
        card_holder=data.card_holder,
        comment=data.comment,
    )
    db.add(request)
    db.commit()
    db.refresh(request)

    if is_auto_payout_enabled(db):
        # Xato ariza berishni BUZMAYDI: pul muzlatilgan, ariza 'pending'
        # da qoladi va admin uni qo'lda o'tkazadi. Aks holda o'tkazma
        # xatosi "ariza berilmadi" ga aylanib, ega qayta-qayta yuborar
        # va har safar yangi muzlatish paydo bo'lardi.
        try:
            send_to_card(db, request)
        except HTTPException as exc:
            logging.getLogger(__name__).warning(
                "avtomatik o'tkazma o'tmadi, ariza qo'lda ko'riladi: id=%s detail=%s",
                request.id, exc.detail,
            )
        db.refresh(request)

    return request


def list_for_user(db: Session, user_id: int) -> List[PayoutRequest]:
    return (
        db.query(PayoutRequest)
        .filter(PayoutRequest.user_id == user_id)
        .order_by(PayoutRequest.created_at.desc())
        .all()
    )


def list_all(db: Session, status: Optional[str] = None, skip: int = 0, limit: int = 100) -> List[PayoutRequest]:
    query = db.query(PayoutRequest)
    if status:
        query = query.filter(PayoutRequest.status == status)
    return query.order_by(PayoutRequest.created_at.desc()).offset(skip).limit(limit).all()


def get_request(db: Session, request_id: int) -> PayoutRequest:
    """Arizani holatiga qaramasdan olish — holatni sverka qilish uchun."""
    request = db.query(PayoutRequest).filter(PayoutRequest.id == request_id).first()
    if request is None:
        raise HTTPException(status_code=404, detail="Ariza topilmadi")
    return request


def _load_pending(db: Session, request_id: int) -> PayoutRequest:
    request = db.query(PayoutRequest).filter(PayoutRequest.id == request_id).first()
    if request is None:
        raise HTTPException(status_code=404, detail="Ariza topilmadi")
    if request.status != "pending":
        raise HTTPException(
            status_code=400,
            detail=f"Ariza allaqachon ko'rib chiqilgan: {request.status}",
        )
    return request


#: Multicard'dagi o'tkazma raqamining boshi. Kabinetda ariza bo'yicha
#: qidirish uchun kerak — aynan shu satr `store_invoice_id` ga tushadi.
PAYOUT_INVOICE_PREFIX = "payout-"


def payout_invoice_id(request_id: int) -> str:
    return f"{PAYOUT_INVOICE_PREFIX}{request_id}"


def pay(db: Session, request_id: int, admin_id: Optional[int], admin_comment: Optional[str] = None) -> PayoutRequest:
    """
    Arizani to'lash: pul kartaga MULTICARD orqali o'tadi.

    Ilgari bu funksiya faqat hisobni yuritardi — pulni admin bank
    ilovasida qo'lda o'tkazardi va keyin "to'landi" deb belgilardi.
    Endi o'tkazmani tizim bajaradi, ya'ni balansdan yechish faqat
    shlyuz "success" deganidan KEYIN bo'ladi. Tartib muhim: teskarisida
    o'tkazma o'tmasa ham egadan pul yechilgan bo'lardi.
    """
    request = _load_pending(db, request_id)
    if admin_comment:
        request.admin_comment = admin_comment
        db.commit()
    return send_to_card(db, request, admin_id=admin_id)


def send_to_card(db: Session, request: PayoutRequest, admin_id: Optional[int] = None) -> PayoutRequest:
    """
    Kartaga o'tkazish so'rovi va natijani arizaga tushirish.

    Kartaga ariza summasining KOMISSIYASIZ qismi ketadi
    (`payout_amount`), balansdan esa to'liq summa yechiladi — farqi
    platformada qoladi.
    """
    from app.services import rahmat_service
    from app.services.rahmat_service import RahmatError

    if request.status != "pending":
        raise HTTPException(
            status_code=400,
            detail=f"Ariza allaqachon ko'rib chiqilgan: {request.status}",
        )

    # O'tkazma allaqachon boshlangan bo'lsa, IKKINCHI marta yubormaymiz:
    # holatini so'raymiz. Aks holda bir arizaga pul ikki marta ketardi.
    if request.rahmat_uuid:
        return sync_with_gateway(db, request)

    try:
        data = rahmat_service.create_payout(
            pan=request.card_number,
            amount_sum=request.payout_amount,
            invoice_id=payout_invoice_id(request.id),
        )
    except RahmatError as exc:
        # ERROR_UNKNOWN yoki timeout — natija NOMA'LUM. Pulni balansdan
        # yechmaymiz va so'rovni QAYTARMAYMIZ: hujjat holatni tekshirishni
        # talab qiladi, lekin uuid bizga kelmagan, shuning uchun tekshirish
        # Multicard kabinetida invoice_id bo'yicha qo'lda bo'ladi.
        request.rahmat_error = (
            f"{exc.code}: {exc.details}"
            + (
                f" | natija noma'lum, kabinetda {payout_invoice_id(request.id)} "
                f"bo'yicha tekshiring"
                if exc.is_unknown
                else ""
            )
        )
        db.commit()
        logging.getLogger(__name__).error(
            "kartaga o'tkazma xatosi: ariza=%s code=%s details=%s",
            request.id, exc.code, exc.details,
        )
        raise HTTPException(status_code=502, detail=f"{exc.code}: {exc.details}")

    return _apply_gateway_payout(db, request, data, admin_id=admin_id)


def sync_with_gateway(db: Session, request: PayoutRequest) -> PayoutRequest:
    """
    O'tkazma holatini shlyuzdan so'rab aniqlash.

    Kerak bo'ladigan joy: so'rov timeout bilan tugagan yoki holat
    'draft'/'progress' da qolgan. Hujjat aynan shuni talab qiladi —
    so'rovni qaytarmaslik, holatni so'rash.
    """
    from app.services import rahmat_service
    from app.services.rahmat_service import RahmatError

    if not request.rahmat_uuid:
        raise HTTPException(status_code=400, detail="O'tkazma hali boshlanmagan")

    try:
        data = rahmat_service.get_payout(request.rahmat_uuid)
    except RahmatError as exc:
        raise HTTPException(status_code=502, detail=f"{exc.code}: {exc.details}")

    return _apply_gateway_payout(db, request, data, admin_id=request.processed_by)


def _apply_gateway_payout(
    db: Session,
    request: PayoutRequest,
    data: Dict[str, Any],
    admin_id: Optional[int] = None,
) -> PayoutRequest:
    """Shlyuz javobini arizaga tushiradi va kerak bo'lsa balansni yopadi."""
    from app.services import rahmat_service

    status = str(data.get("status") or "").strip().lower()
    request.rahmat_uuid = data.get("uuid") or request.rahmat_uuid
    request.rahmat_status = status or request.rahmat_status
    request.rahmat_receipt_url = data.get("receipt_url") or request.rahmat_receipt_url

    if status == rahmat_service.STATUS_SUCCESS:
        request.rahmat_error = None
        db.commit()
        return _settle(db, request, admin_id)

    if status == rahmat_service.STATUS_ERROR:
        # O'tkazma o'tmadi: pul egasida QOLADI (muzlatilgan holda), ariza
        # 'pending' da turadi. Rad etish emas: xato vaqtinchalik bo'lishi
        # mumkin, va rad etish egadan so'ramasdan qaror qilish bo'lardi.
        request.rahmat_error = str(
            data.get("ps_response_msg") or data.get("ps_response_code") or "o'tkazma rad etildi"
        )
        db.commit()
        raise HTTPException(
            status_code=502,
            detail=f"Kartaga o'tkazilmadi: {request.rahmat_error}",
        )

    # draft / progress — pul yo'lda. Balansga TEGMAYMIZ: natija hali
    # aniq emas, va "yechib qo'yib keyin ko'ramiz" degan yo'l aynan
    # shunday holatlarda pulni yo'qotadi.
    db.commit()
    db.refresh(request)
    return request


def _settle(db: Session, request: PayoutRequest, admin_id: Optional[int] = None) -> PayoutRequest:
    """
    Pul kartaga o'tdi: balansdan yechamiz va muzlatishni olib tashlaymiz.

    FAQAT shlyuz "success" deganda chaqiriladi — `_apply_gateway_payout`
    dan. Boshqa yo'l yo'q: ikkinchi chaqiruv joyi paydo bo'lishi bilan
    o'tkazmasiz pul yechish imkoni ham paydo bo'lardi.
    """
    from datetime import datetime, timezone

    amount = Decimal(str(request.amount))

    balance = (
        db.query(Balance)
        .filter(Balance.user_id == request.user_id)
        .with_for_update()
        .one()
    )

    frozen = Decimal(str(balance.frozen_balance))
    total = Decimal(str(balance.balance))

    if frozen < amount or total < amount:
        # Pul KARTAGA ALLAQACHON KETDI — bu yerda to'xtab, xato qaytarish
        # mumkin emas: ariza 'pending' da qolib, keyin qayta o'tkazilardi.
        # Shuning uchun bor pulni yechamiz, arizani 'paid' deb yopamiz va
        # farqni logga yozamiz — bu qo'lda hal qilinadigan holat.
        logging.getLogger(__name__).error(
            "o'tkazma o'tdi, lekin balans arizaga mos kelmadi: ariza=%s user=%s "
            "ariza summasi=%s balans=%s muzlatilgan=%s",
            request.id, request.user_id, amount, total, frozen,
        )
        request.rahmat_error = (
            "Pul kartaga o'tdi, lekin balansdagi summa arizaga mos kelmadi — "
            "qo'lda tekshiring"
        )

    balance.frozen_balance = frozen - amount if frozen >= amount else Decimal("0")
    balance.balance = total - amount if total >= amount else Decimal("0")

    # Balansdan to'liq summa yechiladi, kartaga esa komissiyasiz qismi
    # o'tkaziladi — farqi platformada qoladi. Izohda ikkalasi ham
    # ko'rsatiladi, aks holda ega yo'qolgan pulni izlab qolardi.
    commission = Decimal(str(request.commission or 0))
    net = Decimal(str(request.payout_amount or amount))
    language = _user_language(db, request.user_id)

    if commission > 0:
        description = t(
            "tx.payout_with_commission",
            language,
            request_id=request.id,
            card=request.card_masked,
            net=_money(net),
            commission=_money(commission),
        )
    else:
        description = t(
            "tx.payout",
            language,
            request_id=request.id,
            card=request.card_masked,
        )

    db.add(
        BalanceTransaction(
            user_id=request.user_id,
            amount=amount,
            type="withdrawal",
            status="completed",
            # Izoh egasining "Amallar tarixi"ga tushadi — uning tilida.
            description=description,
        )
    )

    request.status = "paid"
    request.processed_by = admin_id
    request.processed_at = datetime.now(timezone.utc)

    db.commit()
    db.refresh(request)
    return request


def reject(db: Session, request_id: int, admin_id: int, admin_comment: Optional[str] = None) -> PayoutRequest:
    """Rad etildi: pul egasida qoladi, faqat muzlatish olib tashlanadi."""
    from datetime import datetime, timezone

    request = _load_pending(db, request_id)
    amount = Decimal(str(request.amount))

    balance = (
        db.query(Balance)
        .filter(Balance.user_id == request.user_id)
        .with_for_update()
        .one()
    )
    frozen = Decimal(str(balance.frozen_balance))
    # Muzlatish qandaydir sababga ko'ra kamayib qolgan bo'lsa, manfiy qilmaymiz
    balance.frozen_balance = frozen - amount if frozen >= amount else Decimal("0")

    request.status = "rejected"
    request.processed_by = admin_id
    request.processed_at = datetime.now(timezone.utc)
    request.admin_comment = admin_comment

    db.commit()
    db.refresh(request)
    return request
