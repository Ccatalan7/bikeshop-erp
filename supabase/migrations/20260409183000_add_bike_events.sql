create table if not exists public.bike_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  bike_id uuid references public.bikes(id) on delete cascade not null,
  job_id uuid references public.mechanic_jobs(id) on delete set null,
  event_type text not null,
  event_category text not null,
  event_date timestamptz not null default now(),
  title text not null,
  summary text,
  source text not null default 'manual',
  reference_number text,
  severity text,
  payload jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'tenant_id') then
    alter table public.bike_events add column tenant_id uuid references public.tenants(id) on delete cascade not null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'bike_id') then
    alter table public.bike_events add column bike_id uuid references public.bikes(id) on delete cascade not null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'job_id') then
    alter table public.bike_events add column job_id uuid references public.mechanic_jobs(id) on delete set null;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'event_type') then
    alter table public.bike_events add column event_type text not null default 'profile_updated';
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'event_category') then
    alter table public.bike_events add column event_category text not null default 'state';
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'event_date') then
    alter table public.bike_events add column event_date timestamptz not null default now();
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'title') then
    alter table public.bike_events add column title text not null default 'Evento';
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'summary') then
    alter table public.bike_events add column summary text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'source') then
    alter table public.bike_events add column source text not null default 'manual';
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'reference_number') then
    alter table public.bike_events add column reference_number text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'severity') then
    alter table public.bike_events add column severity text;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'payload') then
    alter table public.bike_events add column payload jsonb not null default '{}'::jsonb;
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'created_by') then
    alter table public.bike_events add column created_by uuid references auth.users(id) default auth.uid();
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'created_at') then
    alter table public.bike_events add column created_at timestamptz not null default now();
  end if;
  if not exists (select 1 from information_schema.columns where table_name = 'bike_events' and column_name = 'updated_at') then
    alter table public.bike_events add column updated_at timestamptz not null default now();
  end if;

  if not exists (
    select 1 from information_schema.table_constraints
    where table_name = 'bike_events'
      and constraint_name = 'bike_events_event_category_check'
  ) then
    alter table public.bike_events add constraint bike_events_event_category_check
      check (event_category in ('state', 'visit', 'evidence', 'incident', 'component'));
  end if;

  if not exists (
    select 1 from information_schema.table_constraints
    where table_name = 'bike_events'
      and constraint_name = 'bike_events_severity_check'
  ) then
    alter table public.bike_events add constraint bike_events_severity_check
      check (severity is null or severity in ('info', 'warning', 'critical'));
  end if;
end $$;

create index if not exists idx_bike_events_tenant on public.bike_events(tenant_id);
create index if not exists idx_bike_events_bike_id on public.bike_events(bike_id);
create index if not exists idx_bike_events_bike_date_desc on public.bike_events(bike_id, event_date desc, created_at desc);
create index if not exists idx_bike_events_job_id on public.bike_events(job_id) where job_id is not null;
create index if not exists idx_bike_events_event_type on public.bike_events(event_type);

alter table public.bike_events enable row level security;

drop policy if exists "bike_events_select" on public.bike_events;
drop policy if exists "bike_events_insert" on public.bike_events;
drop policy if exists "bike_events_update" on public.bike_events;
drop policy if exists "bike_events_delete" on public.bike_events;

create policy "bike_events_select" on public.bike_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_events_insert" on public.bike_events
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "bike_events_update" on public.bike_events
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_events_delete" on public.bike_events
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

drop trigger if exists trg_bike_events_updated_at on public.bike_events;
create trigger trg_bike_events_updated_at
  before update on public.bike_events
  for each row execute procedure public.set_updated_at();