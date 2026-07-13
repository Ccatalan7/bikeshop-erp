-- ============================================================================
-- SIMPLE TEST: Is the multi-tenant FK fix working?
-- ============================================================================
-- Copy-paste this entire block into Supabase SQL Editor
-- If it says "SUCCESS: Cross-tenant FK was BLOCKED!" → Fix is working! ✅

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
  
  RAISE NOTICE '';
  RAISE NOTICE '🧪 Testing cross-tenant FK blocking...';
  RAISE NOTICE '   Attempting to create payment_method from Tenant A';
  RAISE NOTICE '   referencing account from Tenant B...';
  RAISE NOTICE '';
  
  -- Try to create payment_method with cross-tenant account_id
  BEGIN
    INSERT INTO payment_methods (tenant_id, code, name, account_id)
    VALUES (v_tenant_a, 'CROSS_TEST_' || extract(epoch from now())::text, 'Cross-Tenant Test', v_account_b)
    RETURNING id INTO v_pm_id;
    
    -- If we got here, FK did NOT block (BAD!)
    DELETE FROM payment_methods WHERE id = v_pm_id;
    RAISE EXCEPTION '';
    RAISE EXCEPTION '❌ ═══════════════════════════════════════════════════';
    RAISE EXCEPTION '❌ FAIL: Cross-tenant FK was ALLOWED!';
    RAISE EXCEPTION '❌ The fix is NOT deployed correctly!';
    RAISE EXCEPTION '❌ ═══════════════════════════════════════════════════';
    
  EXCEPTION
    WHEN foreign_key_violation OR check_violation THEN
      RAISE NOTICE '';
      RAISE NOTICE '✅ ═══════════════════════════════════════════════════';
      RAISE NOTICE '✅ SUCCESS: Cross-tenant FK was BLOCKED!';
      RAISE NOTICE '✅ THE FIX IS WORKING CORRECTLY!';
      RAISE NOTICE '✅ ═══════════════════════════════════════════════════';
      RAISE NOTICE '';
      RAISE NOTICE '   Details:';
      RAISE NOTICE '   • Payment method from Tenant A tried to reference Account from Tenant B';
      RAISE NOTICE '   • Database correctly rejected the cross-tenant reference';
      RAISE NOTICE '   • Multi-tenant isolation is enforced at FK level';
      RAISE NOTICE '';
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%FAIL%' THEN
        RAISE; -- Re-raise our custom failure message
      ELSE
        RAISE NOTICE '';
        RAISE NOTICE '⚠️  Unexpected error during test: %', SQLERRM;
        RAISE NOTICE '';
      END IF;
  END;
END $$;
