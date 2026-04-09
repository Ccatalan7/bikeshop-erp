create table if not exists bike_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  bike_id uuid references bikes(id) on delete cascade not null,
  catalog_bike_id uuid references bike_catalog(id) on delete set null,
  intake_profile jsonb not null default '{}'::jsonb,
  technical_profile jsonb not null default '{}'::jsonb,
  summary_snapshot jsonb not null default '{}'::jsonb,
  last_confirmed_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(bike_id)
);

do $$
begin
  if not exists (select 1 from information_schema.columns where table_name = 'bike_profiles' and column_name = 'tenant_id') then
    alter table bike_profiles add column tenant_id uuid references tenants(id) on delete cascade not null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_profiles' and column_name = 'bike_id') then
    alter table bike_profiles add column bike_id uuid references bikes(id) on delete cascade not null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_profiles' and column_name = 'catalog_bike_id') then
    alter table bike_profiles add column catalog_bike_id uuid references bike_catalog(id) on delete set null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_profiles' and column_name = 'intake_profile') then
    alter table bike_profiles add column intake_profile jsonb not null default '{}'::jsonb;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_profiles' and column_name = 'technical_profile') then
    alter table bike_profiles add column technical_profile jsonb not null default '{}'::jsonb;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_profiles' and column_name = 'summary_snapshot') then
    alter table bike_profiles add column summary_snapshot jsonb not null default '{}'::jsonb;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_profiles' and column_name = 'last_confirmed_at') then
    alter table bike_profiles add column last_confirmed_at timestamp with time zone;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_profiles' and column_name = 'created_at') then
    alter table bike_profiles add column created_at timestamp with time zone not null default now();
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_profiles' and column_name = 'updated_at') then
    alter table bike_profiles add column updated_at timestamp with time zone not null default now();
  end if;

  if not exists (
    select 1
    from information_schema.table_constraints
    where table_name = 'bike_profiles'
      and constraint_type = 'UNIQUE'
      and constraint_name = 'bike_profiles_bike_id_key'
  ) then
    alter table bike_profiles add constraint bike_profiles_bike_id_key unique (bike_id);
  end if;
end $$;

create index if not exists idx_bike_profiles_tenant on bike_profiles(tenant_id);
create index if not exists idx_bike_profiles_bike_id on bike_profiles(bike_id);
create index if not exists idx_bike_profiles_catalog_bike_id on bike_profiles(catalog_bike_id) where catalog_bike_id is not null;

alter table bike_profiles enable row level security;

drop trigger if exists trg_bike_profiles_updated_at on bike_profiles cascade;
create trigger trg_bike_profiles_updated_at
  before update on bike_profiles
  for each row execute procedure public.set_updated_at();

drop policy if exists "bike_profiles_select" on bike_profiles;
drop policy if exists "bike_profiles_insert" on bike_profiles;
drop policy if exists "bike_profiles_update" on bike_profiles;
drop policy if exists "bike_profiles_delete" on bike_profiles;

create policy "bike_profiles_select" on bike_profiles
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_profiles_insert" on bike_profiles
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "bike_profiles_update" on bike_profiles
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_profiles_delete" on bike_profiles
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());