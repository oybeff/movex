"""
Бонус тем владельцам техники, которые зарегистрировались ДО его появления.

Зачем нужен отдельный скрипт. `grant_signup_bonus` вызывается ровно в одном
месте — внутри `/auth/register`, в момент создания аккаунта. Бонус появился
5 сентября 2026, и все, кто зарегистрировался раньше, не получили ничего.
Начисления задним числом в коде нет и быть не должно: это разовое действие,
а не правило системы.

Движение денег тут НЕ дублируется — скрипт зовёт `balance_service.credit_bonus`,
ту же функцию, что и регистрация. Иначе в одной из двух копий рано или поздно
забыли бы поднять `bonus_balance`, и подарок стало бы можно вывести на карту.

ИДЕМПОТЕНТЕН. Признак «уже получил» — транзакция типа `bonus`, а не остаток
на балансе: подарок могли потратить, и проверка по балансу выдала бы его
второй раз.

По умолчанию НИЧЕГО НЕ МЕНЯЕТ — только показывает, кому и сколько уйдёт.
Деньги двигаются лишь с `--apply`.

Запуск (из backend/):

    venv/bin/python scripts/grant_bonus_to_existing_owners.py             # показать
    venv/bin/python scripts/grant_bonus_to_existing_owners.py --apply     # начислить
    venv/bin/python scripts/grant_bonus_to_existing_owners.py --apply --amount 50000
    venv/bin/python scripts/grant_bonus_to_existing_owners.py --apply --yes   # без вопроса

На проде запускать под тем же пользователем, под которым работает сервис —
настройки берутся из `.env` рядом с приложением.
"""
import argparse
import os
import sys
from decimal import Decimal, InvalidOperation

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

from app.db.session import SessionLocal          # noqa: E402
from app.models.user import User                 # noqa: E402
from app.services import balance_service         # noqa: E402

ROLE = "owner"


def money(value) -> str:
    return f"{int(Decimal(str(value))):,}".replace(",", " ")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Начислить бонус владельцам, которые его ещё не получали",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="действительно начислить (без флага — только показать список)",
    )
    parser.add_argument(
        "--amount",
        default=None,
        help="сумма в сумах; по умолчанию берётся из настроек админки",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="не спрашивать подтверждение (для неинтерактивного запуска)",
    )
    return parser.parse_args()


def resolve_amount(db, raw) -> Decimal:
    """
    Сумма: из аргумента, иначе из настроек админки.

    Настройка `signup_bonus_enabled` здесь СОЗНАТЕЛЬНО не смотрится. Она
    отвечает на вопрос «выдавать ли новым при регистрации», а мы отвечаем
    на другой — «доначислить ли старым». Иначе при выключенном тумблере
    скрипт молча не делал бы ничего, и было бы непонятно почему.
    """
    if raw is not None:
        try:
            amount = Decimal(str(raw))
        except (InvalidOperation, TypeError, ValueError):
            raise SystemExit(f"не похоже на сумму: {raw!r}")
        if amount <= 0:
            raise SystemExit("сумма должна быть больше нуля")
        return amount

    amount = balance_service.get_signup_bonus_amount(db)
    if amount <= 0:
        raise SystemExit(
            "в настройках стоит нулевая сумма бонуса — задайте её в админке "
            "(commission.php) или передайте --amount"
        )
    return amount


def main():
    args = parse_args()
    db = SessionLocal()

    try:
        amount = resolve_amount(db, args.amount)

        owners = (
            db.query(User)
            .filter(User.role == ROLE)
            .order_by(User.id)
            .all()
        )
        pending = [u for u in owners if not balance_service.has_signup_bonus(db, u.id)]

        print(f"владельцев техники всего:       {len(owners)}")
        print(f"уже получали бонус:             {len(owners) - len(pending)}")
        print(f"получат сейчас:                 {len(pending)}")
        print(f"сумма каждому:                  {money(amount)} сум")
        print(f"итого будет начислено:          {money(amount * len(pending))} сум")

        if not pending:
            print("\nначислять некому — все владельцы бонус уже получили")
            return 0

        print("\n  id     телефон           имя")
        print("  " + "-" * 56)
        for user in pending:
            name = (user.full_name or "")[:28]
            print(f"  {user.id:<6} {(user.phone or ''):<17} {name}")

        if not args.apply:
            print(
                "\nНИЧЕГО НЕ ИЗМЕНЕНО. Это предпросмотр — чтобы начислить, "
                "добавьте --apply"
            )
            return 0

        if not args.yes:
            # Деньги — действие необратимое, поэтому спрашиваем явно.
            answer = input(
                f"\nНачислить {money(amount)} сум {len(pending)} владельцам? [y/N] "
            ).strip().lower()
            if answer not in ("y", "yes", "д", "да"):
                print("отменено, ничего не изменено")
                return 1

        granted = 0
        failed = []
        for user in pending:
            # Ещё одна проверка перед самой записью: между предпросмотром и
            # начислением человек мог зарегистрироваться заново или другой
            # запуск скрипта мог успеть выдать бонус.
            if balance_service.has_signup_bonus(db, user.id):
                continue
            try:
                balance_service.credit_bonus(db, user, amount)
                granted += 1
                print(f"  [OK]   {user.id:<6} {user.phone}")
            except Exception as error:      # noqa: BLE001 — причину показываем
                db.rollback()
                failed.append((user.id, str(error)))
                print(f"  [FAIL] {user.id:<6} {user.phone}  {error}")

        print(f"\nначислено: {granted} из {len(pending)}")
        if failed:
            print(f"не удалось: {len(failed)} — их можно повторить тем же запуском, "
                  f"повторно никому не начислится")
            return 1
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
