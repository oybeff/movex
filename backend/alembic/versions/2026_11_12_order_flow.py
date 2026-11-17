"""Ход тарифного заказа, госномер техники, время подачи тарифа

- orders.departed_at / started_at / finished_at — владелец нажал
  «Ketdik», «Boshlash», «Yakunlash» (второй макет, экраны 8 и 9 клиента).
  Клиент видит «Texnika yo'lda», таймер работы и подтверждает конец.
- equipment.plate_number — «Davlat raqami» (макет владельца R4, карточка
  исполнителя у клиента).
- tariffs.eta_minutes — «45 daqiqada keladi» в карточке тарифа. Задаёт
  админ; пусто — подпись без минут.

Revision ID: d8b3f6a2c917
Revises: c5a9e2f71d34
Create Date: 2026-11-12
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = 'd8b3f6a2c917'
down_revision: Union[str, Sequence[str], None] = 'c5a9e2f71d34'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('orders', sa.Column('departed_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('orders', sa.Column('started_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('orders', sa.Column('finished_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('equipment', sa.Column('plate_number', sa.String(20), nullable=True))
    op.add_column('tariffs', sa.Column('eta_minutes', sa.Integer(), nullable=True))
    op.create_check_constraint(
        'check_tariff_eta', 'tariffs', 'eta_minutes IS NULL OR eta_minutes BETWEEN 1 AND 1440'
    )


def downgrade() -> None:
    op.drop_constraint('check_tariff_eta', 'tariffs', type_='check')
    op.drop_column('tariffs', 'eta_minutes')
    op.drop_column('equipment', 'plate_number')
    op.drop_column('orders', 'finished_at')
    op.drop_column('orders', 'started_at')
    op.drop_column('orders', 'departed_at')
