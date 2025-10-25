-- ============================================================================
-- DROP OLD NON-TENANT-FILTERED RLS POLICIES FROM LIVE DATABASE
-- ============================================================================
-- Run this BEFORE deploying the updated core_schema.sql
-- This removes old "Authenticated *" policies that allow cross-tenant data access
--
-- CRITICAL: These old policies use auth.role() = 'authenticated' WITHOUT tenant_id filtering
-- PostgreSQL RLS is PERMISSIVE (policies are OR'ed), so having BOTH old (no filter) and 
-- new (tenant filter) policies means the old policy wins and ALL data is visible.
--
-- After running this script, deploy core_schema.sql which has the NEW tenant-filtered policies.
-- ============================================================================

-- Drop old policies for accounts
drop policy if exists "Authenticated accounts read" on accounts;
drop policy if exists "Authenticated accounts insert" on accounts;
drop policy if exists "Authenticated accounts update" on accounts;
drop policy if exists "Authenticated accounts delete" on accounts;

-- Drop old policies for customers
drop policy if exists "Authenticated customers read" on customers;

-- Drop old policies for suppliers
drop policy if exists "Authenticated suppliers read" on suppliers;
drop policy if exists "Authenticated suppliers insert" on suppliers;
drop policy if exists "Authenticated suppliers update" on suppliers;
drop policy if exists "Authenticated suppliers delete" on suppliers;

-- Drop old policies for product_brands
drop policy if exists "Authenticated product_brands read" on product_brands;
drop policy if exists "Authenticated product_brands insert" on product_brands;
drop policy if exists "Authenticated product_brands update" on product_brands;
drop policy if exists "Authenticated product_brands delete" on product_brands;

-- Drop old policies for purchase_invoices
drop policy if exists "Authenticated purchase_invoices read" on purchase_invoices;
drop policy if exists "Authenticated purchase_invoices insert" on purchase_invoices;
drop policy if exists "Authenticated purchase_invoices update" on purchase_invoices;
drop policy if exists "Authenticated purchase_invoices delete" on purchase_invoices;

-- Drop old policies for journal_entries
drop policy if exists "Authenticated journal_entries read" on journal_entries;
drop policy if exists "Authenticated journal_entries insert" on journal_entries;
drop policy if exists "Authenticated journal_entries update" on journal_entries;
drop policy if exists "Authenticated journal_entries delete" on journal_entries;

-- Drop old policies for journal_lines
drop policy if exists "Authenticated journal_lines read" on journal_lines;
drop policy if exists "Authenticated journal_lines insert" on journal_lines;
drop policy if exists "Authenticated journal_lines update" on journal_lines;
drop policy if exists "Authenticated journal_lines delete" on journal_lines;

-- Drop old policies for products
drop policy if exists "Authenticated products read" on products;
drop policy if exists "Authenticated products insert" on products;
drop policy if exists "Authenticated products update" on products;
drop policy if exists "Authenticated products delete" on products;

-- Drop old policies for sales_invoices
drop policy if exists "Authenticated invoices read" on sales_invoices;
drop policy if exists "Authenticated invoices insert" on sales_invoices;
drop policy if exists "Authenticated invoices update" on sales_invoices;
drop policy if exists "Authenticated invoices delete" on sales_invoices;

-- Drop old policies for sales_payments
drop policy if exists "Authenticated payments read" on sales_payments;
drop policy if exists "Authenticated payments insert" on sales_payments;
drop policy if exists "Authenticated payments update" on sales_payments;
drop policy if exists "Authenticated payments delete" on sales_payments;

-- Drop old policies for stock_movements
drop policy if exists "Authenticated stock_movements read" on stock_movements;
drop policy if exists "Authenticated stock_movements insert" on stock_movements;

-- Drop old policies for orders
drop policy if exists "Authenticated orders read" on orders;

-- Drop old policies for order_items
drop policy if exists "Authenticated order_items read" on order_items;

-- Drop old policies for employees
drop policy if exists "Authenticated employees read" on employees;
drop policy if exists "Authenticated employees insert" on employees;
drop policy if exists "Authenticated employees update" on employees;
drop policy if exists "Authenticated employees delete" on employees;

-- Drop old policies for departments
drop policy if exists "Authenticated departments read" on departments;
drop policy if exists "Authenticated departments insert" on departments;
drop policy if exists "Authenticated departments update" on departments;
drop policy if exists "Authenticated departments delete" on departments;

-- Drop old policies for attendances
drop policy if exists "Authenticated attendances read" on attendances;
drop policy if exists "Authenticated attendances insert" on attendances;
drop policy if exists "Authenticated attendances update" on attendances;
drop policy if exists "Authenticated attendances delete" on attendances;

-- Drop old policies for website module (e-commerce)
drop policy if exists "Authenticated can manage featured" on featured_products;
drop policy if exists "Authenticated can manage all order items" on online_order_items;
drop policy if exists "Authenticated can manage all orders" on online_orders;
drop policy if exists "Authenticated can manage banners" on website_banners;
drop policy if exists "Authenticated can manage blocks" on website_blocks;
drop policy if exists "Authenticated can manage content" on website_content;
drop policy if exists "Authenticated can manage settings" on website_settings;

-- Verify policies dropped
select 
  tablename,
  policyname,
  cmd,
  qual
from pg_policies
where schemaname = 'public'
  and policyname like 'Authenticated%'
order by tablename, policyname;

-- Should return 0 rows if all old policies dropped successfully
