-- QUICK FIX: Add missing RLS policies for bikes table
-- This allows you to continue working while preparing full schema deployment
-- Run this in Supabase SQL Editor

-- Enable RLS on bikes table (if not already enabled)
alter table bikes enable row level security;

-- Create tenant-isolated RLS policies for bikes
do $$ begin
  -- Drop existing policies if any
  drop policy if exists "bikes_select" on bikes;
  drop policy if exists "bikes_insert" on bikes;
  drop policy if exists "bikes_update" on bikes;
  drop policy if exists "bikes_delete" on bikes;
  
  -- Create new tenant-isolated policies using user_tenant_id() helper
  create policy "bikes_select" on bikes 
    for select 
    using (tenant_id = public.user_tenant_id());
  
  create policy "bikes_insert" on bikes 
    for insert 
    with check (tenant_id = public.user_tenant_id());
  
  create policy "bikes_update" on bikes 
    for update 
    using (tenant_id = public.user_tenant_id());
  
  create policy "bikes_delete" on bikes 
    for delete 
    using (tenant_id = public.user_tenant_id());
  
  raise notice '✓ Created RLS policies for bikes table';
exception
  when others then
    raise notice 'Error creating bikes policies: %', sqlerrm;
end $$;
