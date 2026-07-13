-- Deploy bulletproof auto_parse_item_description() function
-- Lines 11655-11735 from supabase/sql/core_schema.sql (Nov 19 2025)
-- Updated after removing mechanic_job_labor: works exclusively with mechanic_job_items

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
  -- CRITICAL: IMMEDIATELY RETURN if not on mechanic_job_items
  if TG_TABLE_NAME <> 'mechanic_job_items' then
    raise notice 'auto_parse_item_description: skipping table %, trigger: %', TG_TABLE_NAME, TG_NAME;
    return null;  -- AFTER trigger, return null is correct
  end if;
  
  -- Use exception handling to safely access fields
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
  
  return null;  -- AFTER trigger must return null
end;
$$;
