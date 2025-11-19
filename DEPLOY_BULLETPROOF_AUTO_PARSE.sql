-- Deploy bulletproof auto_parse_item_description() function
-- Lines 11935-12005 from core_schema.sql
-- This version has exception handling and safe field access to prevent product_id errors

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
  -- CRITICAL: IMMEDIATELY RETURN if not on correct tables
  -- This prevents ANY field access on wrong table
  if TG_TABLE_NAME not in ('mechanic_job_items', 'mechanic_job_labor') then
    raise notice 'auto_parse_item_description: skipping table %, trigger: %', TG_TABLE_NAME, TG_NAME;
    return null;  -- AFTER trigger, return null is correct
  end if;
  
  -- Use exception handling to safely access fields
  begin
    -- Try to get product_id or service_product_id safely
    if TG_TABLE_NAME = 'mechanic_job_items' then
      v_product_id := (NEW).product_id;
    elsif TG_TABLE_NAME = 'mechanic_job_labor' then
      v_service_product_id := (NEW).service_product_id;
    end if;
  exception
    when undefined_column then
      raise warning 'auto_parse_item_description: column access error on table %, skipping', TG_TABLE_NAME;
      return null;
  end;
  
  -- Get product/service description
  if TG_TABLE_NAME = 'mechanic_job_items' and v_product_id is not null then
    select description into v_description
    from products
    where id = v_product_id;
    
    if v_description is not null then
      v_task_count := public.parse_description_to_tasks(
        NEW.tenant_id,
        NEW.job_id,
        NEW.id,
        null,
        v_description
      );
      
      if v_task_count > 0 then
        raise notice 'Auto-parsed % tasks from product description', v_task_count;
      end if;
    end if;
    
  elsif TG_TABLE_NAME = 'mechanic_job_labor' and v_service_product_id is not null then
    select description into v_description
    from products
    where id = v_service_product_id;
    
    if v_description is not null then
      v_task_count := public.parse_description_to_tasks(
        NEW.tenant_id,
        NEW.job_id,
        null,
        NEW.id,
        v_description
      );
      
      if v_task_count > 0 then
        raise notice 'Auto-parsed % tasks from service description', v_task_count;
      end if;
    end if;
  end if;
  
  return null;  -- AFTER trigger must return null
end;
$$;
