-- ============================================================================
-- 🚀 ONE-LINE FIX: Seed Payment Methods for Your Tenant
-- ============================================================================
-- Just run this in Supabase SQL Editor and you're done!

SELECT public.seed_payment_methods_for_tenant(public.user_tenant_id());

-- That's it! Refresh your Flutter app and the payment dropdown works! ✨

-- ============================================================================
-- Want to verify? Run this:
SELECT code, name FROM payment_methods 
WHERE tenant_id = public.user_tenant_id() 
ORDER BY sort_order;
-- ============================================================================
