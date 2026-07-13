-- ========================================================================
-- DEPLOY: Public Store RLS Policies
-- Deploy to: Supabase SQL Editor
-- Purpose: Allow anonymous users to access public store data
-- ========================================================================

-- 1. TENANTS TABLE: Allow anonymous lookup by subdomain
drop policy if exists "public_tenants_select" on tenants;
drop policy if exists "tenant_select_anon" on tenants;

create policy "public_tenants_select" on tenants 
  for select 
  to anon
  using (is_active = true);

-- 2. WEBSITE BLOCKS: Allow anonymous read for homepage
drop policy if exists "public_website_blocks_select" on website_blocks;

create policy "public_website_blocks_select" on website_blocks 
  for select 
  to anon
  using (is_visible = true);

-- 3. Verify policies were created
select tablename, policyname, roles, cmd 
from pg_policies 
where tablename in ('tenants', 'website_blocks', 'products', 'website_settings', 'featured_products')
  and 'anon' = any(roles)
order by tablename, policyname;
