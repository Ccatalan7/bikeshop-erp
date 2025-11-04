-- ============================================================
-- TEST 1: Delete the invoice
-- ============================================================
DELETE FROM sales_invoices WHERE id = 'abce6bc5-052b-4d8a-8026-c63289b1cb10';

-- ============================================================
-- TEST 2: Check if pega was deleted (should return 0 rows)
-- ============================================================
SELECT * FROM mechanic_jobs WHERE id = '50baf3aa-3089-46ec-ad29-a76ec0b6d9ae';

-- If you see the pega still exists, the trigger didn't work!
-- If you get 0 rows, the trigger worked! ✅

-- ============================================================
-- TEST 3: Check Postgres logs
-- ============================================================
-- Go to: Supabase Dashboard → Logs → Postgres Logs
-- Filter for: "TRIGGER FIRED" or "Deleting pega" or "cascade_delete"
-- You should see log messages from the trigger function
