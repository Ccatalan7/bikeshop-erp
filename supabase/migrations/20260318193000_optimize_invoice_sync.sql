-- Optimize Bidirectional Sync between Sales Invoices and Mechanic Jobs
-- This migration removes redundant sync calls from handle_sales_invoice_change
-- to prevent race conditions during status updates while maintaining bidirectional sync.

-- 1. Enhance the specialized items sync trigger to handle both INSERT and UPDATE
DROP TRIGGER IF EXISTS trg_sync_invoice_to_job ON public.sales_invoices;

CREATE TRIGGER trg_sync_invoice_to_job
  AFTER INSERT OR UPDATE OF items ON public.sales_invoices
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_invoice_to_job_on_change();

-- 2. Modify handle_sales_invoice_change to remove redundant items sync on update
-- We only need sync_invoice_status_to_job and recalculate_sales_invoice_payments here.
-- Items sync is now exclusively handled by trg_sync_invoice_to_job.

CREATE OR REPLACE FUNCTION public.handle_sales_invoice_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
declare
  v_non_posted constant text[] := array[
    'draft','borrador',
    'sent','enviado','enviada','issued','emitido','emitida',
    'cancelled','cancelado','cancelada','anulado','anulada'
  ];
  v_old_status text;
  v_new_status text;
  v_old_posted boolean;
  v_new_posted boolean;
begin
  -- 🔄 CIRCULAR SYNC GUARD: Skip if already syncing in either direction
  if current_setting('app.syncing_job_to_invoice', true) = 'true' or 
     current_setting('app.syncing_invoice_to_job', true) = 'true' then
    if TG_OP = 'DELETE' then return OLD; end if;
    return NEW;
  end if;

  -- Prevent infinite recursion
  if pg_trigger_depth() > 1 then
    if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
  end if;

  if TG_OP = 'INSERT' then
    v_new_status := lower(coalesce(NEW.status, 'draft'));
    
    -- Inventory and Journal Entry logic
    if not (v_new_status = any (v_non_posted)) then
      perform public.consume_sales_invoice_inventory(NEW);
      perform public.create_sales_invoice_journal_entry(NEW);
    end if;
    
    perform public.recalculate_sales_invoice_payments(NEW.id);
    
    -- SYNC: Only sync status. Items sync is handled by trg_sync_invoice_to_job (newly added for INSERT)
    perform public.sync_invoice_status_to_job(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    v_new_status := lower(coalesce(NEW.status, 'draft'));
    
    v_old_posted := not (v_old_status = any (v_non_posted));
    v_new_posted := not (v_new_status = any (v_non_posted));

    -- Handle inventory changes based on status transition
    if v_old_posted and v_new_posted then
      perform public.restore_sales_invoice_inventory(OLD);
      perform public.consume_sales_invoice_inventory(NEW);
    elsif v_old_posted and not v_new_posted then
      perform public.restore_sales_invoice_inventory(OLD);
    elsif not v_old_posted and v_new_posted then
      perform public.consume_sales_invoice_inventory(NEW);
    end if;

    -- Journal Entry Handling
    if v_old_posted and not v_new_posted then
      delete from public.journal_entries
      where source_module = 'sales_invoices' and source_reference = OLD.invoice_number;
      update public.sales_payments set deleted_at = now() where invoice_id = OLD.id and deleted_at is null;
    elsif not v_old_posted and v_new_posted then
      perform public.create_sales_invoice_journal_entry(NEW);
    elsif v_old_posted and v_new_posted then
      delete from public.journal_entries
      where source_module = 'sales_invoices' and source_reference = OLD.invoice_number;
      perform public.create_sales_invoice_journal_entry(NEW);
    end if;
    
    perform public.recalculate_sales_invoice_payments(NEW.id);
    
    -- SYNC: Only update status. 
    -- 🚨 THE FIX: sync_invoice_items_to_job call is removed from here 
    -- because it's already handled by trg_sync_invoice_to_job AFTER items actually change.
    -- Calling it here redundantly on status update is what caused the race condition.
    perform public.sync_invoice_status_to_job(NEW.id);
    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    v_old_posted := not (v_old_status = any (v_non_posted));
    if v_old_posted then
      perform public.restore_sales_invoice_inventory(OLD);
      delete from public.journal_entries where source_module = 'sales_invoices' and source_reference = OLD.invoice_number;
      update public.sales_payments set deleted_at = now() where invoice_id = OLD.id and deleted_at is null;
    end if;
    return OLD;
  end if;

  return null;
end;
$$;
