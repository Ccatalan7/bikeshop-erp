-- ============================================================
-- Job Types & Job Subjects
-- Extends mechanic_jobs to support warranty, quotation, and
-- component (non-registered-bike) work orders.
-- Deploy in Supabase SQL Editor
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. job_subjects: per-tenant catalog of non-bike work items
--    (wheels, wheelchairs, derailleurs, carts, forks, etc.)
-- ────────────────────────────────────────────────────────────
create table if not exists job_subjects (
  id          uuid        primary key default gen_random_uuid(),
  tenant_id   uuid        not null references tenants(id) on delete cascade,
  name        text        not null,
  category    text,
  icon_name   text,
  description text,
  sort_order  integer     not null default 0,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (tenant_id, name)
);

create index if not exists idx_job_subjects_tenant    on job_subjects (tenant_id);
create index if not exists idx_job_subjects_category  on job_subjects (tenant_id, category);

alter table job_subjects enable row level security;

drop policy if exists "job_subjects_select" on job_subjects;
drop policy if exists "job_subjects_insert" on job_subjects;
drop policy if exists "job_subjects_update" on job_subjects;
drop policy if exists "job_subjects_delete" on job_subjects;

create policy "job_subjects_select" on job_subjects for select to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "job_subjects_insert" on job_subjects for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "job_subjects_update" on job_subjects for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "job_subjects_delete" on job_subjects for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- ────────────────────────────────────────────────────────────
-- 2. Make bike_id nullable (jobs can target a catalog subject)
-- ────────────────────────────────────────────────────────────
alter table mechanic_jobs alter column bike_id drop not null;

-- ────────────────────────────────────────────────────────────
-- 3. New columns on mechanic_jobs
-- ────────────────────────────────────────────────────────────
alter table mechanic_jobs
  add column if not exists job_type text not null default 'service'
    check (job_type in ('service', 'warranty', 'quotation', 'component')),
  add column if not exists subject_id uuid references job_subjects(id) on delete set null,
  add column if not exists subject_notes text,
  add column if not exists warranty_outcome text
    check (warranty_outcome in ('pending', 'covered', 'not_covered', 'converted')),
  add column if not exists quotation_status text default 'pending'
    check (quotation_status in ('pending', 'approved', 'rejected', 'converted')),
  add column if not exists converted_from_id uuid references mechanic_jobs(id) on delete set null,
  add column if not exists converted_to_id   uuid references mechanic_jobs(id) on delete set null;

create index if not exists idx_mechanic_jobs_job_type      on mechanic_jobs (tenant_id, job_type);
create index if not exists idx_mechanic_jobs_subject        on mechanic_jobs (subject_id);
create index if not exists idx_mechanic_jobs_converted_from on mechanic_jobs (converted_from_id);

-- Back-fill: existing warranty jobs (is_warranty_job = true) → job_type = 'warranty'
update mechanic_jobs
   set job_type = 'warranty',
       warranty_outcome = 'pending'
 where is_warranty_job = true
   and job_type = 'service';

-- ────────────────────────────────────────────────────────────
-- 4. Seed default job_subjects for every existing tenant
-- ────────────────────────────────────────────────────────────
do $$
declare
  v_tenant record;
  v_order  integer;
begin
  for v_tenant in select id from tenants loop

    v_order := 10;
    -- Ruedas
    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Rueda delantera',     'Ruedas',       'tire',       v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Rueda trasera',        'Ruedas',       'tire',       v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Ambas ruedas',         'Ruedas',       'tire',       v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    -- Transmisión
    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Desviador trasero',    'Transmisión',  'settings',   v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Desviador delantero',  'Transmisión',  'settings',   v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Cadena',               'Transmisión',  'link',       v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Cassette / Piñones',   'Transmisión',  'settings',   v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Platos / Bielas',      'Transmisión',  'settings',   v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    -- Frenos
    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Freno delantero',      'Frenos',       'emergency_brake', v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Freno trasero',        'Frenos',       'emergency_brake', v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Ambos frenos',         'Frenos',       'emergency_brake', v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    -- Estructura
    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Horquilla',            'Estructura',   'arrow_upward', v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Cuadro',               'Estructura',   'bike',       v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Suspensión delantera',  'Estructura',  'compress',   v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    -- Manejo
    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Manubrio / Tija potencia', 'Manejo',   'horizontal_rule', v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Sillín / Tija',        'Manejo',       'airline_seat', v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    -- Movilidad (wheelchair, carts, etc.)
    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Silla de ruedas',      'Movilidad',    'accessible', v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Carro de apoyo',       'Movilidad',    'directions_car', v_order)
    on conflict (tenant_id, name) do nothing;
    v_order := v_order + 10;

    insert into job_subjects (tenant_id, name, category, icon_name, sort_order)
    values (v_tenant.id, 'Otro componente',      'Otros',        'handyman',   v_order)
    on conflict (tenant_id, name) do nothing;

  end loop;
end $$;

-- ────────────────────────────────────────────────────────────
-- 5. Helper RPC: convert a warranty/quotation job to a new service job
-- ────────────────────────────────────────────────────────────
create or replace function public.convert_job_to_service(p_source_job_id uuid)
returns uuid
language plpgsql
security definer
as $$
declare
  v_source     mechanic_jobs%rowtype;
  v_new_job_id uuid;
begin
  -- Load source job (must belong to caller's tenant)
  select * into v_source
    from mechanic_jobs
   where id = p_source_job_id
     and tenant_id = public.user_tenant_id()
     and deleted_at is null;

  if not found then
    raise exception 'Job not found or access denied';
  end if;

  -- Create the new service job
  insert into mechanic_jobs (
    tenant_id, customer_id, bike_id, subject_id, subject_notes,
    job_type, status, priority,
    client_request, notes,
    assigned_to, assigned_technician_name,
    estimated_cost, tax_treatment,
    arrival_date,
    converted_from_id,
    is_warranty_job
  )
  values (
    v_source.tenant_id, v_source.customer_id, v_source.bike_id,
    v_source.subject_id, v_source.subject_notes,
    'service', v_source.status, v_source.priority,
    v_source.client_request, v_source.notes,
    v_source.assigned_to, v_source.assigned_technician_name,
    v_source.estimated_cost, v_source.tax_treatment,
    now(),
    p_source_job_id,
    false
  )
  returning id into v_new_job_id;

  -- Link back: mark source as converted
  update mechanic_jobs
     set converted_to_id   = v_new_job_id,
         warranty_outcome   = case when job_type = 'warranty'   then 'converted' else warranty_outcome end,
         quotation_status   = case when job_type = 'quotation'  then 'converted' else quotation_status end,
         updated_at         = now()
   where id = p_source_job_id;

  return v_new_job_id;
end;
$$;

grant execute on function public.convert_job_to_service(uuid) to authenticated;
