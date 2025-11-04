-- ============================================================
-- FIX: Auto-create and link invoice when pega is created
-- This ensures invoice_id is properly set on the pega
-- ============================================================

-- First, fix the auto-create invoice trigger
create or replace function public.auto_create_invoice_for_new_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice_id uuid;
begin
  raise notice '🔔 [TRIGGER] New pega created: % (customer: %)', NEW.job_number, NEW.customer_id;
  
  -- Only create invoice if customer is specified
  if NEW.customer_id is not null then
    raise notice '📝 Creating invoice for pega %...', NEW.id;
    
    -- Create draft invoice linked to this job
    v_invoice_id := public.create_invoice_from_mechanic_job(NEW.id);
    
    if v_invoice_id is not null then
      raise notice '✅ Created invoice %, now linking to pega %', v_invoice_id, NEW.id;
      
      -- Update NEW record directly (this is BEFORE/AFTER INSERT trigger)
      -- Using dynamic SQL to bypass any potential RLS issues
      execute format(
        'update mechanic_jobs set invoice_id = %L, is_invoiced = true, updated_at = now() where id = %L',
        v_invoice_id,
        NEW.id
      );
      
      -- Also update the NEW record that will be returned
      NEW.invoice_id := v_invoice_id;
      NEW.is_invoiced := true;
      
      raise notice '✅ Linked invoice % to pega %', v_invoice_id, NEW.id;
    else
      raise notice '⚠️ Failed to create invoice for pega %', NEW.id;
    end if;
  else
    raise notice '⚠️ Pega % has no customer, skipping invoice creation', NEW.id;
  end if;
  
  return NEW;
exception
  when others then
    raise notice '❌ ERROR in auto_create_invoice_for_new_job: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
    return NEW;
end;
$$;

-- Recreate the trigger (in case it doesn't exist)
drop trigger if exists trg_auto_create_invoice_for_job on public.mechanic_jobs;
create trigger trg_auto_create_invoice_for_job
  after insert on public.mechanic_jobs
  for each row
  execute function public.auto_create_invoice_for_new_job();

-- Verify trigger exists
select 
  trigger_name, 
  event_object_table, 
  action_timing, 
  event_manipulation
from information_schema.triggers 
where trigger_name = 'trg_auto_create_invoice_for_job';

-- Test: Check if existing pegas have invoices linked
select 
  mj.id as pega_id,
  mj.job_number,
  mj.customer_id,
  mj.invoice_id,
  mj.is_invoiced,
  si.invoice_number
from mechanic_jobs mj
left join sales_invoices si on si.id = mj.invoice_id
order by mj.created_at desc
limit 5;
