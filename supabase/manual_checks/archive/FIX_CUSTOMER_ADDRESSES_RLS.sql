-- ============================================================================
-- FIX: Add RLS policies for customer_addresses table
-- ============================================================================
-- The table has RLS enabled but NO POLICIES, blocking all operations!
-- This adds policies for both ERP users AND website customers
-- ============================================================================

-- Drop any existing policies
drop policy if exists "customer_addresses_select" on customer_addresses;
drop policy if exists "customer_addresses_insert" on customer_addresses;
drop policy if exists "customer_addresses_update" on customer_addresses;
drop policy if exists "customer_addresses_delete" on customer_addresses;
drop policy if exists "public_customer_addresses_select_own" on customer_addresses;
drop policy if exists "public_customer_addresses_insert_own" on customer_addresses;
drop policy if exists "public_customer_addresses_update_own" on customer_addresses;
drop policy if exists "public_customer_addresses_delete_own" on customer_addresses;

-- ============================================================================
-- ERP POLICIES (for tenant users via user_tenant_id())
-- ============================================================================
create policy "customer_addresses_select" on customer_addresses 
  for select 
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "customer_addresses_insert" on customer_addresses 
  for insert 
  to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "customer_addresses_update" on customer_addresses 
  for update 
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "customer_addresses_delete" on customer_addresses 
  for delete 
  to authenticated
  using (tenant_id = public.user_tenant_id());

-- ============================================================================
-- PUBLIC STORE POLICIES (for website customers via auth_user_id)
-- Website customers don't have user_profiles, so user_tenant_id() returns NULL
-- They can only access their OWN addresses
-- ============================================================================
create policy "public_customer_addresses_select_own" on customer_addresses 
  for select 
  to authenticated
  using (
    customer_id IN (
      SELECT id FROM customers WHERE auth_user_id = auth.uid()
    )
  );

create policy "public_customer_addresses_insert_own" on customer_addresses 
  for insert 
  to authenticated
  with check (
    customer_id IN (
      SELECT id FROM customers WHERE auth_user_id = auth.uid()
    )
    AND tenant_id IS NOT NULL
  );

create policy "public_customer_addresses_update_own" on customer_addresses 
  for update 
  to authenticated
  using (
    customer_id IN (
      SELECT id FROM customers WHERE auth_user_id = auth.uid()
    )
  );

create policy "public_customer_addresses_delete_own" on customer_addresses 
  for delete 
  to authenticated
  using (
    customer_id IN (
      SELECT id FROM customers WHERE auth_user_id = auth.uid()
    )
  );

-- Done!
select '✅ customer_addresses RLS policies created!' as status;
