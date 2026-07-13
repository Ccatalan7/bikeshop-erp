-- FIX: Prevent sub-tasks from creating duplicate items
-- Sub-tasks belong to their parent product/service, not standalone items
-- Lines 12023-12069 from core_schema.sql

create or replace function public.sync_adhoc_task_to_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    -- CRITICAL: Only create item for PARENT ad-hoc tasks (not sub-tasks)
    -- Sub-tasks belong to their parent product/service, not standalone items
    if NEW.is_adhoc and NEW.adhoc_price is not null and NEW.adhoc_price > 0 and
       NEW.parent_item_id is null and NEW.parent_labor_id is null then
      perform public.create_adhoc_item_for_task(NEW.id);
    end if;
    
  elsif TG_OP = 'UPDATE' then
    -- CRITICAL: Only sync if this is a PARENT ad-hoc task (not a sub-task)
    if NEW.parent_item_id is not null or NEW.parent_labor_id is not null then
      -- This is a sub-task, don't create standalone item
      return null;
    end if;
    
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
    
  elsif TG_OP = 'DELETE' then
    -- Remove associated item if exists
    if OLD.adhoc_item_id is not null then
      delete from mechanic_job_items where id = OLD.adhoc_item_id;
    end if;
  end if;
  
  return null;
end;
$$;
