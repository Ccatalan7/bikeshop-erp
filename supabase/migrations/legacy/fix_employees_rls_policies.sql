-- Fix employees RLS policies to allow insert/update/delete by any tenant user
-- Drop existing policies
drop policy if exists "employees_insert" on employees;
drop policy if exists "employees_update" on employees;
drop policy if exists "employees_delete" on employees;

-- Recreate policies without manager role restriction
create policy "employees_insert" on employees for insert with check (
  tenant_id = public.user_tenant_id()
);

create policy "employees_update" on employees for update using (
  tenant_id = public.user_tenant_id()
);

create policy "employees_delete" on employees for delete using (
  tenant_id = public.user_tenant_id()
);
