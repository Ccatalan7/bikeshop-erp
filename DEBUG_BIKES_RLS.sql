-- DEBUG: Check why bikes RLS is failing
-- Run this in Supabase SQL Editor while logged in as ccatalan.us@gmail.com

-- 1. Check current user
select 
  auth.uid() as user_id,
  auth.email() as email;

-- 2. Check user_profiles for current user
select 
  user_id,
  tenant_id,
  role,
  created_at
from user_profiles
where user_id = auth.uid();

-- 3. Check what user_tenant_id() returns
select public.user_tenant_id() as tenant_id_from_function;

-- 4. Check if bikes table has RLS enabled
select 
  schemaname,
  tablename,
  rowsecurity as rls_enabled
from pg_tables
where tablename = 'bikes';

-- 5. Check what RLS policies exist on bikes table
select 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where tablename = 'bikes'
order by policyname;

-- 6. Test if you can see bikes (should return empty or bikes from your tenant)
select 
  id,
  tenant_id,
  customer_id,
  brand,
  model
from bikes
limit 5;

-- 7. Check tenants table
select id, name, subdomain from tenants limit 5;
