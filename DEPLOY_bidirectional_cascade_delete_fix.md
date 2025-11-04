# 🔧 Deploy to Supabase: Bidirectional Cascade Delete for Pegas ↔ Invoices

**Modified:** `core_schema.sql` lines 8270-8360

## What This Fixes

- ✅ **Before:** Deleting a pega deleted the invoice, but deleting an invoice did NOT delete the pega
- ✅ **After:** Both directions work - deleting either one deletes the other (bidirectional cascade)

## Features

1. **Recursion Guard:** Prevents infinite loops using transaction-level settings
2. **Debug Logging:** Shows what's being deleted in Supabase logs (useful for troubleshooting)
3. **RLS Bypass:** Uses `SECURITY DEFINER` to bypass Row Level Security during cascade
4. **Tenant-Safe:** Only deletes records within the same tenant

## SQL to Deploy

Copy this SQL and run it in **Supabase SQL Editor**:

```sql
-- ============================================================
-- Bidirectional Cascade Delete: Pega ↔ Sales Invoice
-- ============================================================

create or replace function public.cascade_delete_pega_invoice()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
  v_recursion_guard boolean;
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
    return OLD;
  end if;
  
  -- Set recursion guard
  perform set_config('app.cascade_delete_in_progress', 'true', true);
  
  -- Handle invoice deletion → delete pega
  if TG_TABLE_NAME = 'sales_invoices' then
    raise notice '🗑️ Cascade: Invoice deleted (id=%), deleting linked pega...', OLD.id;
    
    -- Delete linked mechanic_jobs (bypass RLS with SECURITY DEFINER)
    delete from mechanic_jobs 
    where invoice_id = OLD.id 
      and tenant_id = OLD.tenant_id;
    
    get diagnostics v_count = ROW_COUNT;
    
    if v_count > 0 then
      raise notice '✅ Deleted % pega(s) linked to invoice %', v_count, OLD.id;
    end if;
  end if;

  -- Handle pega deletion → delete invoice  
  if TG_TABLE_NAME = 'mechanic_jobs' then
    if OLD.invoice_id is not null then
      raise notice '🗑️ Cascade: Pega deleted (id=%), deleting linked invoice %...', OLD.id, OLD.invoice_id;
      
      -- Delete linked sales_invoice (bypass RLS with SECURITY DEFINER)
      delete from sales_invoices 
      where id = OLD.invoice_id 
        and tenant_id = OLD.tenant_id;
      
      get diagnostics v_count = ROW_COUNT;
      
      if v_count > 0 then
        raise notice '✅ Deleted invoice % linked to pega %', OLD.invoice_id, OLD.id;
      end if;
    end if;
  end if;
  
  -- Clear recursion guard
  perform set_config('app.cascade_delete_in_progress', 'false', true);
  
  return OLD;
exception
  when others then
    -- Clear recursion guard on error
    perform set_config('app.cascade_delete_in_progress', 'false', true);
    raise notice '⚠️ Error in cascade_delete_pega_invoice: %', SQLERRM;
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
```

## How to Test

After deploying:

1. **Test Invoice → Pega Delete:**
   - Create a new pega (mechanic job)
   - Note the invoice ID that gets auto-created
   - Delete the invoice from Sales module
   - Verify the pega is also deleted

2. **Test Pega → Invoice Delete:**
   - Create a new pega (mechanic job)
   - Delete the pega from Bikeshop module
   - Verify the invoice is also deleted

3. **Check Logs (Optional):**
   - In Supabase Dashboard → Logs → Postgres Logs
   - Look for messages like:
     - `🗑️ Cascade: Invoice deleted...`
     - `✅ Deleted 1 pega(s) linked to invoice...`

## What Changed

- **Recursion Guard:** Added transaction-level setting to prevent infinite loops
- **Debug Logging:** Added `raise notice` statements for troubleshooting
- **Error Handling:** Improved exception handling with cleanup
- **Both Triggers Deployed:** Ensures both directions work correctly

---

**Deploy this now to fix the bidirectional cascade delete issue!**
