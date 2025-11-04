-- ============================================================
-- FIX: Bidirectional Cascade Delete for Pega ↔ Invoice
-- Deploy this to make invoice deletion also delete the pega
-- ============================================================

-- Drop existing triggers first
drop trigger if exists trg_delete_pega_cascade_invoice on mechanic_jobs cascade;
drop trigger if exists trg_delete_invoice_cascade_pega on sales_invoices cascade;

-- Recreate the function with proper recursion guard and explicit RLS bypass
create or replace function public.cascade_delete_pega_invoice()
returns trigger
language plpgsql
security definer  -- Run with function owner's privileges (bypasses RLS)
set search_path = public
as $$
declare
  v_count int;
  v_recursion_guard boolean;
  v_pega_id uuid;
  v_invoice_id uuid;
begin
  -- Get recursion guard from transaction-level setting
  begin
    v_recursion_guard := current_setting('app.cascade_delete_in_progress', true)::boolean;
  exception
    when others then
      v_recursion_guard := false;
  end;
  
  -- If already in recursion, skip to prevent infinite loop
  if v_recursion_guard then
    raise notice '⏭️ Skipping cascade (recursion guard active)';
    return OLD;
  end if;
  
  -- Set recursion guard
  perform set_config('app.cascade_delete_in_progress', 'true', true);
  
  -- Handle invoice deletion → delete pega
  if TG_TABLE_NAME = 'sales_invoices' then
    raise notice '🗑️ [TRIGGER] Invoice % deleted (tenant=%)', OLD.id, OLD.tenant_id;
    
    -- Find linked pegas
    select id into v_pega_id
    from mechanic_jobs
    where invoice_id = OLD.id 
      and tenant_id = OLD.tenant_id
    limit 1;
    
    if v_pega_id is not null then
      raise notice '🔍 Found pega % linked to invoice %', v_pega_id, OLD.id;
      
      -- Delete using direct SQL (SECURITY DEFINER bypasses RLS)
      execute format('delete from mechanic_jobs where id = %L', v_pega_id);
      
      get diagnostics v_count = ROW_COUNT;
      
      if v_count > 0 then
        raise notice '✅ Deleted pega % linked to invoice %', v_pega_id, OLD.id;
      else
        raise notice '❌ Failed to delete pega %', v_pega_id;
      end if;
    else
      raise notice '⚠️ No pega found with invoice_id=%', OLD.id;
    end if;
  end if;

  -- Handle pega deletion → delete invoice  
  if TG_TABLE_NAME = 'mechanic_jobs' then
    if OLD.invoice_id is not null then
      raise notice '🗑️ [TRIGGER] Pega % deleted (tenant=%)', OLD.id, OLD.tenant_id;
      raise notice '🔍 Looking for linked invoice %', OLD.invoice_id;
      
      -- Verify invoice exists
      select id into v_invoice_id
      from sales_invoices
      where id = OLD.invoice_id
        and tenant_id = OLD.tenant_id;
      
      if v_invoice_id is not null then
        raise notice '🔍 Found invoice % linked to pega %', v_invoice_id, OLD.id;
        
        -- Delete using direct SQL (SECURITY DEFINER bypasses RLS)
        execute format('delete from sales_invoices where id = %L', v_invoice_id);
        
        get diagnostics v_count = ROW_COUNT;
        
        if v_count > 0 then
          raise notice '✅ Deleted invoice % linked to pega %', v_invoice_id, OLD.id;
        else
          raise notice '❌ Failed to delete invoice %', v_invoice_id;
        end if;
      else
        raise notice '⚠️ Invoice % not found (may already be deleted)', OLD.invoice_id;
      end if;
    else
      raise notice '⚠️ Pega % has no linked invoice_id', OLD.id;
    end if;
  end if;
  
  -- Clear recursion guard
  perform set_config('app.cascade_delete_in_progress', 'false', true);
  
  return OLD;
exception
  when others then
    -- Clear recursion guard on error
    perform set_config('app.cascade_delete_in_progress', 'false', true);
    raise notice '❌ ERROR in cascade_delete_pega_invoice: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
    return OLD;
end;
$$;

-- Create triggers for BOTH directions
create trigger trg_delete_pega_cascade_invoice
  after delete on mechanic_jobs
  for each row
  execute function public.cascade_delete_pega_invoice();

create trigger trg_delete_invoice_cascade_pega
  after delete on sales_invoices
  for each row
  execute function public.cascade_delete_pega_invoice();

-- Verify triggers were created
select 
  trigger_name, 
  event_object_table, 
  action_timing, 
  event_manipulation
from information_schema.triggers 
where trigger_name in ('trg_delete_pega_cascade_invoice', 'trg_delete_invoice_cascade_pega')
order by event_object_table;

-- Check current pega-invoice links
select 
  mj.id as pega_id,
  mj.job_number,
  mj.invoice_id,
  si.invoice_number,
  mj.tenant_id
from mechanic_jobs mj
left join sales_invoices si on si.id = mj.invoice_id
order by mj.created_at desc
limit 5;
