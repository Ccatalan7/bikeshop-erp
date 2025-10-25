-- ============================================================================
-- DEBUG: Check tenant assignment and RLS policies
-- ============================================================================

-- 1. Check which tenant ccatalansandoval7@gmail.com belongs to
SELECT 
  id,
  email,
  raw_app_meta_data->>'tenant_id' as assigned_tenant_id,
  raw_app_meta_data->>'role' as role
FROM auth.users
WHERE email = 'ccatalansandoval7@gmail.com';

-- 2. Check what user_tenant_id() function returns for current user
SELECT public.user_tenant_id() as current_user_tenant_id;

-- 3. List all tenants
SELECT * FROM tenants ORDER BY created_at;

-- 4. Check company_settings for both tenants
SELECT 
  tenant_id,
  key,
  value
FROM company_settings
WHERE key = 'company_logo'
ORDER BY tenant_id;

-- 5. Check if RLS is enabled on company_settings
SELECT 
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables
WHERE tablename = 'company_settings';

-- 6. Check RLS policies on company_settings
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'company_settings';

-- 7. Check products table tenant_id distribution
SELECT 
  tenant_id,
  COUNT(*) as product_count
FROM products
GROUP BY tenant_id
ORDER BY tenant_id;

-- 8. Check if RLS is enabled on products
SELECT 
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables
WHERE tablename = 'products';

-- 9. Check RLS policies on products
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE tablename = 'products';
