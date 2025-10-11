-- =====================================================
-- Row Level Security (RLS) Policies
-- =====================================================
-- This script sets up RLS policies for all tables.
-- For a bikeshop ERP, we'll use a simple approach:
-- - Authenticated users can do everything
-- - Anonymous users have no access
-- =====================================================

-- =====================================================
-- Enable RLS on all tables
-- =====================================================
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- Drop existing policies (if any)
-- =====================================================
DROP POLICY IF EXISTS "Authenticated users can read categories" ON categories;
DROP POLICY IF EXISTS "Authenticated users can insert categories" ON categories;
DROP POLICY IF EXISTS "Authenticated users can update categories" ON categories;
DROP POLICY IF EXISTS "Authenticated users can delete categories" ON categories;

DROP POLICY IF EXISTS "Authenticated users can read products" ON products;
DROP POLICY IF EXISTS "Authenticated users can insert products" ON products;
DROP POLICY IF EXISTS "Authenticated users can update products" ON products;
DROP POLICY IF EXISTS "Authenticated users can delete products" ON products;

DROP POLICY IF EXISTS "Authenticated users can read customers" ON customers;
DROP POLICY IF EXISTS "Authenticated users can insert customers" ON customers;
DROP POLICY IF EXISTS "Authenticated users can update customers" ON customers;
DROP POLICY IF EXISTS "Authenticated users can delete customers" ON customers;

DROP POLICY IF EXISTS "Authenticated users can read suppliers" ON suppliers;
DROP POLICY IF EXISTS "Authenticated users can insert suppliers" ON suppliers;
DROP POLICY IF EXISTS "Authenticated users can update suppliers" ON suppliers;
DROP POLICY IF EXISTS "Authenticated users can delete suppliers" ON suppliers;

DROP POLICY IF EXISTS "Authenticated users can read sales_invoices" ON sales_invoices;
DROP POLICY IF EXISTS "Authenticated users can insert sales_invoices" ON sales_invoices;
DROP POLICY IF EXISTS "Authenticated users can update sales_invoices" ON sales_invoices;
DROP POLICY IF EXISTS "Authenticated users can delete sales_invoices" ON sales_invoices;

DROP POLICY IF EXISTS "Authenticated users can read purchase_invoices" ON purchase_invoices;
DROP POLICY IF EXISTS "Authenticated users can insert purchase_invoices" ON purchase_invoices;
DROP POLICY IF EXISTS "Authenticated users can update purchase_invoices" ON purchase_invoices;
DROP POLICY IF EXISTS "Authenticated users can delete purchase_invoices" ON purchase_invoices;

DROP POLICY IF EXISTS "Authenticated users can read stock_movements" ON stock_movements;
DROP POLICY IF EXISTS "Authenticated users can insert stock_movements" ON stock_movements;
DROP POLICY IF EXISTS "Authenticated users can update stock_movements" ON stock_movements;
DROP POLICY IF EXISTS "Authenticated users can delete stock_movements" ON stock_movements;

DROP POLICY IF EXISTS "Authenticated users can read journal_entries" ON journal_entries;
DROP POLICY IF EXISTS "Authenticated users can insert journal_entries" ON journal_entries;
DROP POLICY IF EXISTS "Authenticated users can update journal_entries" ON journal_entries;
DROP POLICY IF EXISTS "Authenticated users can delete journal_entries" ON journal_entries;

DROP POLICY IF EXISTS "Authenticated users can read journal_lines" ON journal_lines;
DROP POLICY IF EXISTS "Authenticated users can insert journal_lines" ON journal_lines;
DROP POLICY IF EXISTS "Authenticated users can update journal_lines" ON journal_lines;
DROP POLICY IF EXISTS "Authenticated users can delete journal_lines" ON journal_lines;

DROP POLICY IF EXISTS "Authenticated users can read accounts" ON accounts;
DROP POLICY IF EXISTS "Authenticated users can insert accounts" ON accounts;
DROP POLICY IF EXISTS "Authenticated users can update accounts" ON accounts;
DROP POLICY IF EXISTS "Authenticated users can delete accounts" ON accounts;

-- =====================================================
-- CATEGORIES
-- =====================================================
CREATE POLICY "Authenticated users can read categories"
  ON categories FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert categories"
  ON categories FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update categories"
  ON categories FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete categories"
  ON categories FOR DELETE
  USING (auth.role() = 'authenticated');

-- =====================================================
-- PRODUCTS
-- =====================================================
CREATE POLICY "Authenticated users can read products"
  ON products FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert products"
  ON products FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update products"
  ON products FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete products"
  ON products FOR DELETE
  USING (auth.role() = 'authenticated');

-- =====================================================
-- CUSTOMERS
-- =====================================================
CREATE POLICY "Authenticated users can read customers"
  ON customers FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert customers"
  ON customers FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update customers"
  ON customers FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete customers"
  ON customers FOR DELETE
  USING (auth.role() = 'authenticated');

-- =====================================================
-- SUPPLIERS
-- =====================================================
CREATE POLICY "Authenticated users can read suppliers"
  ON suppliers FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert suppliers"
  ON suppliers FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update suppliers"
  ON suppliers FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete suppliers"
  ON suppliers FOR DELETE
  USING (auth.role() = 'authenticated');

-- =====================================================
-- SALES INVOICES
-- =====================================================
CREATE POLICY "Authenticated users can read sales_invoices"
  ON sales_invoices FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert sales_invoices"
  ON sales_invoices FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update sales_invoices"
  ON sales_invoices FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete sales_invoices"
  ON sales_invoices FOR DELETE
  USING (auth.role() = 'authenticated');

-- =====================================================
-- PURCHASE INVOICES
-- =====================================================
CREATE POLICY "Authenticated users can read purchase_invoices"
  ON purchase_invoices FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert purchase_invoices"
  ON purchase_invoices FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update purchase_invoices"
  ON purchase_invoices FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete purchase_invoices"
  ON purchase_invoices FOR DELETE
  USING (auth.role() = 'authenticated');

-- =====================================================
-- STOCK MOVEMENTS
-- =====================================================
CREATE POLICY "Authenticated users can read stock_movements"
  ON stock_movements FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert stock_movements"
  ON stock_movements FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update stock_movements"
  ON stock_movements FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete stock_movements"
  ON stock_movements FOR DELETE
  USING (auth.role() = 'authenticated');

-- =====================================================
-- JOURNAL ENTRIES
-- =====================================================
CREATE POLICY "Authenticated users can read journal_entries"
  ON journal_entries FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert journal_entries"
  ON journal_entries FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update journal_entries"
  ON journal_entries FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete journal_entries"
  ON journal_entries FOR DELETE
  USING (auth.role() = 'authenticated');

-- =====================================================
-- JOURNAL LINES
-- =====================================================
CREATE POLICY "Authenticated users can read journal_lines"
  ON journal_lines FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert journal_lines"
  ON journal_lines FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update journal_lines"
  ON journal_lines FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete journal_lines"
  ON journal_lines FOR DELETE
  USING (auth.role() = 'authenticated');

-- =====================================================
-- ACCOUNTS (Chart of Accounts)
-- =====================================================
CREATE POLICY "Authenticated users can read accounts"
  ON accounts FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can insert accounts"
  ON accounts FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can update accounts"
  ON accounts FOR UPDATE
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can delete accounts"
  ON accounts FOR DELETE
  USING (auth.role() = 'authenticated');

-- =====================================================
-- Verification Query
-- =====================================================
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- =====================================================
-- NOTES:
-- =====================================================
-- 1. All tables require authentication (auth.role() = 'authenticated')
-- 2. Anonymous users have NO access
-- 3. Future: Add role-based policies (admin, cashier, mechanic)
-- 4. Future: Add more granular permissions per user role
-- 5. Storage bucket policies must also be configured in Supabase dashboard
-- =====================================================
