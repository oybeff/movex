"""
Компенсация владельцу за напрасный выезд (макет водителя E1, E7).

E1 — клиент отменил заказ, когда техника уже выехала («Ketdik»).
E7 — техника на месте, клиент не вышел за NO_SHOW_WAIT_MINUTES.

Правила (нарушать нельзя):

- Сумма — `app_settings.cancel_compensation_amount` (commission.php).
  По умолчанию 0 — ВЫКЛЮЧЕНО: Шерзодбек 21.11.2026 решил, что залог
  клиента не списывается никогда, и до его решения в админке поведение
  не меняется.
- Платит клиент из того, что УЖЕ заморожено под этот заказ: залог за
  наличный заказ (equipment_requests.frozen_amount) или эскроу заказа с
  баланса (orders.frozen_amount). Сверх заморозки не берём никогда —
  клиент не уходит в минус. Заказ картой: холд снимается целиком,
  компенсации нет (частичное списание с карты — отдельная работа).
- Бонус клиента компенсацией не становится: берём не больше
  `balance - bonus_balance`. Иначе бонус превращался бы в живые деньги
  владельца, которые выводятся на карту.
- Сумма пишется в orders.compensation в момент отмены — смена ставки
  потом историю не переписывает.
- Функция вызывается ДО того, как остаток заморозки вернут клиенту, и
  сама ничего не коммитит.
"""
from decimal import Decimal

from sqlalchemy.orm import Session

from app.core.messages import t
from app.models.app_settings import AppSettings
from app.models.balance import Balance, BalanceTransaction
from app.models.equipment_request import EquipmentRequest
from app.models.order import Order

SETTING_KEY = "cancel_compensation_amount"
#: Макет E7: «15 daqiqa kutdingiz va mijoz javob bermadi».
NO_SHOW_WAIT_MINUTES = 15


def amount_setting(db: Session) -> Decimal:
    row = db.query(AppSettings).filter(AppSettings.key == SETTING_KEY).first()
    try:
        value = Decimal(str(row.value)) if row is not None and row.value not in (None, "") else Decimal("0")
    except Exception:
        value = Decimal("0")
    return value if value > 0 else Decimal("0")


def _lang(db: Session, user_id: int):
    from app.models.user import User

    u = db.query(User).filter(User.id == user_id).first()
    return getattr(u, "language", None) if u else None


def compensate(db: Session, order: Order, owner_id: int) -> Decimal:
    """
    Переводит компенсацию с замороженных денег клиента владельцу.
    Возвращает переведённую сумму (0 — ничего не двигалось). Без commit.
    """
    want = amount_setting(db)
    if want <= 0 or (order.compensation or 0) > 0:
        return Decimal("0")

    method = getattr(order, "payment_method", None) or "balance"
    request = None
    if method == "cash":
        request = (
            db.query(EquipmentRequest)
            .filter(EquipmentRequest.order_id == order.id, EquipmentRequest.payment_method == "cash")
            .with_for_update()
            .first()
        )
        source = Decimal(str(request.frozen_amount or 0)) if request is not None else Decimal("0")
    elif method == "balance":
        source = Decimal(str(order.frozen_amount or 0))
    else:
        return Decimal("0")

    client = db.query(Balance).filter(Balance.user_id == order.user_id).with_for_update().first()
    if client is None or source <= 0:
        return Decimal("0")
    own_money = Decimal(str(client.balance or 0)) - Decimal(str(client.bonus_balance or 0))
    amount = min(want, source, own_money if own_money > 0 else Decimal("0"))
    if amount <= 0:
        return Decimal("0")

    owner = db.query(Balance).filter(Balance.user_id == owner_id).with_for_update().first()
    if owner is None:
        owner = Balance(user_id=owner_id, balance=Decimal("0"), frozen_balance=Decimal("0"))
        db.add(owner)
        db.flush()

    # Деньги клиента: уходят из заморозки И из баланса — это списание, не
    # разморозка. Остаток заморозки вернёт обычная ветка отмены.
    client.balance = Decimal(str(client.balance)) - amount
    frozen = Decimal(str(client.frozen_balance or 0)) - amount
    client.frozen_balance = frozen if frozen > 0 else Decimal("0")
    if request is not None:
        request.frozen_amount = Decimal(str(request.frozen_amount)) - amount
    else:
        order.frozen_amount = Decimal(str(order.frozen_amount)) - amount

    owner.balance = Decimal(str(owner.balance or 0)) + amount
    order.compensation = amount

    db.add(BalanceTransaction(
        user_id=order.user_id,
        amount=amount,
        type="payment",
        status="completed",
        description=t("tx.compensation_paid", _lang(db, order.user_id), order_id=order.id),
        order_id=order.id,
    ))
    db.add(BalanceTransaction(
        user_id=owner_id,
        amount=amount,
        type="income",
        status="completed",
        description=t("tx.compensation_received", _lang(db, owner_id), order_id=order.id),
        order_id=order.id,
    ))
    return amount
