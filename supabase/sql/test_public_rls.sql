-- ========================================
-- TEST SCRIPT FOR PUBLIC RLS POLICIES
-- ========================================
-- 
-- This script tests that anonymous users can read public data
-- but cannot modify it, and that tenant isolation is enforced.
--
-- Run this in Supabase SQL Editor to verify RLS policies work correctly.
--
-- IMPORTANT: Run each section separately and verify results
-- ========================================

-- ========================================
-- SETUP: Get a test tenant_id
-- ========================================
-- First, get an actual tenant_id from your database
SELECT id, shop_name, subdomain FROM tenants LIMIT 1;

-- Copy the 'id' value from the result above
-- Then run the following to store it in a variable for easy testing:

-- Example: Replace this with your actual tenant UUID
-- DO $$
-- DECLARE
--   v_test_tenant_id uuid := 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx';
-- END $$;


-- ========================================
-- TEST 1: Anonymous Read Access (Products)
-- ========================================
-- Switch to anonymous role (simulates public store visitor)
SET ROLE anon;

-- Should SUCCEED: Read active products with stock
-- REPLACE 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' with actual tenant_id from above
SELECT 
    id, 
    name, 
    sku, 
    price, 
    inventory_qty,
    is_active
FROM products 
WHERE tenant_id = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'  -- ⚠️ REPLACE THIS
LIMIT 5;

-- Expected: Returns active products with inventory_qty > 0
-- If empty: No products match criteria (add test products first)
-- If error: RLS policy missing or incorrect


-- ========================================
-- TEST 2: Anonymous Read Access (Categories)
-- ========================================
-- Should SUCCEED: Read all categories for tenant
SELECT 
    id, 
    name, 
    parent_category_id
FROM product_categories 
WHERE tenant_id = 'YOUR_TENANT_ID'  -- Replace with actual tenant_id
LIMIT 5;

-- Expected: Returns categories for that tenant
-- If empty: No categories exist (seed data needed)


-- ========================================
-- TEST 3: Anonymous Read Access (Website Settings)
-- ========================================
-- Should SUCCEED: Read website settings
SELECT 
    id,
    store_name,
    primary_color,
    currency
FROM website_settings 
WHERE tenant_id = 'YOUR_TENANT_ID'  -- Replace with actual tenant_id
LIMIT 1;

-- Expected: Returns website settings
-- If empty: No settings configured yet


-- ========================================
-- TEST 4: Anonymous CANNOT Insert Products
-- ========================================
-- Should FAIL: Anonymous users cannot create products
INSERT INTO products (
    tenant_id,
    name,
    sku,
    price,
    cost,
    inventory_qty,
    is_active
) VALUES (
    'YOUR_TENANT_ID',  -- Replace with actual tenant_id
    'Unauthorized Product',
    'HACK-001',
    999.99,
    500.00,
    10,
    true
);

-- Expected: ERROR - "new row violates row-level security policy"
-- If succeeds: SECURITY ISSUE - RLS policy missing!


-- ========================================
-- TEST 5: Anonymous CANNOT Update Products
-- ========================================
-- Should FAIL: Anonymous users cannot modify products
UPDATE products 
SET price = 0.01 
WHERE tenant_id = 'YOUR_TENANT_ID'  -- Replace with actual tenant_id
  AND id = (SELECT id FROM products WHERE tenant_id = 'YOUR_TENANT_ID' LIMIT 1);

-- Expected: ERROR - "new row violates row-level security policy"
-- Or: 0 rows updated (policy prevents update)
-- If succeeds: SECURITY ISSUE!


-- ========================================
-- TEST 6: Anonymous CANNOT Delete Products
-- ========================================
-- Should FAIL: Anonymous users cannot delete products
DELETE FROM products 
WHERE tenant_id = 'YOUR_TENANT_ID'  -- Replace with actual tenant_id
  AND id = (SELECT id FROM products WHERE tenant_id = 'YOUR_TENANT_ID' LIMIT 1);

-- Expected: ERROR or 0 rows deleted
-- If succeeds: SECURITY ISSUE!


-- ========================================
-- TEST 7: Tenant Isolation (Cannot See Other Tenants)
-- ========================================
-- Get two different tenant IDs:
SELECT id, shop_name, subdomain FROM tenants LIMIT 2;

-- Try to read products from Tenant A while filtering by Tenant B
SET ROLE anon;

SELECT 
    id, 
    name, 
    tenant_id
FROM products 
WHERE tenant_id != 'YOUR_TENANT_ID'  -- Different tenant
LIMIT 5;

-- Expected: Should return products from other tenants
-- NOTE: RLS allows reading, but app must filter by detected tenant
-- This is why PublicInventoryService MUST filter by tenant_id!


-- ========================================
-- TEST 8: Guest Checkout (Insert Orders)
-- ========================================
-- Should SUCCEED: Anonymous users can create orders (with tenant_id)
SET ROLE anon;

INSERT INTO online_orders (
    tenant_id,
    customer_email,
    customer_name,
    status,
    total_amount,
    currency
) VALUES (
    'YOUR_TENANT_ID',  -- Replace with actual tenant_id
    'guest@example.com',
    'Guest Customer',
    'pending',
    99.99,
    'CLP'
) RETURNING id, customer_email, status, total_amount;

-- Expected: Returns the created order
-- If error "tenant_id cannot be null": Policy requires tenant_id
-- If error "violates row-level security": Policy blocking anon insert


-- ========================================
-- TEST 9: Guest Checkout WITHOUT tenant_id (Should FAIL)
-- ========================================
-- Should FAIL: Tenant_id is required
SET ROLE anon;

INSERT INTO online_orders (
    customer_email,
    customer_name,
    status,
    total_amount,
    currency
) VALUES (
    'hacker@example.com',
    'Hacker',
    'pending',
    0.01,
    'CLP'
);

-- Expected: ERROR - "tenant_id cannot be null" or RLS violation
-- If succeeds: SECURITY ISSUE - no tenant_id validation!


-- ========================================
-- TEST 10: Authenticated User Access
-- ========================================
-- Reset to authenticated role
RESET ROLE;

-- Should SUCCEED: Authenticated users can do everything in their tenant
-- (assuming you're logged in with a user linked to 'YOUR_TENANT_ID')

SELECT 
    id, 
    name, 
    price
FROM products 
WHERE tenant_id = public.user_tenant_id()
LIMIT 5;

-- Expected: Returns products for authenticated user's tenant
-- If error "function public.user_tenant_id() does not exist": 
--   Function not deployed or user not in user_profiles table


-- ========================================
-- CLEANUP: Remove test orders
-- ========================================
RESET ROLE;

DELETE FROM online_orders 
WHERE customer_email IN ('guest@example.com', 'hacker@example.com');


-- ========================================
-- SUMMARY OF EXPECTED RESULTS
-- ========================================
-- ✅ TEST 1-3: Anonymous can READ products, categories, settings
-- ✅ TEST 4-6: Anonymous CANNOT write/update/delete products
-- ⚠️ TEST 7: RLS allows cross-tenant reads (app must filter!)
-- ✅ TEST 8: Anonymous can INSERT orders WITH tenant_id
-- ✅ TEST 9: Anonymous CANNOT insert orders WITHOUT tenant_id
-- ✅ TEST 10: Authenticated users have full access to their tenant
-- ========================================

-- If any test fails unexpectedly, check:
-- 1. Live pg_policy/pg_class definitions and the exact migration stamp;
--    core_schema.sql is incomplete historical context and is never deployed
-- 2. user_profiles table has your user linked to tenant
-- 3. Tables have correct columns (tenant_id, is_active, etc.)
-- 4. Run: SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public';
