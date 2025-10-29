-- ========================================
-- DEBUG CATEGORY VISIBILITY
-- ========================================
-- Check if current user can see their categories
-- Run this in Supabase SQL Editor AS AUTHENTICATED USER
-- ========================================

-- 1. Check current user context
SELECT 
  auth.uid() as current_user_id,
  (SELECT email FROM auth.users WHERE id = auth.uid()) as email,
  public.user_tenant_id() as tenant_id_from_function;

-- 2. Check user_profiles record
SELECT * FROM user_profiles WHERE user_id = auth.uid();

-- 3. Check if categories exist for this tenant (bypass RLS with USING permissions)
SELECT 
  id,
  tenant_id,
  name,
  full_path,
  is_active,
  created_at
FROM product_categories
WHERE tenant_id = public.user_tenant_id()
ORDER BY created_at DESC;

-- 4. Check RLS policies on product_categories
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
WHERE tablename = 'product_categories'
ORDER BY policyname;

-- 5. Check if RLS is enabled
SELECT 
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables 
WHERE tablename = 'product_categories';

-- 6. Try to count categories (should work if RLS is correct)
SELECT COUNT(*) as total_categories
FROM product_categories;
