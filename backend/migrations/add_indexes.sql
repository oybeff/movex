-- УСТАРЕЛО. Не применяйте этот файл вручную.
--
-- Индексы перенесены в миграцию Alembic:
--   alembic/versions/2026_08_30_add_performance_indexes.py
--
-- Файл лежал здесь и никогда не применялся: в базе не было ни одного из
-- этих индексов. Оставлен для истории — имена в миграции другие (ix_*),
-- запуск этого файла создаст дубликаты.

-- ==============================
-- Индексы для оптимизации производительности
-- ==============================

-- Индексы для таблицы equipment
CREATE INDEX IF NOT EXISTS idx_equipment_owner ON equipment(owner_id);
CREATE INDEX IF NOT EXISTS idx_equipment_type ON equipment(type);
CREATE INDEX IF NOT EXISTS idx_equipment_status ON equipment(status);
CREATE INDEX IF NOT EXISTS idx_equipment_lat_lng ON equipment(latitude, longitude);

-- Дополнительные индексы для других таблиц
CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_equipment ON orders(equipment_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);

CREATE INDEX IF NOT EXISTS idx_messages_chat ON messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);

CREATE INDEX IF NOT EXISTS idx_reviews_equipment ON reviews(equipment_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user ON reviews(user_id);

CREATE INDEX IF NOT EXISTS idx_payments_order ON payments(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);

