from sqlalchemy import CheckConstraint, Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.sql import func

from app.db.base import Base


class ClientRating(Base):
    """
    Оценка клиента водителем (макет водителя D6 «Mijozni baholang»).

    Одна на заказ: повторная оценка ПЕРЕПИСЫВАЕТ прежнюю, а не плодит
    новые — иначе один водитель мог бы утопить клиента десятком единиц.
    Отзывы клиента о технике — отдельная таблица `reviews`, их не смешиваем.
    """

    __tablename__ = "client_ratings"

    id = Column(Integer, primary_key=True)
    order_id = Column(Integer, ForeignKey("orders.id", ondelete="CASCADE"), nullable=False, unique=True)
    owner_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    client_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    rating = Column(Integer, nullable=False)
    # Коды плашек через запятую: on_time_pay,polite,exact_address,kept_waiting
    tags = Column(String(200), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        CheckConstraint("rating BETWEEN 1 AND 5", name="check_client_rating_value"),
    )
