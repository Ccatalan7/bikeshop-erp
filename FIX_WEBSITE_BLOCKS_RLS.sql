-- ============================================================================
-- FIX WEBSITE_BLOCKS RLS POLICIES
-- ============================================================================
-- Problem: RLS policies use user_tenant_id() function which can cause issues
-- Solution: Use direct user_profiles check pattern (same as website_settings fix)
-- ============================================================================

-- Drop old policies
drop policy if exists "website_blocks_select" on website_blocks;
drop policy if exists "website_blocks_insert" on website_blocks;
drop policy if exists "website_blocks_update" on website_blocks;
drop policy if exists "website_blocks_delete" on website_blocks;

-- Create new policies with direct user_profiles check
create policy "website_blocks_select" on website_blocks 
  for select 
  using (
    tenant_id in (
      select tenant_id 
      from user_profiles 
      where user_id = auth.uid()
    )
  );

create policy "website_blocks_insert" on website_blocks 
  for insert 
  with check (
    tenant_id in (
      select tenant_id 
      from user_profiles 
      where user_id = auth.uid()
    )
  );

create policy "website_blocks_update" on website_blocks 
  for update 
  using (
    tenant_id in (
      select tenant_id 
      from user_profiles 
      where user_id = auth.uid()
    )
  );

create policy "website_blocks_delete" on website_blocks 
  for delete 
  using (
    tenant_id in (
      select tenant_id 
      from user_profiles 
      where user_id = auth.uid()
    )
  );

-- Verify
select 
  schemaname, 
  tablename, 
  policyname, 
  permissive, 
  roles, 
  cmd
from pg_policies 
where tablename = 'website_blocks'
order by policyname;
