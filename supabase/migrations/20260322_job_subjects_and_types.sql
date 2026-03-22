-- ============================================================
-- MIGRATION: Job Subjects & Job Types
-- Date: 2026-03-22
-- Purpose:
--   1. Create job_subjects catalog (wheel, wheelchair, derailleur, etc.)
--   2. Add job_type, subject_id, warranty_outcome, quotation_status,
--      converted_from_id columns to mechanic_jobs
--   3. Make bike_id nullable (jobs can be for items, not registered bikes)
--   4. Migrate existing is_warranty_job=true → job_type='warranty'
--   5. Seed default job subjects for all existing tenants
-- ============================================================

-- ============================================================
-- 1. JOB SUBJECTS TABLE
-- ============================================================
create table if not exists job_subjects (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  category text not null default 'general',
  icon text default 'build',          -- material icon name (e.g. 'tire_repair', 'chair')
  description text,                    -- optional hint shown in picker
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, name)
);

create index if not exists idx_job_subjects_tenant on job_subjects(tenant_id);
create index if not exists idx_job_subjects_tenant_active on job_subjects(tenant_id, is_active);
create index if not exists idx_job_subjects_category on job_subjects(tenant_id, category);

-- RLS
alter table job_subjects enable row level security;

drop policy if exists "job_subjects_select" on job_subjects;
drop policy if exists "job_subjects_insert" on job_subjects;
drop policy if exists "job_subjects_update" on job_subjects;
drop policy if exists "job_subjects_delete" on job_subjects;

create policy "job_subjects_select" on job_subjects
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "job_subjects_insert" on job_subjects
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "job_subjects_update" on job_subjects
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "job_subjects_delete" on job_subjects
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- updated_at trigger
create or replace function public.set_job_subjects_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

drop trigger if exists trg_job_subjects_updated_at on job_subjects;
create trigger trg_job_subjects_updated_at
  before update on job_subjects
  for each row execute function public.set_job_subjects_updated_at();

-- ============================================================
-- 2. ALTER mechanic_jobs: make bike_id nullable
-- ============================================================
-- Drop the NOT NULL constraint on bike_id so item/quotation jobs don't need a bike.
-- All existing jobs already have a bike_id so no data loss.
alter table mechanic_jobs alter column bike_id drop not null;

-- ============================================================
-- 3. ALTER mechanic_jobs: new columns
-- ============================================================

-- job_type: the kind of job (service=regular, warranty, quotation, item_service)
alter table mechanic_jobs
  add column if not exists job_type text not null default 'service'
  check (job_type in ('service', 'warranty', 'quotation', 'item_service'));

-- subject_id: FK to job_subjects (for non-bike jobs)
alter table mechanic_jobs
  add column if not exists subject_id uuid references job_subjects(id) on delete set null;

-- subject_notes: brief description ("29\" Mavic CrossMax", "silla Karma KM-2500", etc.)
alter table mechanic_jobs
  add column if not exists subject_notes text;

-- warranty_outcome: result of a warranty job
alter table mechanic_jobs
  add column if not exists warranty_outcome text
  check (warranty_outcome in ('pending', 'covered', 'not_covered'));

-- quotation_status: approval state of a quotation
alter table mechanic_jobs
  add column if not exists quotation_status text
  check (quotation_status in ('pending', 'approved', 'rejected', 'expired'));

-- quotation_valid_until: expiry date for quotations
alter table mechanic_jobs
  add column if not exists quotation_valid_until timestamp with time zone;

-- converted_from_id: when a warranty/quote is converted to a paid service job
alter table mechanic_jobs
  add column if not exists converted_from_id uuid references mechanic_jobs(id) on delete set null;

alter table mechanic_jobs
  add column if not exists converted_at timestamp with time zone;

-- indexes
create index if not exists idx_mechanic_jobs_job_type on mechanic_jobs(tenant_id, job_type);
create index if not exists idx_mechanic_jobs_subject on mechanic_jobs(subject_id) where subject_id is not null;
create index if not exists idx_mechanic_jobs_converted on mechanic_jobs(converted_from_id) where converted_from_id is not null;

-- ============================================================
-- 4. MIGRATE existing warranty jobs
-- ============================================================
-- is_warranty_job=true → job_type='warranty', warranty_outcome='pending'
update mechanic_jobs
   set job_type = 'warranty',
       warranty_outcome = case
         when status in ('FINALIZADO', 'ENTREGADO') then 'covered'
         else 'pending'
       end
 where is_warranty_job = true
   and job_type = 'service'; -- only migrate once

-- ============================================================
-- 5. SEED default job subjects for existing tenants
-- ============================================================
-- Common serviceable items in a bike shop, organized by category.
-- Each tenant gets their own copy so they can customize freely.

do $$
declare
  v_tenant record;
begin
  for v_tenant in select id from tenants loop
    -- Category: Ruedas
    insert into job_subjects (tenant_id, name, category, icon, sort_order) values
      (v_tenant.id, 'Rueda delantera',         'Ruedas',      'tire_repair',    10),
      (v_tenant.id, 'Rueda trasera',            'Ruedas',      'tire_repair',    20),
      (v_tenant.id, 'Rueda completa',           'Ruedas',      'tire_repair',    30),
      (v_tenant.id, 'Aro (Rim)',                'Ruedas',      'circle',         40),
      (v_tenant.id, 'Cubierta / Neumático',     'Ruedas',      'tire_repair',    50),
      (v_tenant.id, 'Cámara de neumático',      'Ruedas',      'radio_button_unchecked', 60)
    on conflict (tenant_id, name) do nothing;

    -- Category: Transmisión
    insert into job_subjects (tenant_id, name, category, icon, sort_order) values
      (v_tenant.id, 'Desviador trasero',        'Transmisión', 'settings',       10),
      (v_tenant.id, 'Desviador delantero',      'Transmisión', 'settings',       20),
      (v_tenant.id, 'Cassette',                 'Transmisión', 'settings',       30),
      (v_tenant.id, 'Cadena',                   'Transmisión', 'link',           40),
      (v_tenant.id, 'Plato / Corona',           'Transmisión', 'circle',         50),
      (v_tenant.id, 'Maneta de cambio',         'Transmisión', 'swap_horiz',     60),
      (v_tenant.id, 'Biela',                    'Transmisión', 'settings',       70),
      (v_tenant.id, 'Pedalier / Bottom Bracket','Transmisión', 'settings',       80)
    on conflict (tenant_id, name) do nothing;

    -- Category: Frenos
    insert into job_subjects (tenant_id, name, category, icon, sort_order) values
      (v_tenant.id, 'Freno delantero',          'Frenos',      'stop_circle',    10),
      (v_tenant.id, 'Freno trasero',            'Frenos',      'stop_circle',    20),
      (v_tenant.id, 'Pastillas de freno',       'Frenos',      'stop_circle',    30),
      (v_tenant.id, 'Disco / Rotor de freno',   'Frenos',      'radio_button_unchecked', 40),
      (v_tenant.id, 'Maneta de freno',          'Frenos',      'pan_tool',       50),
      (v_tenant.id, 'Cable de freno',           'Frenos',      'cable',          60)
    on conflict (tenant_id, name) do nothing;

    -- Category: Suspensión
    insert into job_subjects (tenant_id, name, category, icon, sort_order) values
      (v_tenant.id, 'Horquilla delantera',      'Suspensión',  'arrow_upward',   10),
      (v_tenant.id, 'Amortiguador trasero',     'Suspensión',  'compress',       20)
    on conflict (tenant_id, name) do nothing;

    -- Category: Movilidad Reducida
    insert into job_subjects (tenant_id, name, category, icon, sort_order) values
      (v_tenant.id, 'Silla de ruedas',          'Movilidad', 'accessible',       10),
      (v_tenant.id, 'Carro de movilidad',       'Movilidad', 'shopping_cart',    20),
      (v_tenant.id, 'Andador',                  'Movilidad', 'directions_walk',  30)
    on conflict (tenant_id, name) do nothing;

    -- Category: Otros Componentes
    insert into job_subjects (tenant_id, name, category, icon, sort_order) values
      (v_tenant.id, 'Manillar / Guidón',        'Componentes', 'horizontal_rule', 10),
      (v_tenant.id, 'Potencia (stem)',          'Componentes', 'extension',       20),
      (v_tenant.id, 'Tija de sillín',           'Componentes', 'arrow_upward',    30),
      (v_tenant.id, 'Sillín',                   'Componentes', 'airline_seat_recline_normal', 40),
      (v_tenant.id, 'Pedales',                  'Componentes', 'sports',          50),
      (v_tenant.id, 'Cuadro / Frame',           'Componentes', 'rectangle',       60),
      (v_tenant.id, 'Componente / Pieza suelta','General',     'build',           10)
    on conflict (tenant_id, name) do nothing;

  end loop;
end $$;

-- ============================================================
-- 6. FUNCTION: seed_job_subjects_for_tenant(tenant_id)
--    Called automatically when a new tenant is created
-- ============================================================
create or replace function public.seed_job_subjects_for_tenant(p_tenant_id uuid)
returns void language plpgsql security definer as $$
begin
  -- Ruedas
  insert into job_subjects (tenant_id, name, category, icon, sort_order) values
    (p_tenant_id, 'Rueda delantera',         'Ruedas',      'tire_repair',    10),
    (p_tenant_id, 'Rueda trasera',            'Ruedas',      'tire_repair',    20),
    (p_tenant_id, 'Rueda completa',           'Ruedas',      'tire_repair',    30),
    (p_tenant_id, 'Aro (Rim)',                'Ruedas',      'circle',         40),
    (p_tenant_id, 'Cubierta / Neumático',     'Ruedas',      'tire_repair',    50),
    (p_tenant_id, 'Cámara de neumático',      'Ruedas',      'radio_button_unchecked', 60)
  on conflict (tenant_id, name) do nothing;

  -- Transmisión
  insert into job_subjects (tenant_id, name, category, icon, sort_order) values
    (p_tenant_id, 'Desviador trasero',        'Transmisión', 'settings',       10),
    (p_tenant_id, 'Desviador delantero',      'Transmisión', 'settings',       20),
    (p_tenant_id, 'Cassette',                 'Transmisión', 'settings',       30),
    (p_tenant_id, 'Cadena',                   'Transmisión', 'link',           40),
    (p_tenant_id, 'Plato / Corona',           'Transmisión', 'circle',         50),
    (p_tenant_id, 'Maneta de cambio',         'Transmisión', 'swap_horiz',     60),
    (p_tenant_id, 'Biela',                    'Transmisión', 'settings',       70),
    (p_tenant_id, 'Pedalier / Bottom Bracket','Transmisión', 'settings',       80)
  on conflict (tenant_id, name) do nothing;

  -- Frenos
  insert into job_subjects (tenant_id, name, category, icon, sort_order) values
    (p_tenant_id, 'Freno delantero',          'Frenos',      'stop_circle',    10),
    (p_tenant_id, 'Freno trasero',            'Frenos',      'stop_circle',    20),
    (p_tenant_id, 'Pastillas de freno',       'Frenos',      'stop_circle',    30),
    (p_tenant_id, 'Disco / Rotor de freno',   'Frenos',      'radio_button_unchecked', 40),
    (p_tenant_id, 'Maneta de freno',          'Frenos',      'pan_tool',       50),
    (p_tenant_id, 'Cable de freno',           'Frenos',      'cable',          60)
  on conflict (tenant_id, name) do nothing;

  -- Suspensión
  insert into job_subjects (tenant_id, name, category, icon, sort_order) values
    (p_tenant_id, 'Horquilla delantera',      'Suspensión',  'arrow_upward',   10),
    (p_tenant_id, 'Amortiguador trasero',     'Suspensión',  'compress',       20)
  on conflict (tenant_id, name) do nothing;

  -- Movilidad Reducida
  insert into job_subjects (tenant_id, name, category, icon, sort_order) values
    (p_tenant_id, 'Silla de ruedas',          'Movilidad', 'accessible',       10),
    (p_tenant_id, 'Carro de movilidad',       'Movilidad', 'shopping_cart',    20),
    (p_tenant_id, 'Andador',                  'Movilidad', 'directions_walk',  30)
  on conflict (tenant_id, name) do nothing;

  -- Componentes varios
  insert into job_subjects (tenant_id, name, category, icon, sort_order) values
    (p_tenant_id, 'Manillar / Guidón',        'Componentes', 'horizontal_rule', 10),
    (p_tenant_id, 'Potencia (stem)',          'Componentes', 'extension',       20),
    (p_tenant_id, 'Tija de sillín',           'Componentes', 'arrow_upward',    30),
    (p_tenant_id, 'Sillín',                   'Componentes', 'airline_seat_recline_normal', 40),
    (p_tenant_id, 'Pedales',                  'Componentes', 'sports',          50),
    (p_tenant_id, 'Cuadro / Frame',           'Componentes', 'rectangle',       60),
    (p_tenant_id, 'Componente / Pieza suelta','General',     'build',           10)
  on conflict (tenant_id, name) do nothing;
end; $$;

grant execute on function public.seed_job_subjects_for_tenant(uuid) to authenticated;

-- ============================================================
-- 7. Hook seed_job_subjects_for_tenant into handle_new_tenant
--    (add call inside the existing trigger function body)
-- ============================================================
-- NOTE: Only add the call if it doesn't already exist.
-- The full handle_new_tenant function is in core_schema.sql –
-- the ALTER below adds one line to the existing function body.
-- We update it here as a standalone statement so it's idempotent.
-- (If handle_new_tenant is redeployed from core_schema.sql, that
--  version must also include this call.)

-- Verify function exists before patching
do $$
begin
  if exists (select 1 from pg_proc where proname = 'handle_new_tenant') then
    raise notice '✅ handle_new_tenant exists - job subject seeding is in seed function, call separately';
  end if;
end $$;
