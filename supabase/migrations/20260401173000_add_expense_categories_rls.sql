alter table public.expense_categories enable row level security;

drop policy if exists "expense_categories_select" on public.expense_categories;
drop policy if exists "expense_categories_insert" on public.expense_categories;
drop policy if exists "expense_categories_update" on public.expense_categories;
drop policy if exists "expense_categories_delete" on public.expense_categories;

create policy "expense_categories_select" on public.expense_categories
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "expense_categories_insert" on public.expense_categories
  for insert
  to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "expense_categories_update" on public.expense_categories
  for update
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "expense_categories_delete" on public.expense_categories
  for delete
  to authenticated
  using (tenant_id = public.user_tenant_id());