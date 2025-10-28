-- Fix suppliers table RLS policies and multi-tenant setup

-- 1. Add tenant_id index if missing
create index if not exists idx_suppliers_tenant on suppliers(tenant_id);

-- 2. Add unique constraint for tenant_id + name (prevents duplicate supplier names per tenant)
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'suppliers'::regclass
    and conname = 'suppliers_tenant_name_unique'
  ) then
    alter table suppliers add constraint suppliers_tenant_name_unique unique (tenant_id, name);
  end if;
end $$;

-- 3. Enable RLS
alter table suppliers enable row level security;

-- 4. Drop existing policies if any
drop policy if exists "suppliers_select" on suppliers;
drop policy if exists "suppliers_insert" on suppliers;
drop policy if exists "suppliers_update" on suppliers;
drop policy if exists "suppliers_delete" on suppliers;

-- 5. Recreate policies with proper tenant isolation
create policy "suppliers_select" on suppliers 
  for select 
  using (tenant_id = public.user_tenant_id());

create policy "suppliers_insert" on suppliers 
  for insert 
  with check (tenant_id = public.user_tenant_id());

create policy "suppliers_update" on suppliers 
  for update 
  using (tenant_id = public.user_tenant_id());

create policy "suppliers_delete" on suppliers 
  for delete 
  using (tenant_id = public.user_tenant_id());
