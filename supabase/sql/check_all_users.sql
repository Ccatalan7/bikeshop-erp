-- ========================================
-- CHECK ALL USERS, PROFILES, AND TENANTS
-- ========================================
-- This shows all users with their profile and tenant data
-- Run this in Supabase SQL Editor
-- ========================================

SELECT 
  u.id as user_id,
  u.email,
  u.created_at as user_created_at,
  u.email_confirmed_at,
  u.last_sign_in_at,
  
  -- User profile data
  up.tenant_id,
  up.role,
  up.created_at as profile_created_at,
  
  -- Tenant data
  t.shop_name,
  t.subdomain,
  t.is_active as tenant_active,
  t.created_at as tenant_created_at,
  
  -- Status checks
  CASE 
    WHEN up.user_id IS NULL THEN '❌ NO PROFILE'
    WHEN up.tenant_id IS NULL THEN '❌ NO TENANT'
    WHEN t.id IS NULL THEN '❌ TENANT NOT FOUND'
    ELSE '✅ OK'
  END as status
  
FROM auth.users u
LEFT JOIN public.user_profiles up ON up.user_id = u.id
LEFT JOIN public.tenants t ON t.id = up.tenant_id
ORDER BY u.created_at DESC;

-- Summary counts
SELECT 
  COUNT(DISTINCT u.id) as total_users,
  COUNT(DISTINCT up.user_id) as users_with_profile,
  COUNT(DISTINCT CASE WHEN up.tenant_id IS NOT NULL THEN up.user_id END) as users_with_tenant,
  COUNT(DISTINCT t.id) as total_tenants
FROM auth.users u
LEFT JOIN public.user_profiles up ON up.user_id = u.id
LEFT JOIN public.tenants t ON t.id = up.tenant_id;
