-- ========================================
-- FIX PRODUCT_CATEGORIES RLS POLICIES
-- ========================================
-- The policies were missing 'to authenticated'
-- This fixes the SELECT issue where 0 rows were returned
-- ========================================

-- Drop existing policies
drop policy if exists "product_categories_select" on product_categories;
drop policy if exists "product_categories_insert" on product_categories;
drop policy if exists "product_categories_update" on product_categories;
drop policy if exists "product_categories_delete" on product_categories;

-- Recreate with 'to authenticated'
create policy "product_categories_select" on product_categories 
  for select 
  to authenticated 
  using (tenant_id = public.user_tenant_id());

create policy "product_categories_insert" on product_categories 
  for insert 
  to authenticated 
  with check (tenant_id = public.user_tenant_id());

create policy "product_categories_update" on product_categories 
  for update 
  to authenticated 
  using (tenant_id = public.user_tenant_id());

create policy "product_categories_delete" on product_categories 
  for delete 
  to authenticated 
  using (tenant_id = public.user_tenant_id());

-- Verify the fix
SELECT 
  tablename,
  policyname,
  roles,
  cmd
FROM pg_policies 
WHERE tablename = 'product_categories'
ORDER BY policyname;
