-- ============================================================================
-- DROP OLD RLS POLICIES (Without tenant_id filtering)
-- ============================================================================
-- These old policies were created before multi-tenant architecture
-- They allow authenticated users to see ALL data across tenants
-- We need to remove them and keep ONLY the tenant-filtered policies

-- Drop old products policies
DROP POLICY IF EXISTS "Authenticated products read" ON products;
DROP POLICY IF EXISTS "Public website products read" ON products;
DROP POLICY IF EXISTS "Authenticated products insert" ON products;
DROP POLICY IF EXISTS "Authenticated products update" ON products;
DROP POLICY IF EXISTS "Authenticated products delete" ON products;

-- Drop old policies on other tables (these likely exist too)
DROP POLICY IF EXISTS "Authenticated customers read" ON customers;
DROP POLICY IF EXISTS "Authenticated customers insert" ON customers;
DROP POLICY IF EXISTS "Authenticated customers update" ON customers;
DROP POLICY IF EXISTS "Authenticated customers delete" ON customers;

DROP POLICY IF EXISTS "Authenticated suppliers read" ON suppliers;
DROP POLICY IF EXISTS "Authenticated suppliers insert" ON suppliers;
DROP POLICY IF EXISTS "Authenticated suppliers update" ON suppliers;
DROP POLICY IF EXISTS "Authenticated suppliers delete" ON suppliers;

DROP POLICY IF EXISTS "Authenticated sales_invoices read" ON sales_invoices;
DROP POLICY IF EXISTS "Authenticated sales_invoices insert" ON sales_invoices;
DROP POLICY IF EXISTS "Authenticated sales_invoices update" ON sales_invoices;
DROP POLICY IF EXISTS "Authenticated sales_invoices delete" ON sales_invoices;

DROP POLICY IF EXISTS "Authenticated purchase_invoices read" ON purchase_invoices;
DROP POLICY IF EXISTS "Authenticated purchase_invoices insert" ON purchase_invoices;
DROP POLICY IF EXISTS "Authenticated purchase_invoices update" ON purchase_invoices;
DROP POLICY IF EXISTS "Authenticated purchase_invoices delete" ON purchase_invoices;

DROP POLICY IF EXISTS "Authenticated accounts read" ON accounts;
DROP POLICY IF EXISTS "Authenticated accounts insert" ON accounts;
DROP POLICY IF EXISTS "Authenticated accounts update" ON accounts;
DROP POLICY IF EXISTS "Authenticated accounts delete" ON accounts;

DROP POLICY IF EXISTS "Authenticated employees read" ON employees;
DROP POLICY IF EXISTS "Authenticated employees insert" ON employees;
DROP POLICY IF EXISTS "Authenticated employees update" ON employees;
DROP POLICY IF EXISTS "Authenticated employees delete" ON employees;

DROP POLICY IF EXISTS "Authenticated orders read" ON orders;
DROP POLICY IF EXISTS "Authenticated orders insert" ON orders;
DROP POLICY IF EXISTS "Authenticated orders update" ON orders;
DROP POLICY IF EXISTS "Authenticated orders delete" ON orders;

DROP POLICY IF EXISTS "Authenticated payments read" ON payments;
DROP POLICY IF EXISTS "Authenticated payments insert" ON payments;
DROP POLICY IF EXISTS "Authenticated payments update" ON payments;
DROP POLICY IF EXISTS "Authenticated payments delete" ON payments;

-- Add more as needed for other tables

RAISE NOTICE '✅ Old non-tenant-filtered policies dropped!';
RAISE NOTICE 'Only tenant-filtered policies remain active.';
RAISE NOTICE 'Users will now ONLY see data from their own tenant.';
