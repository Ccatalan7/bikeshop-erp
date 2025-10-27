-- ============================================================================
-- MANUAL STEP-BY-STEP DELETION
-- User: ccatalan.us@gmail.com
-- ============================================================================
-- Run each query ONE AT A TIME to see what's being deleted
-- ============================================================================

-- STEP 1: Find the user ID
SELECT 
  id,
  email,
  created_at
FROM auth.users 
WHERE email = 'ccatalan.us@gmail.com';

-- Copy the user ID from the result above, then run:

-- STEP 2: Find the tenant ID
SELECT 
  up.tenant_id,
  t.shop_name,
  t.subdomain,
  t.created_at
FROM public.user_profiles up
JOIN public.tenants t ON up.tenant_id = t.id
WHERE up.user_id = '<PASTE_USER_ID_HERE>';

-- Copy the tenant ID, then run:

-- STEP 3: See what will be deleted (preview)
SELECT 'tenants' as table_name, COUNT(*) FROM public.tenants WHERE id = '<PASTE_TENANT_ID_HERE>'
UNION ALL
SELECT 'products', COUNT(*) FROM public.products WHERE tenant_id = '<PASTE_TENANT_ID_HERE>'
UNION ALL
SELECT 'customers', COUNT(*) FROM public.customers WHERE tenant_id = '<PASTE_TENANT_ID_HERE>'
UNION ALL
SELECT 'sales_invoices', COUNT(*) FROM public.sales_invoices WHERE tenant_id = '<PASTE_TENANT_ID_HERE>'
UNION ALL
SELECT 'purchase_invoices', COUNT(*) FROM public.purchase_invoices WHERE tenant_id = '<PASTE_TENANT_ID_HERE>'
UNION ALL
SELECT 'journal_entries', COUNT(*) FROM public.journal_entries WHERE tenant_id = '<PASTE_TENANT_ID_HERE>'
UNION ALL
SELECT 'employees', COUNT(*) FROM public.employees WHERE tenant_id = '<PASTE_TENANT_ID_HERE>';

-- STEP 4: Delete tenant (CASCADE will delete all related data)
DELETE FROM public.tenants WHERE id = '<PASTE_TENANT_ID_HERE>';

-- STEP 5: Delete user profile
DELETE FROM public.user_profiles WHERE user_id = '<PASTE_USER_ID_HERE>';

-- STEP 6: Delete auth user
DELETE FROM auth.users WHERE id = '<PASTE_USER_ID_HERE>';

-- STEP 7: Verify deletion (should all return 0)
SELECT COUNT(*) FROM auth.users WHERE email = 'ccatalan.us@gmail.com';
SELECT COUNT(*) FROM public.user_profiles up 
  JOIN auth.users u ON up.user_id = u.id 
  WHERE u.email = 'ccatalan.us@gmail.com';
