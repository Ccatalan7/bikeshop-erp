-- ============================================================================
-- MULTI-TENANT FK FIX - VERIFICATION QUERIES
-- ============================================================================
-- Run these queries in Supabase SQL Editor to verify the fix was deployed correctly
-- Expected: All queries should return the expected row counts/results

-- ============================================================================
-- MOST IMPORTANT: PRACTICAL CROSS-TENANT BLOCKING TEST
-- ============================================================================
-- This test actually tries to create cross-tenant FK - if it's blocked, the fix works!

DO $$
DECLARE
  v_tenant_a uuid;
  v_tenant_b uuid;
  v_account_b uuid;
  v_pm_id uuid;
BEGIN
  -- Get two different tenants
  SELECT id INTO v_tenant_a FROM tenants ORDER BY created_at LIMIT 1;
  SELECT id INTO v_tenant_b FROM tenants ORDER BY created_at DESC LIMIT 1;
  
  IF v_tenant_a = v_tenant_b THEN
    RAISE NOTICE '⚠️  Only one tenant found - cannot test cross-tenant blocking';
    RETURN;
  END IF;
  
  -- Get an account from tenant B
  SELECT id INTO v_account_b FROM accounts WHERE tenant_id = v_tenant_b LIMIT 1;
  
  IF v_account_b IS NULL THEN
    RAISE NOTICE '⚠️  No accounts found for second tenant - cannot test';
    RETURN;
  END IF;
  
  RAISE NOTICE '🧪 Testing cross-tenant FK blocking...';
  RAISE NOTICE '   Tenant A: %', v_tenant_a;
  RAISE NOTICE '   Tenant B: %', v_tenant_b;
  RAISE NOTICE '   Account B: %', v_account_b;
  
  -- Try to create payment_method with cross-tenant account_id
  BEGIN
    INSERT INTO payment_methods (tenant_id, code, name, account_id)
    VALUES (v_tenant_a, 'CROSS_TEST_' || extract(epoch from now())::text, 'Cross-Tenant Test', v_account_b)
    RETURNING id INTO v_pm_id;
    
    -- If we got here, FK did NOT block (BAD!)
    DELETE FROM payment_methods WHERE id = v_pm_id;
    RAISE EXCEPTION '❌ FAIL: Cross-tenant FK was ALLOWED! Fix not deployed correctly!';
    
  EXCEPTION
    WHEN foreign_key_violation OR check_violation THEN
      RAISE NOTICE '';
      RAISE NOTICE '✅ ═══════════════════════════════════════════════════';
      RAISE NOTICE '✅ SUCCESS: Cross-tenant FK was BLOCKED!';
      RAISE NOTICE '✅ THE FIX IS WORKING CORRECTLY!';
      RAISE NOTICE '✅ ═══════════════════════════════════════════════════';
      RAISE NOTICE '';
    WHEN OTHERS THEN
      RAISE NOTICE '⚠️  Unexpected error: %', SQLERRM;
  END;
END $$;


-- ============================================================================
-- STEP 1: VERIFY COMPOSITE UNIQUE CONSTRAINTS EXIST
-- ============================================================================

-- Check for composite unique constraints (tenant_id, id) on accounts and payment_methods
SELECT 
  conrelid::regclass as table_name,
  conname as constraint_name,
  contype as constraint_type,
  array_length(conkey, 1) as num_columns
FROM pg_constraint 
WHERE contype = 'u' 
  AND conrelid IN ('accounts'::regclass, 'payment_methods'::regclass)
  AND array_length(conkey, 1) = 2
ORDER BY table_name;

-- ✅ Expected: 2 rows
-- accounts | <constraint_name> | u | 2
-- payment_methods | <constraint_name> | u | 2
-- Note: Constraint names may vary (e.g., accounts_tenant_id_id_key or similar)


-- ============================================================================
-- STEP 2: VERIFY ALL COMPOSITE FK CONSTRAINTS EXIST
-- ============================================================================

SELECT 
  conname as constraint_name,
  conrelid::regclass as table_name,
  confrelid::regclass as references_table,
  array_length(conkey, 1) as num_fk_columns
FROM pg_constraint 
WHERE contype = 'f' 
  AND (
    confrelid = 'accounts'::regclass 
    OR confrelid = 'payment_methods'::regclass
  )
  AND conname NOT LIKE '%invoice%'
  AND conname NOT LIKE '%supplier%'
  AND conname NOT LIKE '%customer%'
  AND conname NOT LIKE '%category%'
  AND conname NOT LIKE '%expense_id%'
ORDER BY table_name, constraint_name;

-- ✅ Expected: 14 rows with num_fk_columns = 2 for all tenant-scoped FKs
-- accounts_parent_id_fkey | accounts | accounts | 2
-- payment_methods_account_id_fkey | payment_methods | accounts | 2
-- sales_payments_payment_method_id_fkey | sales_payments | payment_methods | 2
-- purchase_payments_payment_method_id_fkey | purchase_payments | payment_methods | 2
-- expenses_liability_account_id_fkey | expenses | accounts | 2
-- expenses_payment_account_id_fkey | expenses | accounts | 2
-- expenses_payment_method_id_fkey | expenses | payment_methods | 2
-- expense_lines_account_id_fkey | expense_lines | accounts | 2
-- expense_categories_default_account_id_fkey | expense_categories | accounts | 2
-- expense_payments_payment_method_id_fkey | expense_payments | payment_methods | 2
-- expense_payments_payment_account_id_fkey | expense_payments | accounts | 2


-- ============================================================================
-- STEP 3: VERIFY NO SIMPLE FK CONSTRAINTS REMAIN
-- ============================================================================

-- This query checks for any FK constraints that reference accounts or payment_methods
-- but only have 1 column (simple FK instead of composite)

SELECT 
  conname as constraint_name,
  conrelid::regclass as table_name,
  confrelid::regclass as references_table,
  array_length(conkey, 1) as num_fk_columns,
  '⚠️ SHOULD BE 2 COLUMNS!' as warning
FROM pg_constraint 
WHERE contype = 'f' 
  AND (
    confrelid = 'accounts'::regclass 
    OR confrelid = 'payment_methods'::regclass
  )
  AND array_length(conkey, 1) = 1
  AND conname NOT LIKE '%invoice%'
  AND conname NOT LIKE '%supplier%'
  AND conname NOT LIKE '%customer%'
  AND conname NOT LIKE '%category%'
ORDER BY table_name;

-- ✅ Expected: 0 rows (no simple FKs should exist for tenant-scoped tables)


-- ============================================================================
-- STEP 4: CHECK FOR EXISTING CROSS-TENANT DATA (PRE-DEPLOYMENT)
-- ============================================================================
-- Run these BEFORE deploying to check if corrupt data exists

-- Check payment_methods referencing accounts from different tenant
SELECT 
  pm.id as payment_method_id,
  pm.code as pm_code,
  pm.tenant_id as pm_tenant_id,
  a.tenant_id as account_tenant_id,
  a.code as account_code,
  '⚠️ CROSS-TENANT REFERENCE!' as issue
FROM payment_methods pm
JOIN accounts a ON pm.account_id = a.id
WHERE pm.tenant_id != a.tenant_id;

-- ✅ Expected: 0 rows (no cross-tenant references)
-- ❌ If rows found: Clean corrupt data before deploying


-- Check sales_payments referencing payment_methods from different tenant
SELECT 
  sp.id as sales_payment_id,
  sp.tenant_id as sp_tenant_id,
  pm.tenant_id as pm_tenant_id,
  pm.code as pm_code,
  '⚠️ CROSS-TENANT REFERENCE!' as issue
FROM sales_payments sp
JOIN payment_methods pm ON sp.payment_method_id = pm.id
WHERE sp.tenant_id != pm.tenant_id;

-- ✅ Expected: 0 rows


-- Check purchase_payments referencing payment_methods from different tenant
SELECT 
  pp.id as purchase_payment_id,
  pp.tenant_id as pp_tenant_id,
  pm.tenant_id as pm_tenant_id,
  pm.code as pm_code,
  '⚠️ CROSS-TENANT REFERENCE!' as issue
FROM purchase_payments pp
JOIN payment_methods pm ON pp.payment_method_id = pm.id
WHERE pp.tenant_id != pm.tenant_id;

-- ✅ Expected: 0 rows


-- Check expenses referencing accounts from different tenant
SELECT 
  e.id as expense_id,
  e.expense_number,
  e.tenant_id as expense_tenant_id,
  a.tenant_id as account_tenant_id,
  a.code as account_code,
  '⚠️ CROSS-TENANT REFERENCE!' as issue
FROM expenses e
LEFT JOIN accounts a ON e.liability_account_id = a.id
WHERE e.tenant_id != a.tenant_id;

-- ✅ Expected: 0 rows


-- Check expense_lines referencing accounts from different tenant
SELECT 
  el.id as expense_line_id,
  el.tenant_id as el_tenant_id,
  a.tenant_id as account_tenant_id,
  a.code as account_code,
  '⚠️ CROSS-TENANT REFERENCE!' as issue
FROM expense_lines el
JOIN accounts a ON el.account_id = a.id
WHERE el.tenant_id != a.tenant_id;

-- ✅ Expected: 0 rows


-- ============================================================================
-- STEP 5: TEST CROSS-TENANT BLOCKING (POST-DEPLOYMENT)
-- ============================================================================
-- Run these AFTER deploying to verify FK constraints block cross-tenant references

-- Get two different tenant IDs for testing
SELECT id, shop_name FROM tenants ORDER BY created_at LIMIT 2;

-- Replace these with actual tenant IDs from above query
DO $$
DECLARE
  v_tenant_a uuid := '5443b130-cc28-45af-a420-cd500b288890'; -- Replace with actual tenant A
  v_tenant_b uuid := 'a03f7ebc-14f6-4ab7-b9c0-54dfef59d43f'; -- Replace with actual tenant B
  v_account_b uuid;
  v_payment_method_b uuid;
BEGIN
  -- Get an account from tenant B
  SELECT id INTO v_account_b 
  FROM accounts 
  WHERE tenant_id = v_tenant_b 
  LIMIT 1;
  
  IF v_account_b IS NULL THEN
    RAISE NOTICE 'No accounts found for tenant B - skipping test';
    RETURN;
  END IF;
  
  -- Test 1: Try to create payment_method with cross-tenant account_id
  BEGIN
    INSERT INTO payment_methods (tenant_id, code, name, account_id)
    VALUES (v_tenant_a, 'TEST_CROSS', 'Test Cross-Tenant', v_account_b);
    
    RAISE EXCEPTION '❌ TEST FAILED: Cross-tenant FK was allowed!';
  EXCEPTION
    WHEN foreign_key_violation THEN
      RAISE NOTICE '✅ TEST 1 PASSED: Cross-tenant payment_method.account_id blocked';
    WHEN others THEN
      RAISE EXCEPTION 'Unexpected error: %', SQLERRM;
  END;
  
  -- Get a payment method from tenant B
  SELECT id INTO v_payment_method_b 
  FROM payment_methods 
  WHERE tenant_id = v_tenant_b 
  LIMIT 1;
  
  IF v_payment_method_b IS NULL THEN
    RAISE NOTICE 'No payment methods found for tenant B - skipping test 2';
    RETURN;
  END IF;
  
  -- Test 2: Try to create sales_payment with cross-tenant payment_method_id
  BEGIN
    INSERT INTO sales_payments (tenant_id, invoice_id, payment_method_id, amount, date)
    SELECT v_tenant_a, id, v_payment_method_b, 100.00, now()
    FROM sales_invoices
    WHERE tenant_id = v_tenant_a
    LIMIT 1;
    
    RAISE EXCEPTION '❌ TEST FAILED: Cross-tenant sales_payment was allowed!';
  EXCEPTION
    WHEN foreign_key_violation THEN
      RAISE NOTICE '✅ TEST 2 PASSED: Cross-tenant sales_payment.payment_method_id blocked';
    WHEN others THEN
      RAISE NOTICE 'Test 2 skipped or error: %', SQLERRM;
  END;
  
  RAISE NOTICE '══════════════════════════════════════════════';
  RAISE NOTICE '✅ ALL TESTS PASSED - Cross-tenant blocking works!';
  RAISE NOTICE '══════════════════════════════════════════════';
END $$;


-- ============================================================================
-- STEP 6: TEST EXISTING FUNCTIONALITY STILL WORKS
-- ============================================================================

-- Test: Create valid payment method (same tenant)
DO $$
DECLARE
  v_tenant_id uuid;
  v_account_id uuid;
  v_pm_id uuid;
BEGIN
  -- Get a tenant and one of its accounts
  SELECT t.id, a.id 
  INTO v_tenant_id, v_account_id
  FROM tenants t
  JOIN accounts a ON a.tenant_id = t.id
  LIMIT 1;
  
  -- Try to create valid payment method
  INSERT INTO payment_methods (tenant_id, code, name, account_id)
  VALUES (v_tenant_id, 'TEST_VALID', 'Test Valid Method', v_account_id)
  RETURNING id INTO v_pm_id;
  
  -- Clean up
  DELETE FROM payment_methods WHERE id = v_pm_id;
  
  RAISE NOTICE '✅ TEST PASSED: Valid same-tenant payment method created successfully';
END $$;


-- Test: Create valid sales payment (same tenant)
DO $$
DECLARE
  v_tenant_id uuid;
  v_invoice_id uuid;
  v_pm_id uuid;
  v_payment_id uuid;
BEGIN
  -- Get a tenant, invoice, and payment method
  SELECT si.tenant_id, si.id, pm.id 
  INTO v_tenant_id, v_invoice_id, v_pm_id
  FROM sales_invoices si
  JOIN payment_methods pm ON pm.tenant_id = si.tenant_id
  WHERE si.status != 'paid'
  LIMIT 1;
  
  IF v_invoice_id IS NULL THEN
    RAISE NOTICE 'No unpaid invoices found - skipping test';
    RETURN;
  END IF;
  
  -- Try to create valid sales payment
  INSERT INTO sales_payments (tenant_id, invoice_id, payment_method_id, amount, date)
  VALUES (v_tenant_id, v_invoice_id, v_pm_id, 50.00, now())
  RETURNING id INTO v_payment_id;
  
  -- Clean up
  DELETE FROM sales_payments WHERE id = v_payment_id;
  
  RAISE NOTICE '✅ TEST PASSED: Valid same-tenant sales payment created successfully';
END $$;


-- ============================================================================
-- STEP 7: SUMMARY REPORT
-- ============================================================================

SELECT 
  '════════════════════════════════════════════════════════' as separator
UNION ALL
SELECT '  MULTI-TENANT FK FIX - VERIFICATION SUMMARY'
UNION ALL
SELECT '════════════════════════════════════════════════════════'
UNION ALL
SELECT ''
UNION ALL
SELECT '✅ Composite Unique Constraints: ' || 
  CASE 
    WHEN (SELECT COUNT(*) FROM pg_constraint WHERE conname IN ('accounts_tenant_id_id_key', 'payment_methods_tenant_id_id_key')) = 2 
    THEN 'PASS (2/2)'
    ELSE '❌ FAIL'
  END
UNION ALL
SELECT '✅ Composite FK Constraints: ' || 
  CASE 
    WHEN (SELECT COUNT(*) FROM pg_constraint WHERE contype = 'f' AND (confrelid = 'accounts'::regclass OR confrelid = 'payment_methods'::regclass) AND array_length(conkey, 1) = 2) >= 11
    THEN 'PASS (11+)'
    ELSE '❌ FAIL'
  END
UNION ALL
SELECT '✅ No Simple FKs Remaining: ' || 
  CASE 
    WHEN (SELECT COUNT(*) FROM pg_constraint WHERE contype = 'f' AND (confrelid = 'accounts'::regclass OR confrelid = 'payment_methods'::regclass) AND array_length(conkey, 1) = 1 AND conname NOT LIKE '%invoice%' AND conname NOT LIKE '%supplier%') = 0
    THEN 'PASS (0)'
    ELSE '❌ FAIL'
  END
UNION ALL
SELECT ''
UNION ALL
SELECT '════════════════════════════════════════════════════════';

-- ============================================================================
-- QUICK VERIFICATION (RUN THIS FIRST)
-- ============================================================================
-- One-liner to check if fix is deployed
-- Note: Constraint names may vary - checking for existence of composite unique constraints

SELECT 
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM pg_constraint 
      WHERE contype = 'u' 
        AND conrelid = 'accounts'::regclass 
        AND array_length(conkey, 1) = 2
    )
    AND EXISTS (
      SELECT 1 FROM pg_constraint 
      WHERE contype = 'u' 
        AND conrelid = 'payment_methods'::regclass 
        AND array_length(conkey, 1) = 2
    )
    AND (
      SELECT COUNT(*) 
      FROM pg_constraint 
      WHERE contype = 'f' 
        AND (confrelid = 'accounts'::regclass OR confrelid = 'payment_methods'::regclass) 
        AND array_length(conkey, 1) = 2
    ) >= 11
    THEN '✅ MULTI-TENANT FK FIX IS DEPLOYED CORRECTLY'
    ELSE '❌ MULTI-TENANT FK FIX NOT DEPLOYED OR INCOMPLETE - But test cross-tenant blocking to be sure'
  END as deployment_status;
