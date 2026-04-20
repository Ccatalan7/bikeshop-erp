create table if not exists product_bulk_edit_history (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  operation text not null check (operation in ('classification', 'channels', 'pricing', 'stock', 'images')),
  scope_source text not null check (scope_source in ('selected', 'filtered', 'all')),
  status text not null check (status in ('completed', 'partial', 'failed', 'skipped')),
  actor_name text,
  summary text,
  scope_product_count integer not null default 0,
  enabled_product_count integer not null default 0,
  succeeded_product_count integer not null default 0,
  skipped_product_count integer not null default 0,
  failed_product_count integer not null default 0,
  filters_snapshot jsonb not null default '{}'::jsonb,
  config_snapshot jsonb not null default '{}'::jsonb,
  product_changes jsonb not null default '[]'::jsonb,
  errors jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamp with time zone not null default now(),
  unique(tenant_id, id)
);

create index if not exists idx_product_bulk_edit_history_tenant_created_at
  on product_bulk_edit_history(tenant_id, created_at desc);
create index if not exists idx_product_bulk_edit_history_created_by
  on product_bulk_edit_history(created_by);

alter table product_bulk_edit_history enable row level security;

drop policy if exists "product_bulk_edit_history_select" on product_bulk_edit_history;
drop policy if exists "product_bulk_edit_history_insert" on product_bulk_edit_history;
drop policy if exists "product_bulk_edit_history_update" on product_bulk_edit_history;
drop policy if exists "product_bulk_edit_history_delete" on product_bulk_edit_history;

create policy "product_bulk_edit_history_select" on product_bulk_edit_history
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "product_bulk_edit_history_insert" on product_bulk_edit_history
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "product_bulk_edit_history_update" on product_bulk_edit_history
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "product_bulk_edit_history_delete" on product_bulk_edit_history
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());