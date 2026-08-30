"""
Payme (Paycom) Merchant API integratsiyasi.

Payme bizga JSON-RPC 2.0 so'rovlarini yuboradi, biz javob qaytaramiz.
Protokol: https://developer.help.paycom.uz/

Muhim jihatlar:
  * summalar TIYINDA keladi (1 so'm = 100 tiyin), bazada esa so'mda saqlanadi;
  * vaqtlar millisekundlarda;
  * autentifikatsiya: Authorization: Basic base64("Paycom:" + kassa kaliti);
  * tranzaksiya holatlari: 1 yaratilgan, 2 o'tkazilgan,
    -1 bekor qilingan, -2 o'tkazilgandan keyin bekor qilingan.

To'lovni bo'lish (split) `receivers` maydoni orqali beriladi: Payme pulni
ro'yxatdagi qabul qiluvchilar o'rtasida o'zi taqsimlaydi.
"""
import base64
import time
from decimal import Decimal
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.balance import BalanceTransaction
from app.models.equipment import Equipment
from app.models.order import Order
from app.models.user import User

# --- protokol doimiylari ---------------------------------------------------

STATE_CREATED = 1
STATE_PERFORMED = 2
STATE_CANCELLED = -1
STATE_CANCELLED_AFTER_PERFORM = -2

# Umumiy xatolar
ERR_NOT_POST = -32300
ERR_PARSE = -32700
ERR_INVALID_REQUEST = -32600
ERR_METHOD_NOT_FOUND = -32601
ERR_INSUFFICIENT_PRIVILEGES = -32504
ERR_INTERNAL = -32400

# Merchant xatolari
ERR_INVALID_AMOUNT = -31001
ERR_TRANSACTION_NOT_FOUND = -31003
ERR_CANNOT_CANCEL = -31007
ERR_CANNOT_PERFORM = -31008
# -31050..-31099 — `account` maydonidagi noto'g'ri ma'lumot
ERR_ACCOUNT_NOT_FOUND = -31050

# Payme talabi: 12 soatdan oshgan, hali o'tkazilmagan tranzaksiya bekor qilinadi
TRANSACTION_TIMEOUT_MS = 12 * 60 * 60 * 1000

# Hisobni to'ldirish chegaralari (balance_service bilan bir xil)
MIN_AMOUNT_SUM = Decimal("10000")
MAX_AMOUNT_SUM = Decimal("10000000")


def _msg(ru: str, uz: str, en: str) -> Dict[str, str]:
    """Payme xato matnini uch tilda kutadi."""
    return {"ru": ru, "uz": uz, "en": en}


class PaymeError(Exception):
    """JSON-RPC xatosiga aylanadigan istisno."""

    def __init__(self, code: int, message: Dict[str, str], data: Optional[str] = None):
        super().__init__(message.get("ru", ""))
        self.code = code
        self.message = message
        self.data = data

    def to_response(self, request_id: Any) -> Dict[str, Any]:
        error: Dict[str, Any] = {"code": self.code, "message": self.message}
        if self.data is not None:
            error["data"] = self.data
        return {"error": error, "id": request_id}


def now_ms() -> int:
    return int(time.time() * 1000)


def tiyin_to_sum(amount_tiyin: Any) -> Decimal:
    return (Decimal(str(amount_tiyin)) / Decimal("100")).quantize(Decimal("0.01"))


def sum_to_tiyin(amount_sum: Any) -> int:
    return int((Decimal(str(amount_sum)) * Decimal("100")).to_integral_value())


class PaymeService:
    """Merchant API metodlarini bajaradi."""

    # ---------------------------------------------------------------- auth

    @staticmethod
    def check_auth(authorization: Optional[str]) -> None:
        """
        Payme "Basic base64('Paycom:' + kalit)" yuboradi.
        Kalit mos kelmasa — -32504.
        """
        expected_key = settings.payme_active_key
        if not expected_key:
            raise PaymeError(
                ERR_INSUFFICIENT_PRIVILEGES,
                _msg("Payme не настроен", "Payme sozlanmagan", "Payme is not configured"),
            )

        if not authorization or not authorization.lower().startswith("basic "):
            raise PaymeError(
                ERR_INSUFFICIENT_PRIVILEGES,
                _msg("Недостаточно прав", "Huquqlar yetarli emas", "Insufficient privileges"),
            )

        try:
            decoded = base64.b64decode(authorization.split(" ", 1)[1]).decode("utf-8")
            login, _, key = decoded.partition(":")
        except Exception:
            raise PaymeError(
                ERR_INSUFFICIENT_PRIVILEGES,
                _msg("Недостаточно прав", "Huquqlar yetarli emas", "Insufficient privileges"),
            )

        # Payme har doim "Paycom" login bilan keladi
        if login != "Paycom" or key != expected_key:
            raise PaymeError(
                ERR_INSUFFICIENT_PRIVILEGES,
                _msg("Недостаточно прав", "Huquqlar yetarli emas", "Insufficient privileges"),
            )

    # ------------------------------------------------------------- helpers

    @staticmethod
    def _account_value(params: Dict[str, Any]) -> str:
        account = params.get("account") or {}
        field = settings.PAYME_ACCOUNT_FIELD
        value = account.get(field)
        if value in (None, ""):
            raise PaymeError(
                ERR_ACCOUNT_NOT_FOUND,
                _msg("Неверный номер счёта", "Hisob raqami noto'g'ri", "Invalid account"),
                data=field,
            )
        return str(value)

    @classmethod
    def _find_our_transaction(cls, db: Session, params: Dict[str, Any]) -> BalanceTransaction:
        """`account` bo'yicha bizning to'ldirish arizamizni topadi."""
        raw = cls._account_value(params)
        try:
            tx_id = int(raw)
        except (TypeError, ValueError):
            raise PaymeError(
                ERR_ACCOUNT_NOT_FOUND,
                _msg("Неверный номер счёта", "Hisob raqami noto'g'ri", "Invalid account"),
                data=settings.PAYME_ACCOUNT_FIELD,
            )

        transaction = (
            db.query(BalanceTransaction)
            .filter(BalanceTransaction.id == tx_id)
            .first()
        )
        if transaction is None:
            raise PaymeError(
                ERR_ACCOUNT_NOT_FOUND,
                _msg("Счёт не найден", "Hisob topilmadi", "Account not found"),
                data=settings.PAYME_ACCOUNT_FIELD,
            )
        return transaction

    @staticmethod
    def _find_by_payme_id(db: Session, payme_id: str) -> BalanceTransaction:
        transaction = (
            db.query(BalanceTransaction)
            .filter(BalanceTransaction.payme_transaction_id == str(payme_id))
            .first()
        )
        if transaction is None:
            raise PaymeError(
                ERR_TRANSACTION_NOT_FOUND,
                _msg("Транзакция не найдена", "Tranzaksiya topilmadi", "Transaction not found"),
            )
        return transaction

    @classmethod
    def _validate_amount(cls, transaction: BalanceTransaction, amount_tiyin: Any) -> None:
        """Payme yuborgan summa bizdagi ariza summasiga teng bo'lishi shart."""
        try:
            incoming = tiyin_to_sum(amount_tiyin)
        except Exception:
            raise PaymeError(
                ERR_INVALID_AMOUNT,
                _msg("Неверная сумма", "Summa noto'g'ri", "Invalid amount"),
            )

        if incoming != Decimal(str(transaction.amount)):
            raise PaymeError(
                ERR_INVALID_AMOUNT,
                _msg("Неверная сумма", "Summa noto'g'ri", "Invalid amount"),
            )

    @staticmethod
    def _receivers_for(db: Session, transaction: BalanceTransaction) -> Optional[List[Dict[str, Any]]]:
        """
        To'lovni bo'lish ro'yxati.

        Hisobni to'ldirishda bo'lish YO'Q: pul mijozning o'z hisobiga tushadi.
        Buyurtma uchun to'g'ridan-to'g'ri to'lovda esa (SPLIT_MODE='on_payment')
        texnika egasiga uning ulushi ajratiladi, komissiya platformada qoladi.

        Egasida Payme qabul qiluvchi identifikatori bo'lmasa — bo'lish o'tkazib
        yuboriladi va pul odatdagidek platformaga tushadi.
        """
        if settings.SPLIT_MODE != "on_payment":
            return None
        if transaction.order_id is None:
            return None

        order = db.query(Order).filter(Order.id == transaction.order_id).first()
        if order is None:
            return None

        equipment = db.query(Equipment).filter(Equipment.id == order.equipment_id).first()
        if equipment is None:
            return None

        owner = db.query(User).filter(User.id == equipment.owner_id).first()
        if owner is None or not owner.payme_receiver_id:
            return None

        owner_share = Decimal(str(order.total_amount)) - Decimal(str(order.commission))
        if owner_share <= 0:
            return None

        return [{"id": owner.payme_receiver_id, "amount": sum_to_tiyin(owner_share)}]

    # --------------------------------------------------------- API methods

    @classmethod
    def check_perform_transaction(cls, db: Session, params: Dict[str, Any]) -> Dict[str, Any]:
        transaction = cls._find_our_transaction(db, params)

        if transaction.type != "topup":
            raise PaymeError(
                ERR_ACCOUNT_NOT_FOUND,
                _msg("Счёт не найден", "Hisob topilmadi", "Account not found"),
                data=settings.PAYME_ACCOUNT_FIELD,
            )

        if transaction.status == "completed":
            raise PaymeError(
                ERR_CANNOT_PERFORM,
                _msg("Счёт уже оплачен", "Hisob allaqachon to'langan", "Already paid"),
            )

        amount = Decimal(str(transaction.amount))
        if amount < MIN_AMOUNT_SUM or amount > MAX_AMOUNT_SUM:
            raise PaymeError(
                ERR_INVALID_AMOUNT,
                _msg("Неверная сумма", "Summa noto'g'ri", "Invalid amount"),
            )

        cls._validate_amount(transaction, params.get("amount"))

        result: Dict[str, Any] = {"allow": True}
        receivers = cls._receivers_for(db, transaction)
        if receivers:
            result["receivers"] = receivers
        return result

    @classmethod
    def create_transaction(cls, db: Session, params: Dict[str, Any]) -> Dict[str, Any]:
        payme_id = str(params.get("id"))
        transaction = cls._find_our_transaction(db, params)

        # Shu Payme tranzaksiyasi allaqachon bog'langan bo'lsa — takroriy so'rov
        if transaction.payme_transaction_id == payme_id:
            if transaction.payme_state != STATE_CREATED:
                raise PaymeError(
                    ERR_CANNOT_PERFORM,
                    _msg("Транзакция не в том состоянии", "Tranzaksiya holati mos emas",
                         "Transaction is in wrong state"),
                )
            # 12 soatdan oshgan bo'lsa — bekor qilamiz
            if now_ms() - (transaction.payme_create_time or 0) > TRANSACTION_TIMEOUT_MS:
                transaction.payme_state = STATE_CANCELLED
                transaction.payme_cancel_time = now_ms()
                transaction.payme_reason = 4  # muddati o'tgan
                transaction.status = "canceled"
                db.commit()
                raise PaymeError(
                    ERR_CANNOT_PERFORM,
                    _msg("Время транзакции истекло", "Tranzaksiya muddati tugagan",
                         "Transaction timed out"),
                )
            return {
                "create_time": transaction.payme_create_time,
                "transaction": str(transaction.id),
                "state": STATE_CREATED,
            }

        # Bu ariza bo'yicha boshqa tranzaksiya ochiq bo'lsa — yangisini bermaymiz
        if transaction.payme_transaction_id and transaction.payme_state == STATE_CREATED:
            raise PaymeError(
                ERR_CANNOT_PERFORM,
                _msg("По счёту уже есть незавершённая транзакция",
                     "Hisob bo'yicha tugallanmagan tranzaksiya bor",
                     "Another transaction is pending for this account"),
            )

        # Yaratishdan oldin — odatdagi tekshiruvlar
        cls.check_perform_transaction(db, params)

        transaction.payme_transaction_id = payme_id
        transaction.payme_state = STATE_CREATED
        transaction.payme_create_time = now_ms()
        transaction.payment_method = "payme"
        transaction.status = "pending"
        db.commit()
        db.refresh(transaction)

        return {
            "create_time": transaction.payme_create_time,
            "transaction": str(transaction.id),
            "state": STATE_CREATED,
        }

    @classmethod
    def perform_transaction(cls, db: Session, params: Dict[str, Any]) -> Dict[str, Any]:
        transaction = cls._find_by_payme_id(db, params.get("id"))

        # Takroriy so'rov — o'sha javobni qaytaramiz
        if transaction.payme_state == STATE_PERFORMED:
            return {
                "transaction": str(transaction.id),
                "perform_time": transaction.payme_perform_time,
                "state": STATE_PERFORMED,
            }

        if transaction.payme_state != STATE_CREATED:
            raise PaymeError(
                ERR_CANNOT_PERFORM,
                _msg("Транзакция не в том состоянии", "Tranzaksiya holati mos emas",
                     "Transaction is in wrong state"),
            )

        if now_ms() - (transaction.payme_create_time or 0) > TRANSACTION_TIMEOUT_MS:
            transaction.payme_state = STATE_CANCELLED
            transaction.payme_cancel_time = now_ms()
            transaction.payme_reason = 4
            transaction.status = "canceled"
            db.commit()
            raise PaymeError(
                ERR_CANNOT_PERFORM,
                _msg("Время транзакции истекло", "Tranzaksiya muddati tugagan",
                     "Transaction timed out"),
            )

        # Pulni hisobga o'tkazish. Import shu yerda — aylanma importni oldini oladi.
        from app.services.balance_service import update_balance

        update_balance(db, transaction.user_id, float(transaction.amount))

        transaction.payme_state = STATE_PERFORMED
        transaction.payme_perform_time = now_ms()
        transaction.status = "completed"
        db.commit()
        db.refresh(transaction)

        cls._notify_telegram(db, transaction)

        return {
            "transaction": str(transaction.id),
            "perform_time": transaction.payme_perform_time,
            "state": STATE_PERFORMED,
        }

    @classmethod
    def cancel_transaction(cls, db: Session, params: Dict[str, Any]) -> Dict[str, Any]:
        transaction = cls._find_by_payme_id(db, params.get("id"))
        reason = params.get("reason")

        if transaction.payme_state in (STATE_CANCELLED, STATE_CANCELLED_AFTER_PERFORM):
            return {
                "transaction": str(transaction.id),
                "cancel_time": transaction.payme_cancel_time,
                "state": transaction.payme_state,
            }

        if transaction.payme_state == STATE_CREATED:
            transaction.payme_state = STATE_CANCELLED
            transaction.status = "canceled"
        else:
            # O'tkazilgan to'lovni qaytarish: pul hisobdan yechiladi.
            # Mijoz pulni sarflab ulgurgan bo'lsa, bekor qilib bo'lmaydi —
            # aks holda balans manfiy bo'lib qolardi.
            from app.services.balance_service import get_or_create_balance

            balance = get_or_create_balance(db, transaction.user_id)
            available = Decimal(str(balance.balance)) - Decimal(str(balance.frozen_balance))
            if available < Decimal(str(transaction.amount)):
                raise PaymeError(
                    ERR_CANNOT_CANCEL,
                    _msg("Средства уже израсходованы, отмена невозможна",
                         "Mablag' sarflangan, bekor qilib bo'lmaydi",
                         "Funds already spent, cannot cancel"),
                )
            balance.balance = Decimal(str(balance.balance)) - Decimal(str(transaction.amount))
            transaction.payme_state = STATE_CANCELLED_AFTER_PERFORM
            transaction.status = "canceled"

        transaction.payme_cancel_time = now_ms()
        transaction.payme_reason = reason
        db.commit()
        db.refresh(transaction)

        return {
            "transaction": str(transaction.id),
            "cancel_time": transaction.payme_cancel_time,
            "state": transaction.payme_state,
        }

    @classmethod
    def check_transaction(cls, db: Session, params: Dict[str, Any]) -> Dict[str, Any]:
        transaction = cls._find_by_payme_id(db, params.get("id"))
        return {
            "create_time": transaction.payme_create_time or 0,
            "perform_time": transaction.payme_perform_time or 0,
            "cancel_time": transaction.payme_cancel_time or 0,
            "transaction": str(transaction.id),
            "state": transaction.payme_state,
            "reason": transaction.payme_reason,
        }

    @classmethod
    def get_statement(cls, db: Session, params: Dict[str, Any]) -> Dict[str, Any]:
        start = params.get("from")
        end = params.get("to")
        if start is None or end is None:
            raise PaymeError(
                ERR_INVALID_REQUEST,
                _msg("Неверные параметры", "Parametrlar noto'g'ri", "Invalid params"),
            )

        rows = (
            db.query(BalanceTransaction)
            .filter(
                BalanceTransaction.payme_transaction_id.isnot(None),
                BalanceTransaction.payme_create_time >= start,
                BalanceTransaction.payme_create_time <= end,
            )
            .order_by(BalanceTransaction.payme_create_time)
            .all()
        )

        return {
            "transactions": [
                {
                    "id": row.payme_transaction_id,
                    "time": row.payme_create_time,
                    "amount": sum_to_tiyin(row.amount),
                    "account": {settings.PAYME_ACCOUNT_FIELD: str(row.id)},
                    "create_time": row.payme_create_time or 0,
                    "perform_time": row.payme_perform_time or 0,
                    "cancel_time": row.payme_cancel_time or 0,
                    "transaction": str(row.id),
                    "state": row.payme_state,
                    "reason": row.payme_reason,
                }
                for row in rows
            ]
        }

    # ------------------------------------------------------------ dispatch

    METHODS = {
        "CheckPerformTransaction": "check_perform_transaction",
        "CreateTransaction": "create_transaction",
        "PerformTransaction": "perform_transaction",
        "CancelTransaction": "cancel_transaction",
        "CheckTransaction": "check_transaction",
        "GetStatement": "get_statement",
    }

    @classmethod
    def handle(cls, db: Session, method: str, params: Dict[str, Any]) -> Dict[str, Any]:
        handler_name = cls.METHODS.get(method)
        if handler_name is None:
            raise PaymeError(
                ERR_METHOD_NOT_FOUND,
                _msg("Метод не найден", "Metod topilmadi", "Method not found"),
                data=method,
            )
        return getattr(cls, handler_name)(db, params or {})

    # -------------------------------------------------------------- extras

    @staticmethod
    def _notify_telegram(db: Session, transaction: BalanceTransaction) -> None:
        """Telegram xatosi to'lovni buzmasligi kerak."""
        try:
            from app.models.user import User as UserModel
            from app.services.telegram_service import telegram_service

            user = db.query(UserModel).filter(UserModel.id == transaction.user_id).first()
            telegram_service.send_payment_notification(
                user_name=getattr(user, "full_name", "—"),
                phone_number=transaction.phone_number or getattr(user, "phone", "—"),
                amount=float(transaction.amount),
                transaction_id=transaction.id,
                payment_method="Payme",
            )
        except Exception:
            import logging

            logging.getLogger(__name__).exception("Payme: Telegram xabari yuborilmadi")

    @staticmethod
    def build_checkout_url(transaction_id: int, amount_sum: Any) -> str:
        """
        To'lov sahifasiga havola.
        Format: {checkout}/base64("m=<merchant>;ac.<field>=<id>;a=<tiyin>;c=<return>")
        """
        payload = (
            f"m={settings.PAYME_MERCHANT_ID};"
            f"ac.{settings.PAYME_ACCOUNT_FIELD}={transaction_id};"
            f"a={sum_to_tiyin(amount_sum)};"
            f"c={settings.PAYME_RETURN_URL}"
        )
        encoded = base64.b64encode(payload.encode("utf-8")).decode("utf-8")
        return f"{settings.PAYME_CHECKOUT_URL}/{encoded}"
