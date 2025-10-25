-- ============================================================================
-- CHECK YOUR CURRENT SESSION TENANT
-- ============================================================================
-- Run this WHILE LOGGED IN as ccatalansandoval7@gmail.com
-- ============================================================================

-- What does your JWT say RIGHT NOW?
SELECT 
  'JWT metadata tenant_id' as check,
  auth.jwt()->'user_metadata'->>'tenant_id' as tenant_id,
  auth.jwt()->'user_metadata'->>'role' as role;

-- What does user_tenant_id() return RIGHT NOW?
SELECT 
  'user_tenant_id() function' as check,
  public.user_tenant_id()::text as tenant_id;

-- What's in your auth.users record?
SELECT 
  'auth.users metadata' as check,
  email,
  raw_user_meta_data->>'tenant_id' as tenant_id,
  raw_user_meta_data->>'role' as role
FROM auth.users
WHERE id = auth.uid();

-- Do you have pending invitations?
SELECT 
  'Pending invitations' as check,
  i.tenant_id,
  t.shop_name,
  i.role,
  i.status
FROM user_invitations i
JOIN tenants t ON t.id = i.tenant_id
WHERE i.email = 'ccatalansandoval7@gmail.com'
ORDER BY i.created_at DESC;

-- ============================================================================
-- EXPECTED RESULTS FOR CLAUDIO:
-- tenant_id should be: 5fb195aa-2ec5-4a5d-b057-ed61156312ec
-- shop_name should be: "Claudio Catalán's Shop"
-- 
-- If you see: 97ef40bf-f58c-4f76-a629-c013fb3928cf (Vinabike)
-- Then your JWT has the wrong tenant_id!
-- ============================================================================
