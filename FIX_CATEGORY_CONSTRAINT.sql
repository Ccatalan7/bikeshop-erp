-- ⚠️ RUN THIS IN SUPABASE SQL EDITOR TO FIX CATEGORY CONSTRAINT
-- Problem: Old unique constraint on full_path needs to be per-tenant

-- Step 1: Drop the old global unique constraint (if it exists)
ALTER TABLE product_categories DROP CONSTRAINT IF EXISTS product_categories_full_path_key;

-- Step 2: Ensure the correct per-tenant constraint exists
-- (This should already exist from core_schema.sql, but we make sure)
DO $$ 
BEGIN
  -- Drop existing constraint if it has wrong definition
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'product_categories_tenant_id_full_path_key'
  ) THEN
    ALTER TABLE product_categories 
    DROP CONSTRAINT product_categories_tenant_id_full_path_key;
  END IF;
  
  -- Add the correct per-tenant unique constraint
  ALTER TABLE product_categories 
  ADD CONSTRAINT product_categories_tenant_id_full_path_key 
  UNIQUE (tenant_id, full_path);
END $$;

-- Verify the constraint
SELECT 
  conname as constraint_name,
  pg_get_constraintdef(oid) as definition
FROM pg_constraint
WHERE conrelid = 'product_categories'::regclass
  AND contype = 'u';
