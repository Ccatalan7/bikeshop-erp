-- ============================================================================
-- DEPLOY: Notion-style Custom Job Statuses
-- ============================================================================
-- This migration adds customizable job statuses for mechanic jobs (pegas).
-- Users can create, edit, delete, reorder statuses with custom names and colors.
-- 
-- Run this in Supabase SQL Editor to deploy the changes.
-- ============================================================================

-- STEP 1: Create job_statuses table
-- ============================================================================
create table if not exists job_statuses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  code text not null, -- Internal code for backwards compatibility (e.g., 'PENDIENTE')
  color text not null default '#6B7280', -- Hex color (gray default)
  phase text not null default 'in_progress'
    check (phase in ('todo', 'in_progress', 'complete')),
  sort_order integer not null default 0,
  is_system boolean not null default false, -- System statuses can't be deleted
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, code), -- Each tenant has unique codes
  unique(tenant_id, id) -- Enable composite FK references (multi-tenant isolation)
);

-- STEP 2: Create indexes for performance
-- ============================================================================
do $$ begin
  create index if not exists idx_job_statuses_tenant on job_statuses(tenant_id);
  create index if not exists idx_job_statuses_code on job_statuses(tenant_id, code);
  create index if not exists idx_job_statuses_phase on job_statuses(tenant_id, phase);
  create index if not exists idx_job_statuses_sort on job_statuses(tenant_id, sort_order);
exception
  when undefined_table then raise notice '⚠ Table job_statuses does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id does not exist in job_statuses';
end $$;

-- STEP 3: Enable RLS and create policies
-- ============================================================================
alter table job_statuses enable row level security;

drop policy if exists "job_statuses_select" on job_statuses;
drop policy if exists "job_statuses_insert" on job_statuses;
drop policy if exists "job_statuses_update" on job_statuses;
drop policy if exists "job_statuses_delete" on job_statuses;

create policy "job_statuses_select" on job_statuses
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "job_statuses_insert" on job_statuses
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "job_statuses_update" on job_statuses
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "job_statuses_delete" on job_statuses
  for delete to authenticated
  using (tenant_id = public.user_tenant_id() and is_system = false); -- Can't delete system statuses

-- STEP 4: Add status_id column to mechanic_jobs
-- ============================================================================
alter table mechanic_jobs add column if not exists status_id uuid;

-- Add foreign key constraint
do $$ begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'mechanic_jobs_status_id_fkey'
  ) then
    alter table mechanic_jobs add constraint mechanic_jobs_status_id_fkey
      foreign key (tenant_id, status_id) references job_statuses(tenant_id, id) on delete set null;
    raise notice '✅ Added mechanic_jobs.status_id foreign key';
  end if;
exception
  when others then raise notice '⚠️ mechanic_jobs.status_id FK: %', sqlerrm;
end $$;

create index if not exists idx_mechanic_jobs_status_id on mechanic_jobs(status_id);

-- STEP 5: Create seed function for job statuses
-- ============================================================================
drop function if exists public.seed_job_statuses_for_tenant(uuid);

create or replace function public.seed_job_statuses_for_tenant(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int := 0;
begin
  -- Phase: TODO (not started yet)
  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'PENDIENTE') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'PENDIENTE', 'Pendiente', '#6B7280', 'todo', 1, true);
    v_count := v_count + 1;
  end if;

  -- Phase: IN_PROGRESS (active work)
  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'DIAGNOSTICO') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'DIAGNOSTICO', 'Diagnóstico', '#3B82F6', 'in_progress', 2, true);
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'ESPERANDO_APROBACION') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'ESPERANDO_APROBACION', 'Esperando Aprobación', '#F59E0B', 'in_progress', 3, true);
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'ESPERANDO_REPUESTOS') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'ESPERANDO_REPUESTOS', 'Esperando Repuestos', '#F97316', 'in_progress', 4, true);
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'EN_CURSO') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'EN_CURSO', 'En Curso', '#8B5CF6', 'in_progress', 5, true);
    v_count := v_count + 1;
  end if;

  -- Phase: COMPLETE (finished)
  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'FINALIZADO') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'FINALIZADO', 'Finalizado', '#10B981', 'complete', 6, true);
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'ENTREGADO') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'ENTREGADO', 'Entregado', '#06B6D4', 'complete', 7, true);
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from job_statuses where tenant_id = p_tenant_id and code = 'CANCELADO') then
    insert into job_statuses (tenant_id, code, name, color, phase, sort_order, is_system)
    values (p_tenant_id, 'CANCELADO', 'Cancelado', '#EF4444', 'complete', 8, true);
    v_count := v_count + 1;
  end if;

  raise notice '✓ Created % job statuses for tenant %', v_count, p_tenant_id;
  return format('✓ Created %s job statuses for tenant %s', v_count, p_tenant_id);
end;
$$;

-- STEP 6: Create migration function for existing jobs
-- ============================================================================
drop function if exists public.migrate_job_statuses();

create or replace function public.migrate_job_statuses()
returns text
language plpgsql
security definer
as $$
declare
  v_count int := 0;
  v_job record;
  v_status_id uuid;
begin
  -- First, seed job statuses for all existing tenants that don't have them
  for v_job in (select distinct tenant_id from mechanic_jobs) loop
    perform public.seed_job_statuses_for_tenant(v_job.tenant_id);
  end loop;

  -- Now update all mechanic_jobs to set status_id based on status text
  for v_job in (
    select id, tenant_id, status from mechanic_jobs where status_id is null
  ) loop
    select id into v_status_id
    from job_statuses
    where tenant_id = v_job.tenant_id
      and code = v_job.status
    limit 1;

    if v_status_id is not null then
      update mechanic_jobs set status_id = v_status_id where id = v_job.id;
      v_count := v_count + 1;
    end if;
  end loop;

  return format('✓ Migrated %s jobs to use status_id', v_count);
end;
$$;

-- STEP 7: Update handle_new_tenant to seed job statuses for new tenants
-- ============================================================================
create or replace function public.handle_new_tenant()
returns trigger
language plpgsql
security definer
as $$
begin
  raise notice '🏗️ Initializing new tenant: % (ID: %)', NEW.shop_name, NEW.id;
  
  -- Seed chart of accounts (CRITICAL - must come first, needed by payment methods)
  perform public.seed_chart_of_accounts(NEW.id);
  raise notice '  ✓ Chart of accounts created';
  
  -- Seed payment methods (uses accounts created above)
  perform public.seed_payment_methods_for_tenant(NEW.id);
  raise notice '  ✓ Payment methods configured';
  
  -- Seed job statuses (Notion-style custom statuses for pegas)
  perform public.seed_job_statuses_for_tenant(NEW.id);
  raise notice '  ✓ Job statuses configured';
  
  -- Seed company settings
  perform public.seed_company_settings(NEW.id);
  raise notice '  ✓ Company settings initialized';
  
  -- Seed website settings
  perform public.seed_website_settings(NEW.id);
  raise notice '  ✓ Website settings initialized';
  
  -- Seed job roles (employee-user linking system)
  perform public.seed_job_roles_for_tenant(NEW.id);
  raise notice '  ✓ Job roles catalog created';
  
  raise notice '✅ Tenant % fully initialized and ready for use!', NEW.shop_name;
  return NEW;
end;
$$;

-- STEP 8: Run migration for existing tenants
-- ============================================================================
-- This will seed statuses for all existing tenants and link existing jobs
select public.migrate_job_statuses();

-- STEP 9: Seed for any remaining tenants without job statuses
-- ============================================================================
do $$
declare
  tenant_rec record;
begin
  for tenant_rec in 
    select id, shop_name from tenants 
    where id not in (select distinct tenant_id from job_statuses)
  loop
    perform public.seed_job_statuses_for_tenant(tenant_rec.id);
    raise notice '✓ Seeded job statuses for tenant: %', tenant_rec.shop_name;
  end loop;
end $$;

-- ============================================================================
-- DEPLOYMENT COMPLETE
-- ============================================================================
-- After running this SQL:
-- 1. Deploy the Flutter app: flutter build web --release && firebase deploy
-- 2. Users will see "Estados personalizados" in the Taller menu
-- 3. Existing jobs will automatically show their current status in the new UI
-- 4. Users can add custom statuses, change colors, reorder, etc.
-- ============================================================================
