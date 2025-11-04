-- ============================================================
-- FINAL FIX: Simpler trigger that properly bypasses RLS
-- The key: ALTER FUNCTION to be owned by postgres (superuser)
-- ============================================================

create or replace function public.cascade_delete_pega_invoice()
returns trigger
language plpgsql
security definer  -- Run with definer's (postgres) privileges
set search_path = public
as $$
declare
  v_row_count int;
begin
  raise notice '🔔 TRIGGER FIRED: Table=%, Operation=DELETE, Row ID=%', TG_TABLE_NAME, OLD.id;
  
  -- Handle invoice deletion → delete pega
  if TG_TABLE_NAME = 'sales_invoices' then
    raise notice '🗑️ Invoice % deleted (tenant=%), searching for linked pega...', OLD.id, OLD.tenant_id;
    
    -- Delete directly, filtering by tenant_id to maintain data isolation
    delete from mechanic_jobs 
    where invoice_id = OLD.id
      and tenant_id = OLD.tenant_id;  -- Ensure same tenant
    
    get diagnostics v_row_count = ROW_COUNT;
    raise notice '✅ Deleted % pega(s) linked to invoice %', v_row_count, OLD.id;
  end if;

  -- Handle pega deletion → delete invoice  
  if TG_TABLE_NAME = 'mechanic_jobs' and OLD.invoice_id is not null then
    raise notice '🗑️ Pega % deleted (tenant=%), deleting linked invoice %...', OLD.id, OLD.tenant_id, OLD.invoice_id;
    
    -- Delete directly, filtering by tenant_id to maintain data isolation
    delete from sales_invoices 
    where id = OLD.invoice_id
      and tenant_id = OLD.tenant_id;  -- Ensure same tenant
    
    get diagnostics v_row_count = ROW_COUNT;
    raise notice '✅ Deleted invoice % (affected % rows)', OLD.invoice_id, v_row_count;
  end if;
  
  return OLD;
exception
  when others then
    raise notice '❌ ERROR: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
    raise notice 'Context: TG_TABLE_NAME=%, OLD.id=%, OLD.tenant_id=%', TG_TABLE_NAME, OLD.id, OLD.tenant_id;
    return OLD; -- Don't fail the original delete
end;
$$;

-- CRITICAL: Make the function owned by postgres (superuser) to bypass RLS
alter function public.cascade_delete_pega_invoice() owner to postgres;

-- Verify function was updated
select proname, prosrc 
from pg_proc 
where proname = 'cascade_delete_pega_invoice';
