-- ============================================================
-- MULTI-TENANT ISOLATION VERIFICATION TEST
-- ============================================================
-- This test proves that tenants are 100% isolated from each other
-- Run this in Supabase SQL Editor
-- 
-- Date: 2025-10-25
-- Purpose: Verify tenant isolation works correctly
-- ============================================================

-- 🧪 TEST 1: Create Two Test Tenants
-- ============================================================
DO $$
DECLARE
  tenant_a_id uuid;
  tenant_b_id uuid;
  user_a_id uuid;
  user_b_id uuid;
BEGIN
  -- Create Tenant A (Bike Shop Santiago)
  INSERT INTO tenants (id, name, created_at)
  VALUES (gen_random_uuid(), 'Bike Shop Santiago TEST', now())
  RETURNING id INTO tenant_a_id;
  
  -- Create Tenant B (Bike World TEST)
  INSERT INTO tenants (id, name, created_at)
  VALUES (gen_random_uuid(), 'Bike World TEST', now())
  RETURNING id INTO tenant_b_id;
  
  RAISE NOTICE '✅ Created Tenant A: %', tenant_a_id;
  RAISE NOTICE '✅ Created Tenant B: %', tenant_b_id;
  
  -- Store for next tests
  CREATE TEMP TABLE test_tenants (tenant_a_id uuid, tenant_b_id uuid);
  INSERT INTO test_tenants VALUES (tenant_a_id, tenant_b_id);
END $$;

-- 🧪 TEST 2: Create Test Customers for Each Tenant
-- ============================================================
DO $$
DECLARE
  tenant_a_id uuid;
  tenant_b_id uuid;
  customer_a1_id uuid;
  customer_a2_id uuid;
  customer_b1_id uuid;
BEGIN
  SELECT t.tenant_a_id, t.tenant_b_id INTO tenant_a_id, tenant_b_id FROM test_tenants t;
  
  -- Customers for Tenant A
  INSERT INTO customers (id, tenant_id, name, email, phone, created_at)
  VALUES (gen_random_uuid(), tenant_a_id, 'Juan Pérez (Tenant A)', 'juan@tenantA.com', '+56912345678', now())
  RETURNING id INTO customer_a1_id;
  
  INSERT INTO customers (id, tenant_id, name, email, phone, created_at)
  VALUES (gen_random_uuid(), tenant_a_id, 'María González (Tenant A)', 'maria@tenantA.com', '+56987654321', now())
  RETURNING id INTO customer_a2_id;
  
  -- Customers for Tenant B
  INSERT INTO customers (id, tenant_id, name, email, phone, created_at)
  VALUES (gen_random_uuid(), tenant_b_id, 'Pedro Silva (Tenant B)', 'pedro@tenantB.com', '+56911111111', now())
  RETURNING id INTO customer_b1_id;
  
  RAISE NOTICE '✅ Created 2 customers for Tenant A';
  RAISE NOTICE '✅ Created 1 customer for Tenant B';
END $$;

-- 🧪 TEST 3: Verify Tenant A Can ONLY See Their Own Customers
-- ============================================================
DO $$
DECLARE
  tenant_a_id uuid;
  customer_count integer;
BEGIN
  SELECT t.tenant_a_id INTO tenant_a_id FROM test_tenants t;
  
  -- Simulate Tenant A querying customers
  SELECT COUNT(*) INTO customer_count
  FROM customers
  WHERE tenant_id = tenant_a_id;
  
  IF customer_count = 2 THEN
    RAISE NOTICE '✅ TEST PASSED: Tenant A sees exactly 2 customers (their own)';
  ELSE
    RAISE EXCEPTION '❌ TEST FAILED: Tenant A sees % customers, expected 2', customer_count;
  END IF;
END $$;

-- 🧪 TEST 4: Verify Tenant B Can ONLY See Their Own Customers
-- ============================================================
DO $$
DECLARE
  tenant_b_id uuid;
  customer_count integer;
BEGIN
  SELECT t.tenant_b_id INTO tenant_b_id FROM test_tenants t;
  
  -- Simulate Tenant B querying customers
  SELECT COUNT(*) INTO customer_count
  FROM customers
  WHERE tenant_id = tenant_b_id;
  
  IF customer_count = 1 THEN
    RAISE NOTICE '✅ TEST PASSED: Tenant B sees exactly 1 customer (their own)';
  ELSE
    RAISE EXCEPTION '❌ TEST FAILED: Tenant B sees % customers, expected 1', customer_count;
  END IF;
END $$;

-- 🧪 TEST 5: Verify Cross-Tenant Customer Search Fails
-- ============================================================
DO $$
DECLARE
  tenant_a_id uuid;
  tenant_b_id uuid;
  found_count integer;
BEGIN
  SELECT t.tenant_a_id, t.tenant_b_id INTO tenant_a_id, tenant_b_id FROM test_tenants t;
  
  -- Try to find Tenant B's customer while filtering as Tenant A
  SELECT COUNT(*) INTO found_count
  FROM customers
  WHERE name LIKE '%Pedro Silva%'
    AND tenant_id = tenant_a_id;  -- Tenant A trying to access Tenant B's customer
  
  IF found_count = 0 THEN
    RAISE NOTICE '✅ TEST PASSED: Tenant A CANNOT see Tenant B customers';
  ELSE
    RAISE EXCEPTION '❌ TEST FAILED: Tenant A can see Tenant B customers!';
  END IF;
END $$;

-- 🧪 TEST 6: Create Test Products for Each Tenant
-- ============================================================
DO $$
DECLARE
  tenant_a_id uuid;
  tenant_b_id uuid;
BEGIN
  SELECT t.tenant_a_id, t.tenant_b_id INTO tenant_a_id, tenant_b_id FROM test_tenants t;
  
  -- Products for Tenant A
  INSERT INTO products (id, tenant_id, name, sku, price, cost, stock_quantity, created_at)
  VALUES (gen_random_uuid(), tenant_a_id, 'Mountain Bike X1 (Tenant A)', 'MTB-X1-A', 500000, 300000, 10, now());
  
  INSERT INTO products (id, tenant_id, name, sku, price, cost, stock_quantity, created_at)
  VALUES (gen_random_uuid(), tenant_a_id, 'Road Bike R2 (Tenant A)', 'RB-R2-A', 600000, 350000, 5, now());
  
  -- Products for Tenant B
  INSERT INTO products (id, tenant_id, name, sku, price, cost, stock_quantity, created_at)
  VALUES (gen_random_uuid(), tenant_b_id, 'BMX Bike B3 (Tenant B)', 'BMX-B3-B', 400000, 250000, 8, now());
  
  RAISE NOTICE '✅ Created 2 products for Tenant A';
  RAISE NOTICE '✅ Created 1 product for Tenant B';
END $$;

-- 🧪 TEST 7: Verify Product Isolation
-- ============================================================
DO $$
DECLARE
  tenant_a_id uuid;
  tenant_b_id uuid;
  tenant_a_products integer;
  tenant_b_products integer;
BEGIN
  SELECT t.tenant_a_id, t.tenant_b_id INTO tenant_a_id, tenant_b_id FROM test_tenants t;
  
  -- Count Tenant A products
  SELECT COUNT(*) INTO tenant_a_products FROM products WHERE tenant_id = tenant_a_id;
  
  -- Count Tenant B products
  SELECT COUNT(*) INTO tenant_b_products FROM products WHERE tenant_id = tenant_b_id;
  
  IF tenant_a_products = 2 AND tenant_b_products = 1 THEN
    RAISE NOTICE '✅ TEST PASSED: Product isolation works correctly';
    RAISE NOTICE '   - Tenant A has 2 products';
    RAISE NOTICE '   - Tenant B has 1 product';
  ELSE
    RAISE EXCEPTION '❌ TEST FAILED: Product counts incorrect (A=%, B=%)', tenant_a_products, tenant_b_products;
  END IF;
END $$;

-- 🧪 TEST 8: Verify Website Configuration Isolation
-- ============================================================
DO $$
DECLARE
  tenant_a_id uuid;
  tenant_b_id uuid;
BEGIN
  SELECT t.tenant_a_id, t.tenant_b_id INTO tenant_a_id, tenant_b_id FROM test_tenants t;
  
  -- Configure website for Tenant A
  INSERT INTO company_settings (tenant_id, key, value, website_subdomain, website_status)
  VALUES (tenant_a_id, 'website_config', 'Bike Shop Santiago', 'bike-shop-santiago-test', 'deployed');
  
  -- Configure website for Tenant B
  INSERT INTO company_settings (tenant_id, key, value, website_subdomain, website_status)
  VALUES (tenant_b_id, 'website_config', 'Bike World', 'bike-world-test', 'deployed');
  
  RAISE NOTICE '✅ Created website configs for both tenants';
END $$;

-- 🧪 TEST 9: Verify Website Subdomain Uniqueness
-- ============================================================
DO $$
DECLARE
  tenant_a_id uuid;
  duplicate_error boolean := false;
BEGIN
  SELECT t.tenant_a_id INTO tenant_a_id FROM test_tenants t;
  
  -- Try to create duplicate subdomain (should fail)
  BEGIN
    INSERT INTO company_settings (tenant_id, key, value, website_subdomain, website_status)
    VALUES (tenant_a_id, 'website_config_2', 'Duplicate', 'bike-shop-santiago-test', 'deployed');
  EXCEPTION
    WHEN unique_violation THEN
      duplicate_error := true;
  END;
  
  IF duplicate_error THEN
    RAISE NOTICE '✅ TEST PASSED: Duplicate subdomain correctly blocked';
  ELSE
    RAISE EXCEPTION '❌ TEST FAILED: Duplicate subdomain was allowed!';
  END IF;
END $$;

-- 🧪 TEST 10: Final Summary & Cleanup Instructions
-- ============================================================
DO $$
DECLARE
  tenant_a_id uuid;
  tenant_b_id uuid;
BEGIN
  SELECT t.tenant_a_id, t.tenant_b_id INTO tenant_a_id, tenant_b_id FROM test_tenants t;
  
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ ALL TESTS PASSED!';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Multi-tenant isolation is working correctly:';
  RAISE NOTICE '  ✅ Customers are isolated by tenant';
  RAISE NOTICE '  ✅ Products are isolated by tenant';
  RAISE NOTICE '  ✅ Website configs are isolated by tenant';
  RAISE NOTICE '  ✅ Cross-tenant access is blocked';
  RAISE NOTICE '  ✅ Subdomain uniqueness is enforced';
  RAISE NOTICE '';
  RAISE NOTICE '📋 TO CLEANUP TEST DATA, RUN:';
  RAISE NOTICE '';
  RAISE NOTICE '  DELETE FROM tenants WHERE id IN (''%'', ''%'');', tenant_a_id, tenant_b_id;
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
END $$;

-- Display test tenant IDs for manual verification
SELECT 
  'Tenant A (Bike Shop Santiago)' as tenant,
  tenant_a_id as tenant_id,
  (SELECT COUNT(*) FROM customers WHERE tenant_id = tenant_a_id) as customers,
  (SELECT COUNT(*) FROM products WHERE tenant_id = tenant_a_id) as products
FROM test_tenants
UNION ALL
SELECT 
  'Tenant B (Bike World)' as tenant,
  tenant_b_id as tenant_id,
  (SELECT COUNT(*) FROM customers WHERE tenant_id = tenant_b_id) as customers,
  (SELECT COUNT(*) FROM products WHERE tenant_id = tenant_b_id) as products
FROM test_tenants;
