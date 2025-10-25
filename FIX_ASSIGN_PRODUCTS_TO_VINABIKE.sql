-- ============================================================================
-- FIX: Assign all existing products to Vinabike tenant
-- ============================================================================
-- This assigns all products with NULL tenant_id to Vinabike
-- ============================================================================

-- Update all products without tenant_id to Vinabike tenant
UPDATE products 
SET tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'
WHERE tenant_id IS NULL;

-- Update all categories without tenant_id to Vinabike tenant
UPDATE categories 
SET tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'
WHERE tenant_id IS NULL;

-- Update all customers without tenant_id to Vinabike tenant
UPDATE customers 
SET tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'
WHERE tenant_id IS NULL;

-- Update all sales_invoices without tenant_id to Vinabike tenant
UPDATE sales_invoices 
SET tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'
WHERE tenant_id IS NULL;

-- Update all suppliers without tenant_id to Vinabike tenant
UPDATE suppliers 
SET tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'
WHERE tenant_id IS NULL;

-- Update all purchase_invoices without tenant_id to Vinabike tenant
UPDATE purchase_invoices 
SET tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'
WHERE tenant_id IS NULL;

-- Update all stock_movements without tenant_id to Vinabike tenant
UPDATE stock_movements 
SET tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'
WHERE tenant_id IS NULL;

-- Update all sales_payments without tenant_id to Vinabike tenant
UPDATE sales_payments 
SET tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'
WHERE tenant_id IS NULL;

-- Update all accounts (chart of accounts) without tenant_id to Vinabike tenant
UPDATE accounts 
SET tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'
WHERE tenant_id IS NULL;

-- Update all journal_entries without tenant_id to Vinabike tenant
UPDATE journal_entries 
SET tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'
WHERE tenant_id IS NULL;

-- Update all employees without tenant_id to Vinabike tenant
UPDATE employees 
SET tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'
WHERE tenant_id IS NULL;

-- Verify the results
SELECT 
  'products' as table_name,
  count(*) filter (where tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf') as vinabike_count,
  count(*) filter (where tenant_id is null) as null_count,
  count(*) as total
FROM products
UNION ALL
SELECT 
  'categories',
  count(*) filter (where tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'),
  count(*) filter (where tenant_id is null),
  count(*)
FROM categories
UNION ALL
SELECT 
  'customers',
  count(*) filter (where tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'),
  count(*) filter (where tenant_id is null),
  count(*)
FROM customers
UNION ALL
SELECT 
  'sales_invoices',
  count(*) filter (where tenant_id = '97ef40bf-f58c-4f76-a629-c013fb3928cf'),
  count(*) filter (where tenant_id is null),
  count(*)
FROM sales_invoices;

-- Final check: What can your new tenant see?
-- Run this while logged in as ccatalansandoval7@gmail.com
-- SELECT count(*) as visible_products FROM products;
-- (Should return 0 if isolation is working)
