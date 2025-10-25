-- ============================================================================
-- DROP ALL OLD TENANT-UNSAFE RLS POLICIES
-- ============================================================================
-- Run this in Supabase SQL Editor to immediately fix tenant isolation.
-- These policies allow ANY authenticated user to see ALL data regardless of tenant_id.
-- After running this, the tenant-based policies (lines 10530-10750 in core_schema.sql)
-- will be the only active policies, enforcing proper multi-tenant isolation.

-- Drop old accounts policies
DROP POLICY IF EXISTS "Authenticated accounts read" ON accounts;
DROP POLICY IF EXISTS "Authenticated accounts insert" ON accounts;
DROP POLICY IF EXISTS "Authenticated accounts update" ON accounts;
DROP POLICY IF EXISTS "Authenticated accounts delete" ON accounts;

-- Drop old customers policies
DROP POLICY IF EXISTS "Authenticated customers read" ON customers;
-- Keep these - they allow customers to manage their own profile
-- DROP POLICY IF EXISTS "Customers can create own profile" ON customers;
-- DROP POLICY IF EXISTS "Customers can update own profile" ON customers;

-- Drop old customer_addresses policies (but keep customer-specific ones)
-- Keep: "Customers can view own addresses", "Customers can insert own addresses", etc.

-- Drop old suppliers policies
DROP POLICY IF EXISTS "Authenticated suppliers read" ON suppliers;
DROP POLICY IF EXISTS "Authenticated suppliers insert" ON suppliers;
DROP POLICY IF EXISTS "Authenticated suppliers update" ON suppliers;
DROP POLICY IF EXISTS "Authenticated suppliers delete" ON suppliers;

-- Drop old product_brands policies
DROP POLICY IF EXISTS "Authenticated product_brands read" ON product_brands;
DROP POLICY IF EXISTS "Authenticated product_brands insert" ON product_brands;
DROP POLICY IF EXISTS "Authenticated product_brands update" ON product_brands;
DROP POLICY IF EXISTS "Authenticated product_brands delete" ON product_brands;

-- Drop old purchase_invoices policies
DROP POLICY IF EXISTS "Authenticated purchase_invoices read" ON purchase_invoices;
DROP POLICY IF EXISTS "Authenticated purchase_invoices insert" ON purchase_invoices;
DROP POLICY IF EXISTS "Authenticated purchase_invoices update" ON purchase_invoices;
DROP POLICY IF EXISTS "Authenticated purchase_invoices delete" ON purchase_invoices;

-- Drop old journal_entries policies
DROP POLICY IF EXISTS "Authenticated journal_entries read" ON journal_entries;
DROP POLICY IF EXISTS "Authenticated journal_entries insert" ON journal_entries;
DROP POLICY IF EXISTS "Authenticated journal_entries update" ON journal_entries;
DROP POLICY IF EXISTS "Authenticated journal_entries delete" ON journal_entries;

-- Drop old journal_lines policies
DROP POLICY IF EXISTS "Authenticated journal_lines read" ON journal_lines;
DROP POLICY IF EXISTS "Authenticated journal_lines insert" ON journal_lines;
DROP POLICY IF EXISTS "Authenticated journal_lines update" ON journal_lines;
DROP POLICY IF EXISTS "Authenticated journal_lines delete" ON journal_lines;

-- Drop old products policies (CRITICAL - this is what's causing cross-tenant visibility)
DROP POLICY IF EXISTS "Authenticated products read" ON products;
DROP POLICY IF EXISTS "Authenticated products insert" ON products;
DROP POLICY IF EXISTS "Authenticated products update" ON products;
DROP POLICY IF EXISTS "Authenticated products delete" ON products;
-- Keep: "Public website products read" - this is for anonymous users

-- Drop old sales_invoices policies
DROP POLICY IF EXISTS "Authenticated invoices read" ON sales_invoices;
DROP POLICY IF EXISTS "Authenticated invoices insert" ON sales_invoices;
DROP POLICY IF EXISTS "Authenticated invoices update" ON sales_invoices;
DROP POLICY IF EXISTS "Authenticated invoices delete" ON sales_invoices;

-- Drop old sales_payments policies
DROP POLICY IF EXISTS "Authenticated payments read" ON sales_payments;
DROP POLICY IF EXISTS "Authenticated payments insert" ON sales_payments;
DROP POLICY IF EXISTS "Authenticated payments update" ON sales_payments;
DROP POLICY IF EXISTS "Authenticated payments delete" ON sales_payments;

-- Drop old stock_movements policies
DROP POLICY IF EXISTS "Authenticated stock_movements read" ON stock_movements;
DROP POLICY IF EXISTS "Authenticated stock_movements insert" ON stock_movements;

-- Drop old orders policies
DROP POLICY IF EXISTS "Authenticated orders read" ON orders;

-- Drop old order_items policies
DROP POLICY IF EXISTS "Authenticated order_items read" ON order_items;

-- Drop old product_categories policies (if they exist)
DROP POLICY IF EXISTS "Authenticated product_categories read" ON product_categories;
DROP POLICY IF EXISTS "Authenticated product_categories insert" ON product_categories;
DROP POLICY IF EXISTS "Authenticated product_categories update" ON product_categories;
DROP POLICY IF EXISTS "Authenticated product_categories delete" ON product_categories;

-- Drop old invoice_items policies (if they exist)
DROP POLICY IF EXISTS "Authenticated invoice_items read" ON invoice_items;
DROP POLICY IF EXISTS "Authenticated invoice_items insert" ON invoice_items;
DROP POLICY IF EXISTS "Authenticated invoice_items update" ON invoice_items;
DROP POLICY IF EXISTS "Authenticated invoice_items delete" ON invoice_items;

-- Drop old purchase_invoice_items policies (if they exist)
DROP POLICY IF EXISTS "Authenticated purchase_invoice_items read" ON purchase_invoice_items;
DROP POLICY IF EXISTS "Authenticated purchase_invoice_items insert" ON purchase_invoice_items;
DROP POLICY IF EXISTS "Authenticated purchase_invoice_items update" ON purchase_invoice_items;
DROP POLICY IF EXISTS "Authenticated purchase_invoice_items delete" ON purchase_invoice_items;

-- Verify policies have been dropped
SELECT schemaname, tablename, policyname
FROM pg_policies
WHERE schemaname = 'public'
  AND policyname LIKE 'Authenticated%'
ORDER BY tablename, policyname;

-- This query should return ZERO rows if all old policies are dropped.
-- Any remaining "Authenticated..." policies are tenant-unsafe and should be investigated.
