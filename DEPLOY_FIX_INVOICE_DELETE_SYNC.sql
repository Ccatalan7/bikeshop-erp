-- ============================================================
-- FIX 3: Enable invoice sync on DELETE operations
-- ============================================================
-- Issue: When removing products/services from Tasks tab or Detalles tab,
-- the items were deleted from pega but NOT removed from the linked invoice.
--
-- Root Cause: DELETE triggers were skipping sync with comment:
-- "let the app handle manual sync after batch delete+insert"
--
-- Solution: Enable DELETE sync - the sync_job_to_invoice() function
-- properly handles all scenarios including batch operations.
-- ============================================================

-- ============================================================
-- FIX 1: Drop rogue triggers on mechanic_job_tasks
-- ============================================================
-- Issue: Old triggers still firing on mechanic_job_tasks table
-- Error: "record 'new' has no field 'service_product_id'"
--
-- Root Cause: Cleanup wasn't dropping triggers on mechanic_job_tasks itself
-- Some old trigger is calling auto_parse_item_description() which expects
-- product/service fields from mechanic_job_items
--
-- Solution: Drop ALL old triggers on mechanic_job_tasks, then recreate only the new ones
-- ============================================================

do $$
declare
  r record;
begin
  -- Drop ALL old triggers on mechanic_job_tasks (will be recreated with new schema)
  for r in (
    select trigger_name 
    from information_schema.triggers 
    where event_object_table = 'mechanic_job_tasks'
      and trigger_name not in ('trg_sync_adhoc_task_to_item', 'trg_set_task_completed_at', 'trg_mechanic_job_tasks_updated_at')
  ) loop
    execute format('drop trigger if exists %I on mechanic_job_tasks cascade', r.trigger_name);
    raise notice 'Dropped old task trigger: %', r.trigger_name;
  end loop;
end $$;

-- Fix the auto_parse_item_description function with better table check
create or replace function public.auto_parse_item_description()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_description text;
  v_task_count integer;
  v_product_id uuid;
  v_service_product_id uuid;
begin
  -- CRITICAL: Only process mechanic_job_items
  if TG_TABLE_NAME <> 'mechanic_job_items' then
    raise notice 'auto_parse_item_description: skipping table %', TG_TABLE_NAME;
    return null;
  end if;
  
  -- Safely capture product/service references
  begin
    v_product_id := (NEW).product_id;
    v_service_product_id := (NEW).service_product_id;
  exception
    when undefined_column then
      raise warning 'auto_parse_item_description: column access error on table %, skipping', TG_TABLE_NAME;
      return null;
  end;
  
  -- Get product/service description
  if v_product_id is not null then
    select description into v_description
    from products
    where id = v_product_id;
    
    if v_description is not null then
      v_task_count := public.parse_description_to_tasks(
        NEW.tenant_id,
        NEW.job_id,
        NEW.id,
        v_description
      );
      
      if v_task_count > 0 then
        raise notice 'Auto-parsed % tasks from product description', v_task_count;
      end if;
    end if;
    
  elsif v_service_product_id is not null then
    select description into v_description
    from products
    where id = v_service_product_id;
    
    if v_description is not null then
      v_task_count := public.parse_description_to_tasks(
        NEW.tenant_id,
        NEW.job_id,
        NEW.id,
        v_description
      );
      
      if v_task_count > 0 then
        raise notice 'Auto-parsed % tasks from service description', v_task_count;
      end if;
    end if;
  end if;
  
  return null; -- AFTER trigger must return null
end;
$$;

-- Fix the sync_adhoc_task_to_item to return null (AFTER trigger requirement)
create or replace function public.sync_adhoc_task_to_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    if NEW.is_adhoc and NEW.adhoc_price is not null and NEW.adhoc_price > 0 then
      perform public.create_adhoc_item_for_task(NEW.id);
    end if;
    
  elsif TG_OP = 'UPDATE' then
    -- Price added to existing task
    if NEW.is_adhoc and NEW.adhoc_price is not null and 
       (OLD.adhoc_price is null or OLD.adhoc_price != NEW.adhoc_price) then
      
      -- If item exists, update it
      if NEW.adhoc_item_id is not null then
        update mechanic_job_items
        set 
          product_name = 'Ad-hoc: ' || NEW.task_name,
          unit_price = NEW.adhoc_price,
          total_price = NEW.adhoc_price
        where id = NEW.adhoc_item_id;
      else
        -- Create new item
        perform public.create_adhoc_item_for_task(NEW.id);
      end if;
    end if;
    
    -- Price removed
    if OLD.adhoc_price is not null and NEW.adhoc_price is null and NEW.adhoc_item_id is not null then
      delete from mechanic_job_items where id = NEW.adhoc_item_id;
    end if;
  end if;
  
  return null; -- AFTER trigger must return null
end;
$$;

-- ============================================================
-- FIX 2: Drop old task schema columns
-- ============================================================
-- Issue: Database still has old columns (title, status, task_type, etc.)
-- causing NOT NULL constraint violations when creating tasks.
--
-- Error: "null value in column 'title' violates not-null constraint"
--
-- Root Cause: Old triggers were dropped but old table columns remained.
-- New code uses task_name, is_completed, parent_item_id, parent_labor_id
-- but old columns (title, status, job_item_id, job_labor_id) still exist.
--
-- Solution: Drop all old columns from mechanic_job_tasks table.
-- ============================================================

-- Drop old task columns
do $$
begin
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'title') then
    alter table mechanic_job_tasks alter column title drop not null;
    alter table mechanic_job_tasks drop column title cascade;
    raise notice 'Dropped old column: title';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'status') then
    alter table mechanic_job_tasks drop column status cascade;
    raise notice 'Dropped old column: status';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'task_type') then
    alter table mechanic_job_tasks drop column task_type cascade;
    raise notice 'Dropped old column: task_type';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'job_item_id') then
    alter table mechanic_job_tasks drop column job_item_id cascade;
    raise notice 'Dropped old column: job_item_id';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'job_labor_id') then
    alter table mechanic_job_tasks drop column job_labor_id cascade;
    raise notice 'Dropped old column: job_labor_id';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'priority') then
    alter table mechanic_job_tasks drop column priority cascade;
    raise notice 'Dropped old column: priority';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'assigned_to') then
    alter table mechanic_job_tasks drop column assigned_to cascade;
    raise notice 'Dropped old column: assigned_to';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'assigned_technician_name') then
    alter table mechanic_job_tasks drop column assigned_technician_name cascade;
    raise notice 'Dropped old column: assigned_technician_name';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'estimated_duration_minutes') then
    alter table mechanic_job_tasks drop column estimated_duration_minutes cascade;
    raise notice 'Dropped old column: estimated_duration_minutes';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'started_at') then
    alter table mechanic_job_tasks drop column started_at cascade;
    raise notice 'Dropped old column: started_at';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'is_auto_generated') then
    alter table mechanic_job_tasks drop column is_auto_generated cascade;
    raise notice 'Dropped old column: is_auto_generated';
  end if;
  
  if exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'description') then
    alter table mechanic_job_tasks drop column description cascade;
    raise notice 'Dropped old column: description';
  end if;
end $$;

-- Fix items DELETE trigger
create or replace function public.sync_job_items_to_invoice_statement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_id uuid;
  v_invoice_id uuid;
  v_syncing_flag text;
begin
  -- Check if we're currently syncing invoice → job (prevent circular sync)
  v_syncing_flag := current_setting('app.syncing_invoice_to_job', true);
  if v_syncing_flag = 'true' then
    raise notice 'sync_job_items_to_invoice_statement: skipping due to invoice→job sync in progress';
    return null;
  end if;

  -- Handle DELETE operations - get job_id from old_table
  if TG_OP = 'DELETE' then
    for v_job_id in select distinct job_id from old_table
    loop
      -- Recalculate costs first to update job record with new totals
      perform public.recalculate_mechanic_job_costs(v_job_id);
      
      -- Find the linked invoice
      select invoice_id into v_invoice_id from mechanic_jobs where id = v_job_id;
      
      if v_invoice_id is not null then
        -- Sync this job to its invoice (will remove deleted items)
        perform public.sync_job_to_invoice(v_job_id);
      end if;
    end loop;
    return null;
  end if;

  -- Handle INSERT and UPDATE - sync immediately since we're adding/changing items
  for v_job_id in select distinct job_id from new_table
  loop
    -- Recalculate costs first to update job record with new totals
    perform public.recalculate_mechanic_job_costs(v_job_id);
    
    -- Find the linked invoice
    select invoice_id into v_invoice_id from mechanic_jobs where id = v_job_id;
    
    if v_invoice_id is not null then
      -- Sync this job to its invoice (will recalculate fresh totals from DB)
      perform public.sync_job_to_invoice(v_job_id);
    end if;
  end loop;
  
  return null;
end;
$$;

-- ============================================================
-- VERIFICATION QUERIES
-- ============================================================

-- Check triggers are installed
SELECT tgname, tgrelid::regclass 
FROM pg_trigger 
WHERE tgname LIKE '%sync_invoice%'
ORDER BY tgname;

-- Expected triggers:
-- trg_mechanic_job_items_sync_invoice_delete
-- trg_mechanic_job_items_sync_invoice_insert
-- trg_mechanic_job_items_sync_invoice_update
