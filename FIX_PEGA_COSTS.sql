-- ============================================================
-- FIX: MECHANIC JOB COST CALCULATION
-- This creates triggers to auto-update parts_cost, labor_cost,
-- and total_cost in mechanic_jobs when items/labor change
-- ============================================================

-- Function: Recalculate mechanic job costs
create or replace function public.update_mechanic_job_costs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parts_cost numeric;
  v_labor_cost numeric;
  v_total_cost numeric;
begin
  -- Calculate parts cost
  select coalesce(sum(total_price), 0)
  into v_parts_cost
  from mechanic_job_items
  where job_id = coalesce(NEW.job_id, OLD.job_id);
  
  -- Calculate labor cost
  select coalesce(sum(total_cost), 0)
  into v_labor_cost
  from mechanic_job_labor
  where job_id = coalesce(NEW.job_id, OLD.job_id);
  
  -- Calculate total
  v_total_cost := v_parts_cost + v_labor_cost;
  
  -- Update mechanic_jobs table
  update mechanic_jobs
  set 
    parts_cost = v_parts_cost,
    labor_cost = v_labor_cost,
    total_cost = v_total_cost,
    updated_at = now()
  where id = coalesce(NEW.job_id, OLD.job_id);
  
  return coalesce(NEW, OLD);
end;
$$;

-- Triggers for mechanic_job_items
drop trigger if exists trg_update_job_costs_on_item_insert on mechanic_job_items;
create trigger trg_update_job_costs_on_item_insert
  after insert on mechanic_job_items
  for each row
  execute function public.update_mechanic_job_costs();

drop trigger if exists trg_update_job_costs_on_item_update on mechanic_job_items;
create trigger trg_update_job_costs_on_item_update
  after update on mechanic_job_items
  for each row
  when (OLD.total_price is distinct from NEW.total_price)
  execute function public.update_mechanic_job_costs();

drop trigger if exists trg_update_job_costs_on_item_delete on mechanic_job_items;
create trigger trg_update_job_costs_on_item_delete
  after delete on mechanic_job_items
  for each row
  execute function public.update_mechanic_job_costs();

-- Triggers for mechanic_job_labor
drop trigger if exists trg_update_job_costs_on_labor_insert on mechanic_job_labor;
create trigger trg_update_job_costs_on_labor_insert
  after insert on mechanic_job_labor
  for each row
  execute function public.update_mechanic_job_costs();

drop trigger if exists trg_update_job_costs_on_labor_update on mechanic_job_labor;
create trigger trg_update_job_costs_on_labor_update
  after update on mechanic_job_labor
  for each row
  when (OLD.total_cost is distinct from NEW.total_cost)
  execute function public.update_mechanic_job_costs();

drop trigger if exists trg_update_job_costs_on_labor_delete on mechanic_job_labor;
create trigger trg_update_job_costs_on_labor_delete
  after delete on mechanic_job_labor
  for each row
  execute function public.update_mechanic_job_costs();

-- ============================================================
-- FIX EXISTING DATA: Recalculate all pega costs
-- ============================================================

-- Update all existing pegas with correct costs
do $$
declare
  v_job record;
  v_parts_cost numeric;
  v_labor_cost numeric;
begin
  for v_job in select id from mechanic_jobs loop
    -- Calculate parts cost
    select coalesce(sum(total_price), 0)
    into v_parts_cost
    from mechanic_job_items
    where job_id = v_job.id;
    
    -- Calculate labor cost
    select coalesce(sum(total_cost), 0)
    into v_labor_cost
    from mechanic_job_labor
    where job_id = v_job.id;
    
    -- Update job
    update mechanic_jobs
    set 
      parts_cost = v_parts_cost,
      labor_cost = v_labor_cost,
      total_cost = v_parts_cost + v_labor_cost,
      updated_at = now()
    where id = v_job.id
      and (parts_cost != v_parts_cost or labor_cost != v_labor_cost);
  end loop;
  
  raise notice 'Cost recalculation complete!';
end $$;
