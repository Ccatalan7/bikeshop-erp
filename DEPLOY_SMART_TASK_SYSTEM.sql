-- ============================================================
-- SMART TASK SYSTEM FOR MECHANIC JOBS (PEGAS)
-- Deploy this SQL to Supabase SQL Editor
-- ============================================================
-- Location in core_schema.sql: Lines 9427-9726
-- This system provides a dynamic to-do list for mechanics
-- linked to pega statuses (not invoice statuses)
-- ============================================================

-- Table: mechanic_job_tasks
-- Individual tasks linked to mechanic job items and labor
create table if not exists mechanic_job_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  job_id uuid not null references mechanic_jobs(id) on delete cascade,
  
  -- Link to specific item or labor (optional - can be general task too)
  job_item_id uuid references mechanic_job_items(id) on delete cascade,
  job_labor_id uuid references mechanic_job_labor(id) on delete cascade,
  
  -- Task details
  task_type text not null check (task_type in (
    'diagnostic',        -- Diagnose issue
    'install_part',      -- Install a specific part
    'perform_service',   -- Perform service work
    'quality_check',     -- Quality control check
    'test_ride',         -- Test bike after repair
    'cleanup',           -- Clean/polish bike
    'general'            -- General task
  )),
  title text not null,
  description text,
  
  -- Task status
  status text not null default 'pending' check (status in (
    'pending',           -- Not started
    'in_progress',       -- Currently working on it
    'completed',         -- Task finished
    'skipped',           -- Skipped (not needed)
    'blocked'            -- Waiting for something (parts, approval)
  )),
  
  -- Priority and assignment
  priority text not null default 'normal' check (priority in ('urgent', 'high', 'normal', 'low')),
  assigned_to uuid references customers(id) on delete set null, -- Will be employee_id when HR exists
  assigned_technician_name text,
  
  -- Timing
  estimated_duration_minutes integer, -- Estimated time to complete
  actual_duration_minutes integer,    -- Actual time taken
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  
  -- Tracking
  is_auto_generated boolean not null default false, -- True if auto-created from item/labor
  completed_by uuid references customers(id) on delete set null, -- Will be user_id
  completed_by_name text,
  notes text,
  
  -- Display order (for custom sorting)
  display_order integer not null default 0,
  
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Indexes for mechanic_job_tasks
create index if not exists idx_mechanic_job_tasks_tenant on mechanic_job_tasks(tenant_id);
create index if not exists idx_mechanic_job_tasks_job on mechanic_job_tasks(job_id);
create index if not exists idx_mechanic_job_tasks_item on mechanic_job_tasks(job_item_id) where job_item_id is not null;
create index if not exists idx_mechanic_job_tasks_labor on mechanic_job_tasks(job_labor_id) where job_labor_id is not null;
create index if not exists idx_mechanic_job_tasks_status on mechanic_job_tasks(job_id, status);
create index if not exists idx_mechanic_job_tasks_assigned on mechanic_job_tasks(assigned_to) where assigned_to is not null;
create index if not exists idx_mechanic_job_tasks_order on mechanic_job_tasks(job_id, display_order);

-- RLS policies for mechanic_job_tasks
alter table mechanic_job_tasks enable row level security;

drop policy if exists "mechanic_job_tasks_select" on mechanic_job_tasks;
drop policy if exists "mechanic_job_tasks_insert" on mechanic_job_tasks;
drop policy if exists "mechanic_job_tasks_update" on mechanic_job_tasks;
drop policy if exists "mechanic_job_tasks_delete" on mechanic_job_tasks;

create policy "mechanic_job_tasks_select" on mechanic_job_tasks
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "mechanic_job_tasks_insert" on mechanic_job_tasks
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "mechanic_job_tasks_update" on mechanic_job_tasks
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "mechanic_job_tasks_delete" on mechanic_job_tasks
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- ============================================================
-- AUTO-GENERATE TASKS WHEN ITEMS/LABOR ARE ADDED
-- ============================================================

-- Function: Auto-create task when mechanic_job_items is inserted
create or replace function public.auto_create_task_for_job_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_status text;
begin
  -- Get current job status
  select status into v_job_status
  from mechanic_jobs
  where id = NEW.job_id and tenant_id = NEW.tenant_id;
  
  -- Only auto-create tasks for jobs that are not completed/delivered
  if v_job_status not in ('FINALIZADO', 'ENTREGADO', 'CANCELADO') then
    -- Create task for installing this part
    insert into mechanic_job_tasks (
      tenant_id,
      job_id,
      job_item_id,
      task_type,
      title,
      description,
      status,
      priority,
      is_auto_generated,
      display_order
    ) values (
      NEW.tenant_id,
      NEW.job_id,
      NEW.id,
      'install_part',
      'Instalar: ' || NEW.product_name,
      case 
        when NEW.notes is not null and NEW.notes != '' 
        then 'Instalar ' || NEW.product_name || ' (' || NEW.quantity || ' unidad(es)). ' || NEW.notes
        else 'Instalar ' || NEW.product_name || ' (' || NEW.quantity || ' unidad(es))'
      end,
      'pending',
      'normal',
      true,
      (select coalesce(max(display_order), 0) + 1 from mechanic_job_tasks where job_id = NEW.job_id)
    );
  end if;
  
  return NEW;
end;
$$;

-- Trigger: Auto-create task when item is added
drop trigger if exists trg_auto_create_task_for_item on mechanic_job_items;
create trigger trg_auto_create_task_for_item
  after insert on mechanic_job_items
  for each row
  execute function public.auto_create_task_for_job_item();

-- Function: Auto-create task when mechanic_job_labor is inserted
create or replace function public.auto_create_task_for_job_labor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_status text;
begin
  -- Get current job status
  select status into v_job_status
  from mechanic_jobs
  where id = NEW.job_id and tenant_id = NEW.tenant_id;
  
  -- Only auto-create tasks for jobs that are not completed/delivered
  if v_job_status not in ('FINALIZADO', 'ENTREGADO', 'CANCELADO') then
    -- Create task for performing this service
    insert into mechanic_job_tasks (
      tenant_id,
      job_id,
      job_labor_id,
      task_type,
      title,
      description,
      status,
      priority,
      assigned_to,
      assigned_technician_name,
      estimated_duration_minutes,
      is_auto_generated,
      display_order
    ) values (
      NEW.tenant_id,
      NEW.job_id,
      NEW.id,
      'perform_service',
      coalesce(NEW.description, 'Realizar servicio'),
      case 
        when NEW.description is not null and NEW.description != '' 
        then NEW.description || ' (' || NEW.hours_worked || ' horas estimadas)'
        else 'Realizar servicio (' || NEW.hours_worked || ' horas estimadas)'
      end,
      'pending',
      'normal',
      NEW.technician_id,
      NEW.technician_name,
      (NEW.hours_worked * 60)::integer, -- Convert hours to minutes
      true,
      (select coalesce(max(display_order), 0) + 1 from mechanic_job_tasks where job_id = NEW.job_id)
    );
  end if;
  
  return NEW;
end;
$$;

-- Trigger: Auto-create task when labor is added
drop trigger if exists trg_auto_create_task_for_labor on mechanic_job_labor;
create trigger trg_auto_create_task_for_labor
  after insert on mechanic_job_labor
  for each row
  execute function public.auto_create_task_for_job_labor();

-- ============================================================
-- SYNC TASK STATUS WITH PEGA STATUS
-- ============================================================

-- Function: Update task statuses when pega status changes
create or replace function public.sync_tasks_with_job_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- When job is completed, mark all pending tasks as completed
  if NEW.status = 'FINALIZADO' and OLD.status != 'FINALIZADO' then
    update mechanic_job_tasks
    set status = 'completed',
        completed_at = now(),
        updated_at = now()
    where job_id = NEW.id 
      and status in ('pending', 'in_progress');
  end if;
  
  -- When job is cancelled, mark all tasks as skipped
  if NEW.status = 'CANCELADO' and OLD.status != 'CANCELADO' then
    update mechanic_job_tasks
    set status = 'skipped',
        updated_at = now()
    where job_id = NEW.id 
      and status in ('pending', 'in_progress', 'blocked');
  end if;
  
  -- When job moves to EN_CURSO, mark first pending task as in_progress (if none in progress)
  if NEW.status = 'EN_CURSO' and OLD.status != 'EN_CURSO' then
    -- Check if there's already a task in progress
    if not exists (
      select 1 from mechanic_job_tasks 
      where job_id = NEW.id and status = 'in_progress'
    ) then
      -- Mark first pending task as in_progress
      update mechanic_job_tasks
      set status = 'in_progress',
          started_at = now(),
          updated_at = now()
      where id = (
        select id from mechanic_job_tasks
        where job_id = NEW.id and status = 'pending'
        order by display_order, created_at
        limit 1
      );
    end if;
  end if;
  
  return NEW;
end;
$$;

-- Trigger: Sync tasks when job status changes
drop trigger if exists trg_sync_tasks_with_job_status on mechanic_jobs;
create trigger trg_sync_tasks_with_job_status
  after update of status on mechanic_jobs
  for each row
  when (OLD.status is distinct from NEW.status)
  execute function public.sync_tasks_with_job_status();

-- ============================================================
-- HELPER FUNCTION: GET TASK SUMMARY FOR A JOB
-- ============================================================

-- Function: Get task completion statistics for a job
create or replace function public.get_job_task_summary(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total integer;
  v_completed integer;
  v_in_progress integer;
  v_pending integer;
  v_blocked integer;
  v_completion_percentage numeric;
begin
  select
    count(*) as total,
    count(*) filter (where status = 'completed') as completed,
    count(*) filter (where status = 'in_progress') as in_progress,
    count(*) filter (where status = 'pending') as pending,
    count(*) filter (where status = 'blocked') as blocked
  into v_total, v_completed, v_in_progress, v_pending, v_blocked
  from mechanic_job_tasks
  where job_id = p_job_id;
  
  -- Calculate completion percentage
  if v_total > 0 then
    v_completion_percentage := (v_completed::numeric / v_total::numeric * 100)::numeric(5,2);
  else
    v_completion_percentage := 0;
  end if;
  
  return jsonb_build_object(
    'total_tasks', v_total,
    'completed', v_completed,
    'in_progress', v_in_progress,
    'pending', v_pending,
    'blocked', v_blocked,
    'completion_percentage', v_completion_percentage
  );
end;
$$;

grant execute on function public.get_job_task_summary(uuid) to authenticated;

-- ============================================================
-- DEPLOYMENT COMPLETE
-- ============================================================
-- What this system does:
-- 
-- 1. Auto-creates tasks when parts/services are added to a pega
-- 2. Links tasks to specific mechanic_job_items or mechanic_job_labor
-- 3. Syncs task status with pega status:
--    - FINALIZADO → all tasks marked completed
--    - CANCELADO → all tasks marked skipped
--    - EN_CURSO → first pending task marked in_progress
-- 4. Provides task summary function for progress tracking
-- 5. Supports manual task creation (is_auto_generated = false)
-- 6. Full multi-tenant isolation with RLS
--
-- Usage in Flutter:
-- - Query tasks: SELECT * FROM mechanic_job_tasks WHERE job_id = ?
-- - Get summary: SELECT get_job_task_summary(job_id)
-- - Update task: UPDATE mechanic_job_tasks SET status = 'completed' WHERE id = ?
-- ============================================================
