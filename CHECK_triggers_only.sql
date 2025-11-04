-- Check if both triggers exist and are enabled
select 
  tgname as trigger_name,
  tgenabled as enabled,
  tgrelid::regclass as table_name,
  pg_get_triggerdef(oid) as trigger_definition
from pg_trigger
where tgname in ('trg_delete_pega_cascade_invoice', 'trg_delete_invoice_cascade_pega')
order by tgname;

-- Expected 2 rows:
-- trg_delete_pega_cascade_invoice | O | mechanic_jobs | ...
-- trg_delete_invoice_cascade_pega | O | sales_invoices | ...
