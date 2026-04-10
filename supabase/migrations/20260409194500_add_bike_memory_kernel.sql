create table if not exists public.bike_system_states (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  bike_id uuid references public.bikes(id) on delete cascade not null,
  job_id uuid references public.mechanic_jobs(id) on delete set null,
  job_bike_id uuid references public.mechanic_job_bikes(id) on delete set null,
  system_key text not null,
  location_key text not null default 'none'
    check (location_key in ('none', 'front', 'rear', 'left', 'right', 'center')),
  overall_status text not null default 'unknown'
    check (overall_status in ('ok', 'attention', 'critical', 'unknown')),
  status_note text,
  last_reviewed_at timestamptz,
  payload jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, bike_id, system_key, location_key)
);

create index if not exists idx_bike_system_states_tenant on public.bike_system_states(tenant_id);
create index if not exists idx_bike_system_states_bike on public.bike_system_states(bike_id);
create index if not exists idx_bike_system_states_job on public.bike_system_states(job_id) where job_id is not null;
create index if not exists idx_bike_system_states_job_bike on public.bike_system_states(job_bike_id) where job_bike_id is not null;
create index if not exists idx_bike_system_states_system on public.bike_system_states(bike_id, system_key, location_key);

alter table public.bike_system_states enable row level security;

drop policy if exists "bike_system_states_select" on public.bike_system_states;
drop policy if exists "bike_system_states_insert" on public.bike_system_states;
drop policy if exists "bike_system_states_update" on public.bike_system_states;
drop policy if exists "bike_system_states_delete" on public.bike_system_states;

create policy "bike_system_states_select" on public.bike_system_states
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_system_states_insert" on public.bike_system_states
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "bike_system_states_update" on public.bike_system_states
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_system_states_delete" on public.bike_system_states
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

drop trigger if exists trg_bike_system_states_updated_at on public.bike_system_states;
create trigger trg_bike_system_states_updated_at
  before update on public.bike_system_states
  for each row execute procedure public.set_updated_at();

create table if not exists public.bike_component_lifecycles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  bike_id uuid references public.bikes(id) on delete cascade not null,
  job_id uuid references public.mechanic_jobs(id) on delete set null,
  job_bike_id uuid references public.mechanic_job_bikes(id) on delete set null,
  mechanic_job_item_id uuid references public.mechanic_job_items(id) on delete set null,
  product_id uuid references public.products(id) on delete set null,
  service_product_id uuid references public.products(id) on delete set null,
  system_key text not null,
  component_slot_key text not null,
  location_key text not null default 'none'
    check (location_key in ('none', 'front', 'rear', 'left', 'right', 'center')),
  component_label text not null,
  status text not null default 'installed'
    check (status in ('installed', 'removed', 'superseded')),
  installed_at timestamptz not null default now(),
  removed_at timestamptz,
  removal_reason text,
  source text not null default 'manual',
  notes text,
  payload jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_bike_component_lifecycles_tenant on public.bike_component_lifecycles(tenant_id);
create index if not exists idx_bike_component_lifecycles_bike on public.bike_component_lifecycles(bike_id);
create index if not exists idx_bike_component_lifecycles_job on public.bike_component_lifecycles(job_id) where job_id is not null;
create index if not exists idx_bike_component_lifecycles_job_bike on public.bike_component_lifecycles(job_bike_id) where job_bike_id is not null;
create index if not exists idx_bike_component_lifecycles_item on public.bike_component_lifecycles(mechanic_job_item_id) where mechanic_job_item_id is not null;
create index if not exists idx_bike_component_lifecycles_product on public.bike_component_lifecycles(product_id) where product_id is not null;
create index if not exists idx_bike_component_lifecycles_service_product on public.bike_component_lifecycles(service_product_id) where service_product_id is not null;
create index if not exists idx_bike_component_lifecycles_slot on public.bike_component_lifecycles(bike_id, component_slot_key, location_key, installed_at desc);
create unique index if not exists idx_bike_component_lifecycles_current_slot
  on public.bike_component_lifecycles(tenant_id, bike_id, component_slot_key, location_key)
  where status = 'installed';

alter table public.bike_component_lifecycles enable row level security;

drop policy if exists "bike_component_lifecycles_select" on public.bike_component_lifecycles;
drop policy if exists "bike_component_lifecycles_insert" on public.bike_component_lifecycles;
drop policy if exists "bike_component_lifecycles_update" on public.bike_component_lifecycles;
drop policy if exists "bike_component_lifecycles_delete" on public.bike_component_lifecycles;

create policy "bike_component_lifecycles_select" on public.bike_component_lifecycles
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_component_lifecycles_insert" on public.bike_component_lifecycles
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "bike_component_lifecycles_update" on public.bike_component_lifecycles
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_component_lifecycles_delete" on public.bike_component_lifecycles
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

drop trigger if exists trg_bike_component_lifecycles_updated_at on public.bike_component_lifecycles;
create trigger trg_bike_component_lifecycles_updated_at
  before update on public.bike_component_lifecycles
  for each row execute procedure public.set_updated_at();

create table if not exists public.bike_observations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  bike_id uuid references public.bikes(id) on delete cascade not null,
  job_id uuid references public.mechanic_jobs(id) on delete set null,
  job_bike_id uuid references public.mechanic_job_bikes(id) on delete set null,
  mechanic_job_item_id uuid references public.mechanic_job_items(id) on delete set null,
  lifecycle_id uuid references public.bike_component_lifecycles(id) on delete set null,
  product_id uuid references public.products(id) on delete set null,
  service_product_id uuid references public.products(id) on delete set null,
  system_key text not null,
  component_slot_key text,
  location_key text not null default 'none'
    check (location_key in ('none', 'front', 'rear', 'left', 'right', 'center')),
  observation_kind text not null
    check (observation_kind in ('measurement', 'condition_assessment', 'diagnosis_snapshot', 'incident', 'confirmation')),
  observation_key text not null,
  title text not null,
  summary text,
  status_value text,
  value_numeric numeric(12,4),
  value_text text,
  unit text,
  severity text check (severity is null or severity in ('info', 'warning', 'critical')),
  observed_at timestamptz not null default now(),
  source text not null default 'manual',
  source_field text,
  payload jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_bike_observations_tenant on public.bike_observations(tenant_id);
create index if not exists idx_bike_observations_bike on public.bike_observations(bike_id, observed_at desc, created_at desc);
create index if not exists idx_bike_observations_job on public.bike_observations(job_id) where job_id is not null;
create index if not exists idx_bike_observations_job_bike on public.bike_observations(job_bike_id) where job_bike_id is not null;
create index if not exists idx_bike_observations_item on public.bike_observations(mechanic_job_item_id) where mechanic_job_item_id is not null;
create index if not exists idx_bike_observations_lifecycle on public.bike_observations(lifecycle_id) where lifecycle_id is not null;
create index if not exists idx_bike_observations_system on public.bike_observations(bike_id, system_key, location_key, observed_at desc);
create index if not exists idx_bike_observations_slot on public.bike_observations(bike_id, component_slot_key, location_key, observed_at desc) where component_slot_key is not null;
create index if not exists idx_bike_observations_key on public.bike_observations(observation_key);

alter table public.bike_observations enable row level security;

drop policy if exists "bike_observations_select" on public.bike_observations;
drop policy if exists "bike_observations_insert" on public.bike_observations;
drop policy if exists "bike_observations_update" on public.bike_observations;
drop policy if exists "bike_observations_delete" on public.bike_observations;

create policy "bike_observations_select" on public.bike_observations
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_observations_insert" on public.bike_observations
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "bike_observations_update" on public.bike_observations
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_observations_delete" on public.bike_observations
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

drop trigger if exists trg_bike_observations_updated_at on public.bike_observations;
create trigger trg_bike_observations_updated_at
  before update on public.bike_observations
  for each row execute procedure public.set_updated_at();

create table if not exists public.bike_interventions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  bike_id uuid references public.bikes(id) on delete cascade not null,
  job_id uuid references public.mechanic_jobs(id) on delete set null,
  job_bike_id uuid references public.mechanic_job_bikes(id) on delete set null,
  mechanic_job_item_id uuid references public.mechanic_job_items(id) on delete set null,
  product_id uuid references public.products(id) on delete set null,
  service_product_id uuid references public.products(id) on delete set null,
  from_lifecycle_id uuid references public.bike_component_lifecycles(id) on delete set null,
  to_lifecycle_id uuid references public.bike_component_lifecycles(id) on delete set null,
  system_key text not null,
  component_slot_key text,
  location_key text not null default 'none'
    check (location_key in ('none', 'front', 'rear', 'left', 'right', 'center')),
  intervention_type text not null
    check (intervention_type in ('replacement', 'service', 'adjustment', 'installation', 'removal', 'inspection')),
  title text not null,
  summary text,
  performed_at timestamptz not null default now(),
  source text not null default 'manual',
  payload jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_bike_interventions_tenant on public.bike_interventions(tenant_id);
create index if not exists idx_bike_interventions_bike on public.bike_interventions(bike_id, performed_at desc, created_at desc);
create index if not exists idx_bike_interventions_job on public.bike_interventions(job_id) where job_id is not null;
create index if not exists idx_bike_interventions_job_bike on public.bike_interventions(job_bike_id) where job_bike_id is not null;
create index if not exists idx_bike_interventions_item on public.bike_interventions(mechanic_job_item_id) where mechanic_job_item_id is not null;
create index if not exists idx_bike_interventions_system on public.bike_interventions(bike_id, system_key, location_key, performed_at desc);
create index if not exists idx_bike_interventions_slot on public.bike_interventions(bike_id, component_slot_key, location_key, performed_at desc) where component_slot_key is not null;
create index if not exists idx_bike_interventions_from_lifecycle on public.bike_interventions(from_lifecycle_id) where from_lifecycle_id is not null;
create index if not exists idx_bike_interventions_to_lifecycle on public.bike_interventions(to_lifecycle_id) where to_lifecycle_id is not null;

alter table public.bike_interventions enable row level security;

drop policy if exists "bike_interventions_select" on public.bike_interventions;
drop policy if exists "bike_interventions_insert" on public.bike_interventions;
drop policy if exists "bike_interventions_update" on public.bike_interventions;
drop policy if exists "bike_interventions_delete" on public.bike_interventions;

create policy "bike_interventions_select" on public.bike_interventions
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_interventions_insert" on public.bike_interventions
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "bike_interventions_update" on public.bike_interventions
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_interventions_delete" on public.bike_interventions
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

drop trigger if exists trg_bike_interventions_updated_at on public.bike_interventions;
create trigger trg_bike_interventions_updated_at
  before update on public.bike_interventions
  for each row execute procedure public.set_updated_at();