-- ============================================================
-- FIX: Bidirectional Cascade Delete (Invoice ↔ Pega)
-- Deploy this in Supabase SQL Editor
-- ============================================================

-- The Problem: Foreign key ON DELETE CASCADE doesn't work with RLS
-- The Solution: Use triggers with SECURITY DEFINER to bypass RLS

create or replace function public.cascade_delete_pega_invoice()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  raise notice '🔥 CASCADE DELETE TRIGGERED: table=%, op=%, trigger_depth=%', TG_TABLE_NAME, TG_OP, pg_trigger_depth();
  
  -- Prevent infinite recursion
  if pg_trigger_depth() > 1 then
    raise notice '⚠️ RECURSION DETECTED - Exiting at depth %', pg_trigger_depth();
    return OLD;
  end if;

  -- Handle invoice deletion → delete pega
  if TG_TABLE_NAME = 'sales_invoices' then
    raise notice '🔹 INVOICE DELETED: id=%, number=%, tenant_id=%', OLD.id, OLD.invoice_number, OLD.tenant_id;
    
    -- Delete all pegas linked to this invoice
    delete from mechanic_jobs 
    where invoice_id = OLD.id 
      and tenant_id = OLD.tenant_id;
    
    get diagnostics v_count = ROW_COUNT;
    raise notice '✅ Deleted % pega(s) linked to invoice %', v_count, OLD.invoice_number;
  end if;

  -- Handle pega deletion → delete invoice
  if TG_TABLE_NAME = 'mechanic_jobs' then
    raise notice '🔹 PEGA DELETED: id=%, job_number=%, invoice_id=%, tenant_id=%', OLD.id, OLD.job_number, OLD.invoice_id, OLD.tenant_id;
    
    if OLD.invoice_id is not null then
      raise notice '🔸 Attempting to delete invoice % (tenant: %)', OLD.invoice_id, OLD.tenant_id;
      
      delete from sales_invoices 
      where id = OLD.invoice_id 
        and tenant_id = OLD.tenant_id;
      
      get diagnostics v_count = ROW_COUNT;
      raise notice '✅ Deleted % invoice(s) for pega %', v_count, OLD.job_number;
    else
      raise notice '⚠️ Pega has no invoice_id, skipping invoice delete';
    end if;
  end if;

  raise notice '🏁 CASCADE DELETE COMPLETED';
  return OLD;
end;
$$;

-- Create triggers for BOTH directions
drop trigger if exists trg_delete_pega_cascade_invoice on mechanic_jobs cascade;
create trigger trg_delete_pega_cascade_invoice
  after delete on mechanic_jobs
  for each row
  execute function public.cascade_delete_pega_invoice();

drop trigger if exists trg_delete_invoice_cascade_pega on sales_invoices cascade;
create trigger trg_delete_invoice_cascade_pega
  after delete on sales_invoices
  for each row
  execute function public.cascade_delete_pega_invoice();
