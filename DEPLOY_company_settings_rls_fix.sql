-- Fix company_settings table for multi-tenancy
-- Deploy this in Supabase SQL Editor

-- Step 1: Drop old wrong unique constraint (global key, not per-tenant)
do $$ 
begin
  -- Drop constraint if it exists
  if exists (
    select 1 from pg_constraint 
    where conname = 'company_settings_key_key'
  ) then
    alter table company_settings drop constraint company_settings_key_key;
    raise notice '✓ Dropped old global unique constraint on key';
  end if;
exception
  when others then
    raise notice '⚠ Could not drop constraint: %', SQLERRM;
end $$;

-- Step 2: Ensure correct unique constraint exists (per-tenant)
do $$
begin
  -- Check if correct constraint exists
  if not exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    where t.relname = 'company_settings'
    and c.contype = 'u'
    and array_length(c.conkey, 1) = 2  -- Composite constraint
  ) then
    -- Create the correct per-tenant unique constraint
    alter table company_settings add constraint company_settings_tenant_key_unique unique (tenant_id, key);
    raise notice '✓ Created per-tenant unique constraint';
  else
    raise notice '✓ Per-tenant unique constraint already exists';
  end if;
exception
  when others then
    raise notice '⚠ Could not create constraint: %', SQLERRM;
end $$;

-- Step 3: Fix RLS policies (add 'to authenticated')
drop policy if exists "company_settings_select" on company_settings;
drop policy if exists "company_settings_insert" on company_settings;
drop policy if exists "company_settings_update" on company_settings;
drop policy if exists "company_settings_delete" on company_settings;

create policy "company_settings_select" on company_settings 
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "company_settings_insert" on company_settings 
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "company_settings_update" on company_settings 
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "company_settings_delete" on company_settings 
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

