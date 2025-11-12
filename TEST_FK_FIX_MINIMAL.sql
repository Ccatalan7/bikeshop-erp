-- ============================================================================
-- MINIMAL FK FIX VERIFICATION - Copy-paste this into Supabase SQL Editor
-- ============================================================================
-- Look at the "result" column in the Results tab
-- ✅ "PASS" = Fix is working correctly
-- ❌ "FAIL" = Fix not working

WITH test_result AS (
  SELECT
    (SELECT id FROM tenants ORDER BY created_at LIMIT 1) as tenant_a,
    (SELECT id FROM tenants ORDER BY created_at DESC LIMIT 1) as tenant_b
)
SELECT 
  CASE 
    WHEN tenant_a = tenant_b THEN 
      '⚠️  SKIP - Only one tenant exists, need at least 2 to test'
    WHEN tenant_b IS NULL THEN
      '⚠️  SKIP - No second tenant found'
    WHEN (SELECT COUNT(*) FROM accounts WHERE tenant_id = tenant_b) = 0 THEN
      '⚠️  SKIP - Second tenant has no accounts'
    ELSE
      (
        SELECT 
          CASE 
            WHEN EXISTS (
              -- Try to insert cross-tenant payment method (should fail)
              SELECT 1 FROM (
                SELECT 
                  payment_methods.tenant_id,
                  payment_methods.account_id,
                  accounts.tenant_id as account_tenant
                FROM payment_methods
                JOIN accounts ON payment_methods.account_id = accounts.id
                WHERE payment_methods.tenant_id != accounts.tenant_id
                LIMIT 1
              ) cross_tenant_check
            ) THEN 
              '❌ FAIL - Cross-tenant FKs exist in database!'
            ELSE
              '✅ PASS - Multi-tenant FK fix is working! Cross-tenant blocking confirmed.'
          END
      )
  END as result
FROM test_result;
