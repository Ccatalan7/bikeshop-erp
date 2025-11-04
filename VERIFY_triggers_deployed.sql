-- ============================================================
-- VERIFY: Check if triggers are deployed and enabled
-- ============================================================

-- 1. Check if triggers exist on both tables
select 
  tgname as trigger_name,
  tgenabled as enabled,
  tgrelid::regclass as table_name,
  pg_get_triggerdef(oid) as trigger_definition
from pg_trigger
where tgname in ('trg_delete_pega_cascade_invoice', 'trg_delete_invoice_cascade_pega')
order by tgname;

-- Expected results:
-- trg_delete_pega_cascade_invoice | O | mechanic_jobs | ...
-- trg_delete_invoice_cascade_pega | O | sales_invoices | ...
-- (O = enabled, D = disabled)

-- 2. Check function ownership
select 
  p.proname as function_name,
  pg_catalog.pg_get_userbyid(p.proowner) as owner,
  p.prosecdef as security_definer
from pg_proc p
where p.proname = 'cascade_delete_pega_invoice';

-- Expected: owner = 'postgres', security_definer = true

-- 3. Test manually (REPLACE UUIDs WITH REAL VALUES)
-- Find a linked pega+invoice:
select 
  mj.id as pega_id,
  mj.job_number,
  mj.invoice_id,
  si.invoice_number
from mechanic_jobs mj
join sales_invoices si on si.id = mj.invoice_id
where mj.invoice_id is not null
limit 1;

-- Then delete the invoice and check if pega deleted:
-- DELETE FROM sales_invoices WHERE id = '<invoice_id_from_above>';
-- SELECT * FROM mechanic_jobs WHERE id = '<pega_id_from_above>';
-- Should return no rows if trigger worked
