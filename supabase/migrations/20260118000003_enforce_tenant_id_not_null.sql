-- SAFETY MIGRATION: Enforce Tenant Isolation
-- Proactively fail any future INSERT that tries to create an orphan record.
-- This guarantees multi-tenant data integrity moving forward.

-- 1. stock_movements: Enforce tenant_id NOT NULL
ALTER TABLE stock_movements 
  ALTER COLUMN tenant_id SET NOT NULL;

-- 2. stock_adjustments: Enforce tenant_id NOT NULL
ALTER TABLE stock_adjustments 
  ALTER COLUMN tenant_id SET NOT NULL;

-- 3. Double-Check Constraint (Optional but good for documentation)
-- Most Postgres setups imply a check constraint with NOT NULL, but explicit checks are fine too if needed.
-- For standard columns, SET NOT NULL is sufficient and optimal.
