-- Migration: Add budget_reserves table for commission tracking
-- Date: 2025-11-17
-- Description: Bu jadval har bir buyurtmadan olingan 10% komissiyani saqlaydi

-- Create budget_reserves table
CREATE TABLE IF NOT EXISTS budget_reserves (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    amount NUMERIC(12, 2) NOT NULL,
    description VARCHAR(500),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT check_budget_reserve_amount CHECK (amount > 0)
);

-- Create index on order_id for faster lookups
CREATE INDEX IF NOT EXISTS ix_budget_reserves_order_id ON budget_reserves(order_id);

-- Insert into alembic_version table to track this migration
INSERT INTO alembic_version (version_num) VALUES ('a1b2c3d4e5f6')
ON CONFLICT (version_num) DO NOTHING;

-- Success message
SELECT 'Budget reserves table created successfully!' as message;

