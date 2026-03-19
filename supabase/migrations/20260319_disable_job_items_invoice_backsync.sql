-- Disable automatic mechanic_job_items -> sales_invoices statement sync.
-- This back-sync has been overwriting invoice items after manual invoice edits.
-- Source of truth remains `supabase/sql/core_schema.sql`.

create or replace function public.sync_job_items_to_invoice_statement()
returns trigger
language plpgsql
as $$
begin
  raise notice 'sync_job_items_to_invoice_statement: auto back-sync disabled to prevent invoice item loss';
  return null;
end;
$$;