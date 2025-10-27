-- ============================================================================
-- CHECK WHO IS CURRENTLY LOGGED IN
-- ============================================================================

-- Get the current authenticated user
SELECT 
  'Current User' as info,
  auth.uid() as user_id,
  auth.email() as email;

-- Get ALL users in the system
SELECT 
  'All Users' as info,
  id,
  email,
  created_at,
  email_confirmed_at
FROM auth.users
ORDER BY created_at DESC;

-- Get ALL tenants in the system
SELECT 
  'All Tenants' as info,
  id,
  shop_name,
  subdomain,
  owner_email,
  created_at
FROM tenants
ORDER BY created_at DESC;

-- Get ALL user_profiles in the system
SELECT 
  'All Profiles' as info,
  up.id,
  up.user_id,
  up.tenant_id,
  up.role,
  u.email as user_email
FROM user_profiles up
LEFT JOIN auth.users u ON up.user_id = u.id
ORDER BY up.created_at DESC;
