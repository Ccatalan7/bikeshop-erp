-- ========================================
-- AUTOMATED TEST SCRIPT FOR PUBLIC RLS POLICIES
-- ========================================
-- 
-- This version automatically gets a tenant_id and runs tests
-- Run this entire script in Supabase SQL Editor
-- ========================================

DO $$
DECLARE
    v_tenant_id uuid;
    v_test_product_id uuid;
    v_result_count integer;
BEGIN
    -- Get first tenant
    SELECT id INTO v_tenant_id FROM tenants LIMIT 1;
    
    IF v_tenant_id IS NULL THEN
        RAISE NOTICE '❌ No tenants found! Create a tenant first.';
        RETURN;
    END IF;
    
    RAISE NOTICE '✅ Using tenant_id: %', v_tenant_id;
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'TEST 1: Anonymous Read Access (Products)';
    RAISE NOTICE '========================================';
    
    -- Switch to anonymous role
    EXECUTE 'SET ROLE anon';
    
    -- Test 1: Read products
    EXECUTE format('SELECT COUNT(*) FROM products WHERE tenant_id = %L', v_tenant_id) INTO v_result_count;
    
    IF v_result_count > 0 THEN
        RAISE NOTICE '✅ TEST 1 PASSED: Anonymous can read % products', v_result_count;
    ELSE
        RAISE NOTICE '⚠️ TEST 1: No products found (may need to add test data)';
    END IF;
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'TEST 2: Anonymous Read Access (Categories)';
    RAISE NOTICE '========================================';
    
    -- Test 2: Read categories
    EXECUTE format('SELECT COUNT(*) FROM product_categories WHERE tenant_id = %L', v_tenant_id) INTO v_result_count;
    
    IF v_result_count > 0 THEN
        RAISE NOTICE '✅ TEST 2 PASSED: Anonymous can read % categories', v_result_count;
    ELSE
        RAISE NOTICE '⚠️ TEST 2: No categories found (may need to add test data)';
    END IF;
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'TEST 3: Anonymous CANNOT Insert Products';
    RAISE NOTICE '========================================';
    
    -- Test 3: Try to insert product (should fail)
    BEGIN
        EXECUTE format('
            INSERT INTO products (tenant_id, name, sku, price, cost, inventory_qty, is_active)
            VALUES (%L, ''Hack Product'', ''HACK-001'', 999.99, 500, 10, true)
        ', v_tenant_id);
        
        RAISE NOTICE '❌ TEST 3 FAILED: Anonymous user was able to insert product! SECURITY ISSUE!';
    EXCEPTION WHEN insufficient_privilege OR SQLSTATE '42501' THEN
        RAISE NOTICE '✅ TEST 3 PASSED: Anonymous insert blocked by RLS';
    END;
    
    -- Reset role
    RESET ROLE;
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'TEST 4: Guest Checkout (Insert Orders)';
    RAISE NOTICE '========================================';
    
    -- Test 4: Insert order with tenant_id (should succeed)
    EXECUTE 'SET ROLE anon';
    
    BEGIN
        EXECUTE format('
            INSERT INTO online_orders (tenant_id, customer_email, customer_name, status, total_amount, currency)
            VALUES (%L, ''test-guest@example.com'', ''Test Guest'', ''pending'', 99.99, ''CLP'')
        ', v_tenant_id);
        
        RAISE NOTICE '✅ TEST 4 PASSED: Anonymous can create orders with tenant_id';
        
        -- Clean up
        RESET ROLE;
        DELETE FROM online_orders WHERE customer_email = 'test-guest@example.com';
        
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '❌ TEST 4 FAILED: % - %', SQLERRM, SQLSTATE;
        RESET ROLE;
    END;
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'TEST 5: Guest Checkout WITHOUT tenant_id';
    RAISE NOTICE '========================================';
    
    -- Test 5: Insert order without tenant_id (should fail)
    EXECUTE 'SET ROLE anon';
    
    BEGIN
        INSERT INTO online_orders (customer_email, customer_name, status, total_amount, currency)
        VALUES ('hacker@example.com', 'Hacker', 'pending', 0.01, 'CLP');
        
        RAISE NOTICE '❌ TEST 5 FAILED: Order created without tenant_id! SECURITY ISSUE!';
        RESET ROLE;
        DELETE FROM online_orders WHERE customer_email = 'hacker@example.com';
        
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '✅ TEST 5 PASSED: Cannot create order without tenant_id - %', SQLERRM;
        RESET ROLE;
    END;
    
    RESET ROLE;
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'ALL TESTS COMPLETED';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Review the results above:';
    RAISE NOTICE '- ✅ = Test passed (expected behavior)';
    RAISE NOTICE '- ❌ = Test failed (security issue!)';
    RAISE NOTICE '- ⚠️ = Warning (may need test data)';
    
END $$;

-- Reset role to ensure we are not stuck as anon
RESET ROLE;
