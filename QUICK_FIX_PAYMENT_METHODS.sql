-- ============================================================================
-- QUICK FIX: Seed Payment Methods for Existing Tenants
-- ============================================================================
-- This script seeds payment methods for existing tenants.
-- After deploying the updated core_schema.sql, NEW tenants will get payment
-- methods automatically. Use this script to seed EXISTING tenants.
-- ============================================================================

-- Option 1: Seed payment methods for YOUR tenant only
SELECT public.seed_payment_methods_for_tenant(public.user_tenant_id());

-- Option 2: Seed payment methods for ALL existing tenants (admin only)
-- Uncomment the block below to seed all tenants:
--
-- DO $$
-- DECLARE
--   tenant_record RECORD;
--   seeded_count INTEGER := 0;
-- BEGIN
--   FOR tenant_record IN SELECT id, name FROM tenants LOOP
--     PERFORM public.seed_payment_methods_for_tenant(tenant_record.id);
--     seeded_count := seeded_count + 1;
--     RAISE NOTICE 'Seeded payment methods for tenant: % (ID: %)', tenant_record.name, tenant_record.id;
--   END LOOP;
--   RAISE NOTICE '✅ Seeded payment methods for % tenants', seeded_count;
-- END $$;

-- ============================================================================
-- VERIFICATION: Check payment methods were created
-- ============================================================================
SELECT 
  'Payment methods for your tenant:' as info,
  code,
  name,
  requires_reference,
  is_active,
  sort_order
FROM payment_methods
WHERE tenant_id = public.user_tenant_id()
ORDER BY sort_order;

-- Step 4: Verify account links
SELECT 
  'Payment methods with their accounting accounts:' as info,
  pm.code as payment_code,
  pm.name as payment_name,
  a.code as account_code,
  a.name as account_name
FROM payment_methods pm
JOIN accounts a ON pm.account_id = a.id
WHERE pm.tenant_id = public.user_tenant_id()
ORDER BY pm.sort_order;

-- ============================================================================
-- ✅ DONE! You should see 4 payment methods above.
-- Now refresh your Flutter app and the dropdown will work!
-- ============================================================================
