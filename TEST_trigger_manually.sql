-- ============================================================
-- TEST: Manual trigger test to verify it works
-- ============================================================

-- Step 1: Find a pega with an invoice
select 
  mj.id as pega_id,
  mj.job_number,
  mj.invoice_id,
  si.invoice_number,
  mj.tenant_id
from mechanic_jobs mj
join sales_invoices si on si.id = mj.invoice_id
where mj.invoice_id is not null
order by mj.created_at desc
limit 1;

-- Step 2: Copy the invoice_id from above and DELETE it directly in SQL
-- Replace 'YOUR_INVOICE_ID_HERE' with the actual UUID
-- DELETE FROM sales_invoices WHERE id = 'YOUR_INVOICE_ID_HERE';

-- Step 3: Check if the pega was deleted
-- SELECT * FROM mechanic_jobs WHERE id = 'YOUR_PEGA_ID_HERE';
-- Should return no rows if trigger worked

-- Step 4: Check logs
-- Go to Supabase Dashboard → Logs → Postgres Logs
-- Filter for messages containing "TRIGGER FIRED" or "cascade"
