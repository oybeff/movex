"""
Serverda yoziladigan matnlarning tarjimasi.

Nega bu kerak. Xabarnoma sarlavhasi va matni serverda yoziladi va bazada
tayyor satr bo'lib yotadi. Ilova ularni shundayligicha ko'rsatadi, ya'ni
ruscha interfeysda o'zbekcha matn chiqadi.

Ilovada sarlavhani qayta yig'ish mumkin (notification_model.displayTitle
shuni qiladi), lekin PUSH uchun bu ishlamaydi: push matnini server yozadi
va telefon ekranida u o'zgarmaydi. Shuning uchun til serverga ham kerak.

Foydalanuvchining tili users.language da saqlanadi. Ilova uni til
almashtirilganda yuboradi (PUT /users/me). Til noma'lum bo'lsa —
o'zbekcha, chunki ilovada sukut bo'yicha o'sha.
"""
from typing import Dict, Optional

DEFAULT_LANGUAGE = "uz"
SUPPORTED_LANGUAGES = ("uz", "ru")

#: kalit -> {til: shablon}. Shablonda {} o'rniga format() argumentlari.
MESSAGES: Dict[str, Dict[str, str]] = {
    # --- buyurtmalar: sarlavha ---
    "order_created.title": {
        "uz": "Yangi buyurtma: {what}",
        "ru": "Новый заказ: {what}",
    },
    "order_confirmed.title": {
        "uz": "Buyurtma tasdiqlandi: {what}",
        "ru": "Заказ подтверждён: {what}",
    },
    "order_rejected.title": {
        "uz": "Buyurtma rad etildi: {what}",
        "ru": "Заказ отклонён: {what}",
    },
    "order_cancelled.title": {
        "uz": "Buyurtma bekor qilindi: {what}",
        "ru": "Заказ отменён: {what}",
    },
    "order_completed.title": {
        "uz": "Buyurtma yakunlandi: {what}",
        "ru": "Заказ завершён: {what}",
    },
    # --- buyurtmalar: matn ---
    "order_created.body": {
        "uz": "Buyurtma #{order_id}, {start} — {end}",
        "ru": "Заказ #{order_id}, {start} — {end}",
    },
    "order_confirmed.body": {
        "uz": "Buyurtma #{order_id} egasi tomonidan tasdiqlandi",
        "ru": "Заказ #{order_id} подтверждён владельцем",
    },
    "order_rejected.body": {
        "uz": "Buyurtma #{order_id} rad etildi, pul hisobingizga qaytarildi",
        "ru": "Заказ #{order_id} отклонён, деньги вернулись на счёт",
    },
    "order_cancelled.body": {
        "uz": "Buyurtma #{order_id} bekor qilindi",
        "ru": "Заказ #{order_id} отменён",
    },
    "order_completed.body": {
        "uz": "Buyurtma #{order_id} muvaffaqiyatli yakunlandi",
        "ru": "Заказ #{order_id} успешно завершён",
    },
    # --- zayavkalar: sarlavha ---
    "request_created.title": {
        "uz": "Yangi zayavka: {what}",
        "ru": "Новая заявка: {what}",
    },
    "request_offer.title": {
        "uz": "Zayavkangizga taklif keldi",
        "ru": "На вашу заявку прислали предложение",
    },
    "request_offer_accepted.title": {
        "uz": "Taklifingiz qabul qilindi",
        "ru": "Ваше предложение принято",
    },
    "request_offer_rejected.title": {
        "uz": "Taklifingiz tanlanmadi",
        "ru": "Ваше предложение не выбрали",
    },
    "request_cancelled.title": {
        "uz": "Zayavka bekor qilindi",
        "ru": "Заявка отменена",
    },
    # --- zayavkalar: matn ---
    "request_created.body": {
        "uz": "{start} — {end}",
        "ru": "{start} — {end}",
    },
    "request_created.body_with_address": {
        "uz": "{start} — {end}, {address}",
        "ru": "{start} — {end}, {address}",
    },
    "request_offer.body": {
        "uz": "{model} — {price} so'm/kun",
        "ru": "{model} — {price} сум/день",
    },
    "request_offer_accepted.body": {
        "uz": "Buyurtma #{order_id} yaratildi",
        "ru": "Создан заказ #{order_id}",
    },
    "request_offer_rejected.body": {
        "uz": "Zayavka #{request_id} bo'yicha boshqa taklif tanlandi",
        "ru": "По заявке #{request_id} выбрали другое предложение",
    },
    "request_cancelled.body": {
        "uz": "Zayavka #{request_id} mijoz tomonidan bekor qilindi",
        "ru": "Заявка #{request_id} отменена клиентом",
    },
    # --- e'lonlar ---
    "listing_taken.title": {
        "uz": "E'loningizni oldilar",
        "ru": "На ваше объявление откликнулись",
    },
    "listing_taken.body": {
        "uz": "{who} «{title}» e'loningizni olmoqchi. Tasdiqlaysizmi?",
        "ru": "{who} готов взяться за «{title}». Подтвердите исполнителя.",
    },
    "listing_confirmed.title": {
        "uz": "Sizni tasdiqladilar",
        "ru": "Клиент подтвердил вас",
    },
    "listing_confirmed.body": {
        "uz": "«{title}» bo'yicha ishni boshlashingiz mumkin. Telefon endi ochiq.",
        "ru": "Можно приступать к «{title}». Телефон клиента теперь открыт.",
    },
    "listing_offer.title": {
        "uz": "E'loningizga narx taklif qilindi",
        "ru": "На ваше объявление предложили цену",
    },
    "listing_offer.body": {
        "uz": "{who}: «{title}» uchun {price} so'm",
        "ru": "{who}: {price} сум за «{title}»",
    },
    "listing_offer_accepted.title": {
        "uz": "Taklifingiz qabul qilindi",
        "ru": "Ваше предложение приняли",
    },
    "listing_offer_accepted.body": {
        "uz": "«{title}» bo'yicha ishni boshlashingiz mumkin. Telefon endi ochiq.",
        "ru": "Можно приступать к «{title}». Телефон теперь открыт.",
    },
    "listing_rejected.title": {
        "uz": "Mijoz boshqasini tanladi",
        "ru": "Клиент выбрал другого",
    },
    "listing_rejected.body": {
        "uz": "«{title}» e'loni yana ochiq",
        "ru": "Объявление «{title}» снова открыто",
    },
    "listing_cancelled.title": {
        "uz": "E'lon bekor qilindi",
        "ru": "Объявление отменено",
    },
    "listing_cancelled.body": {
        "uz": "«{title}» e'loni mijoz tomonidan bekor qilindi",
        "ru": "Клиент отменил объявление «{title}»",
    },
    "listing_done.title": {
        "uz": "Ish yakunlandi",
        "ru": "Работа завершена",
    },
    "listing_done.body": {
        "uz": "«{title}» yakunlangan deb belgilandi",
        "ru": "«{title}» отмечено как выполненное",
    },
    # --- pul harakati izohlari ---
    #
    # Bu satrlar bazaga tayyor matn bo'lib yoziladi va ilovada "Amallar
    # tarixi"da shundayligicha ko'rinadi. Shuning uchun ular OLUVCHINING
    # tilida yoziladi: mijozning izohi — mijoz tilida, eganiki — ega tilida.
    #
    # Daromad izohida foiz YO'Q. Ilgari "(90%)" deb yozilardi, komissiya esa
    # allaqachon qat'iy 5 000 so'm: 1 907 400 dan 1 902 400 qoldi, bu 90% emas.
    # Foizni umuman yozmaymiz — u sozlamadan o'zgaradi, matn esa bazada qotib
    # qoladi va yana yolg'on bo'lib qoladi.
    "tx.order_completed": {
        "uz": "Buyurtma #{order_id} yakunlandi — {what}",
        "ru": "Заказ #{order_id} завершён — {what}",
    },
    "tx.order_income": {
        "uz": "Buyurtma #{order_id} dan daromad — {what}",
        "ru": "Доход с заказа #{order_id} — {what}",
    },
    "tx.order_commission": {
        "uz": "Buyurtma #{order_id} dan komissiya — {what}",
        "ru": "Комиссия с заказа #{order_id} — {what}",
    },
    "tx.order_rejected": {
        "uz": "Buyurtma #{order_id} rad etildi — {what}",
        "ru": "Заказ #{order_id} отклонён — {what}",
    },
    "tx.order_cancelled": {
        "uz": "Buyurtma #{order_id} bekor qilindi — {what}",
        "ru": "Заказ #{order_id} отменён — {what}",
    },
    "tx.order_cancelled_returned": {
        "uz": "Buyurtma #{order_id} bekor qilindi, pul qaytarildi — {what}",
        "ru": "Заказ #{order_id} отменён, деньги возвращены — {what}",
    },
    # --- qurilish materiallari ---
    "material_approved.title": {
        "uz": "Tovar tasdiqlandi",
        "ru": "Товар одобрен",
    },
    "material_approved.body": {
        "uz": "«{title}» endi katalogda ko'rinadi",
        "ru": "«{title}» теперь виден в каталоге",
    },
    "material_rejected.title": {
        "uz": "Tovar rad etildi",
        "ru": "Товар отклонён",
    },
    "material_rejected.body": {
        "uz": "«{title}» katalogga qo'yilmadi. {reason}",
        "ru": "«{title}» не попал в каталог. {reason}",
    },
    "material_order.title": {
        "uz": "Yangi material buyurtmasi",
        "ru": "Новый заказ материала",
    },
    "material_order.body": {
        "uz": "«{title}» — {quantity} birlik. Tasdiqlaysizmi?",
        "ru": "«{title}» — {quantity} ед. Подтвердите заказ",
    },
    "material_confirmed.title": {
        "uz": "Buyurtma tasdiqlandi",
        "ru": "Заказ подтверждён",
    },
    "material_confirmed.body": {
        "uz": "Buyurtma #{order_number} yo'lga tayyor",
        "ru": "Заказ #{order_number} принят продавцом",
    },
    "material_delivered.title": {
        "uz": "Yetkazildi, pul o'tdi",
        "ru": "Доставлено, деньги перечислены",
    },
    "material_delivered.body": {
        "uz": "Buyurtma #{order_number} bo'yicha pul hisobingizga tushdi",
        "ru": "Деньги по заказу #{order_number} зачислены на баланс",
    },
    "material_cancelled.title": {
        "uz": "Material buyurtmasi bekor qilindi",
        "ru": "Заказ материала отменён",
    },
    "material_cancelled.body": {
        "uz": "Buyurtma #{order_number} yopildi",
        "ru": "Заказ #{order_number} закрыт",
    },
    "tx.topup": {
        "uz": "Hisobni to'ldirish — {method}",
        "ru": "Пополнение счёта — {method}",
    },
    "tx.payout": {
        "uz": "Pul yechish #{request_id} — karta {card}",
        "ru": "Вывод средств #{request_id} — карта {card}",
    },
    # Komissiya ushlangan holat. Alohida matn kerak: aks holda egasi
    # tarixda 100 000 yechilganini ko'radi, kartasiga esa 95 000 tushadi
    # va farq qayerga ketganini hech qayerdan bilolmaydi.
    "tx.payout_with_commission": {
        "uz": "Pul yechish #{request_id} — karta {card}. "
              "Kartaga {net} so'm, komissiya {commission} so'm",
        "ru": "Вывод средств #{request_id} — карта {card}. "
              "На карту {net} сум, комиссия {commission} сум",
    },
    # E'lon bo'yicha pul harakati. Buyurtmadagidek, lekin e'lon raqami bilan.
    "tx.listing_payment": {
        "uz": "E'lon #{listing_id} uchun to'lov — {title}",
        "ru": "Оплата по объявлению #{listing_id} — {title}",
    },
    "tx.listing_income": {
        "uz": "E'lon #{listing_id} bo'yicha daromad — {title}",
        "ru": "Доход по объявлению #{listing_id} — {title}",
    },
    "tx.listing_commission": {
        "uz": "E'lon #{listing_id} ulushi — {title}",
        "ru": "Комиссия по объявлению #{listing_id} — {title}",
    },
    # Ro'yxatdan o'tgan texnika egasiga beriladigan sovg'a.
    "tx.signup_bonus": {
        "uz": "Ro'yxatdan o'tganlik uchun bonus",
        "ru": "Бонус за регистрацию",
    },
    # Faqat OTP_TEST_MODE da ko'rinadi, prodda hech qachon chiqmaydi.
    "test_mode.code": {
        "uz": "TEST REJIMI: tasdiqlash kodi {code}",
        "ru": "ТЕСТОВЫЙ РЕЖИМ: код подтверждения {code}",
    },
}


def normalize_language(value: Optional[str]) -> str:
    if not value:
        return DEFAULT_LANGUAGE
    code = str(value).strip().lower()[:2]
    return code if code in SUPPORTED_LANGUAGES else DEFAULT_LANGUAGE


def _format_dates(params: dict) -> dict:
    """
    Sana obyektlarini 16.08.2040 ko'rinishiga keltiradi.

    format() ularni ISO ko'rinishida chiqarardi ("2040-08-16") — bu
    interfeysdagi barcha boshqa sanalardan farq qilardi.
    """
    out = {}
    for key, value in params.items():
        if hasattr(value, "strftime"):
            out[key] = value.strftime("%d.%m.%Y")
        else:
            out[key] = value
    return out


def t(key: str, language: Optional[str] = None, **params) -> str:
    """
    Kalit bo'yicha matn.

    Kalit topilmasa kalitning o'zi qaytadi — bu ko'rinadigan xato bo'ladi
    va tez tuzatiladi, jimgina bo'sh satr qaytarishdan yaxshiroq.
    """
    lang = normalize_language(language)
    template = MESSAGES.get(key, {}).get(lang)
    if template is None:
        template = MESSAGES.get(key, {}).get(DEFAULT_LANGUAGE)
    if template is None:
        return key
    try:
        return template.format(**_format_dates(params))
    except (KeyError, IndexError):
        # Shablonga argument yetmasa ham xabarnoma yozilishi kerak
        return template
