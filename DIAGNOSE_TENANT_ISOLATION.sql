-- ============================================================================
-- TENANT ISOLATION DIAGNOSTIC SCRIPT
-- ============================================================================
-- Run this in Supabase SQL Editor while logged in as your test user
-- This will show you exactly what's happening with tenant isolation
-- ============================================================================

-- 1️⃣ Check what tenant_id YOUR JWT contains
select 
  'Your JWT tenant_id' as check_name,
  auth.jwt()->'user_metadata'->>'tenant_id' as result;

-- 2️⃣ Check what user_tenant_id() function returns
select 
  'user_tenant_id() returns' as check_name,
  public.user_tenant_id()::text as result;

-- 3️⃣ Check your user record in auth.users
select 
  'Your auth.users record' as check_name,
  email,
  raw_user_meta_data->>'tenant_id' as tenant_id_in_metadata,
  raw_user_meta_data->>'role' as role,
  created_at
from auth.users
where id = auth.uid();

-- 4️⃣ Check all tenants in the system
select 
  'All tenants' as check_name,
  id,
  shop_name,
  owner_email,
  created_at
from tenants
order by created_at;

-- 5️⃣ Check how many products exist per tenant
select 
  'Products per tenant' as check_name,
  coalesce(t.shop_name, 'NULL tenant_id') as tenant,
  count(p.id) as product_count
from products p
left join tenants t on t.id = p.tenant_id
group by t.shop_name, p.tenant_id
order by product_count desc;

-- 6️⃣ Check if products have NULL tenant_id
select 
  'Products with NULL tenant_id' as check_name,
  count(*) as count
from products
where tenant_id is null;

-- 7️⃣ Check RLS status on products table
select 
  'RLS enabled on products?' as check_name,
  relrowsecurity::text as result
from pg_class
where relname = 'products';

-- 8️⃣ Check existing RLS policies on products
select 
  'Products RLS policies' as check_name,
  polname as policy_name,
  polcmd as command,
  polpermissive::text as permissive,
  pg_get_expr(polqual, polrelid) as using_expression
from pg_policy
where polrelid = 'products'::regclass;

-- 9️⃣ Check if you have any pending invitations
select 
  'Your pending invitations' as check_name,
  tenant_id,
  email,
  role,
  status,
  expires_at,
  created_at
from user_invitations
where email = (select email from auth.users where id = auth.uid())
order by created_at desc;

-- 🔟 Check all users and their tenant assignments
select 
  'All users and tenants' as check_name,
  u.email,
  u.raw_user_meta_data->>'tenant_id' as tenant_id,
  u.raw_user_meta_data->>'role' as role,
  t.shop_name
from auth.users u
left join tenants t on t.id = (u.raw_user_meta_data->>'tenant_id')::uuid
order by u.created_at;

-- ============================================================================
-- INTERPRETATION GUIDE:
-- ============================================================================
-- If you see Vinabike products:
--   → Check #1 and #2: Does your JWT contain Vinabike's tenant_id?
--   → Check #3: Does your auth.users record have the wrong tenant_id?
--   → Check #9: Do you have a pending invitation to Vinabike?
--
-- If products have NULL tenant_id:
--   → Check #6: All existing products need tenant_id assigned
--   → Run: UPDATE products SET tenant_id = '[vinabike-tenant-id]' WHERE tenant_id IS NULL;
--
-- If RLS is disabled:
--   → Check #7: Should show 'true'
--   → Run: ALTER TABLE products ENABLE ROW LEVEL SECURITY;
-- ============================================================================
