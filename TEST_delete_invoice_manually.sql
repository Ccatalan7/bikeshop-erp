-- ============================================================
-- MANUAL TEST: Delete invoice and verify pega is deleted
-- ============================================================

-- Step 1: Find a pega with an invoice
select 
  mj.id as pega_id,
  mj.job_number,
  mj.invoice_id,
  si.invoice_number,
  si.id as invoice_id_full
from mechanic_jobs mj
join sales_invoices si on si.id = mj.invoice_id
where mj.invoice_id is not null
order by mj.created_at desc
limit 1;

-- Step 2: Copy the invoice_id from above and paste it below:
-- DELETE FROM sales_invoices WHERE id = 'PASTE_INVOICE_ID_HERE';

-- Step 3: Check if the pega was deleted (should return 0 rows if trigger worked):
-- SELECT * FROM mechanic_jobs WHERE id = 'PASTE_PEGA_ID_HERE';

-- Step 4: Go to Supabase Dashboard → Logs → Postgres Logs
-- Filter for messages containing "TRIGGER FIRED" or "Deleting pega"
-- You should see logs from the cascade_delete_pega_invoice() function
