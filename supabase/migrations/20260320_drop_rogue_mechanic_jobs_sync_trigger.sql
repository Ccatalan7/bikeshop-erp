-- =============================================================================
-- FIX: Drop rogue trigger that overwrites sales_invoices.items after save
-- =============================================================================
-- ROOT CAUSE:
--   FIX_CALENDAR_VIEW_SYNC.sql (deployed previously) created:
--     trg_mechanic_jobs_sync_invoice_update (statement-level AFTER UPDATE on mechanic_jobs)
--   This trigger fires AFTER every mechanic_jobs UPDATE and calls sync_job_to_invoice().
--
-- THE RACE:
--   1. User saves invoice with 3 items via invoice editor
--   2. handle_sales_invoice_change → sync_invoice_items_to_job runs
--      (sets app.syncing_invoice_to_job='true' via begin/end savepoint)
--   3. sync_invoice_items_to_job UPDATEs mechanic_jobs (costs, labor, etc.)
--   4. At this point the savepoint exits → is_local flag is CLEARED automatically
--   5. trg_mechanic_jobs_sync_invoice_update fires (AFTER UPDATE, statement-level)
--   6. sync_job_changes_to_invoice_statement checks flag → flag is '' (already cleared)
--   7. sync_job_to_invoice(job_id) runs → reads mechanic_job_items (from FIX version,
--      missing fields: product_sku, is_catalog_product, job_bike_id, bike_name, item_type)
--   8. Overwrites sales_invoices.items with a degraded/partial snapshot → items count may differ
--
-- FIX:
--   Drop the trigger. The forward sync (invoice→job) in handle_sales_invoice_change
--   handles job updates correctly. The rogue back-sync (job→invoice) here is not needed
--   and creates the race condition that loses invoice items.
--
--   NOTE: sync_job_changes_to_invoice_statement function is also dropped since it has
--   no other callers and the sync_job_to_invoice function is still available for
--   explicit calls from the pega form when the user intentionally edits job items.
-- =============================================================================

-- Drop the rogue trigger
drop trigger if exists trg_mechanic_jobs_sync_invoice_update on mechanic_jobs;

-- Drop the helper function (only used by this trigger)
drop function if exists public.sync_job_changes_to_invoice_statement();

-- Verify the trigger is gone
do $$
begin
  if exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'mechanic_jobs'
      and t.tgname = 'trg_mechanic_jobs_sync_invoice_update'
  ) then
    raise exception 'ERROR: trg_mechanic_jobs_sync_invoice_update still exists after drop!';
  else
    raise notice 'OK: trg_mechanic_jobs_sync_invoice_update has been dropped successfully';
  end if;
end $$;
