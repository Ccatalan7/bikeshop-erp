-- ============================================================
-- COMPLETE TEST WITH FRESH DATA
-- ============================================================

-- Step 1: Create a fresh pega to test with
INSERT INTO mechanic_jobs (
  tenant_id,
  customer_id,
  bike_id,
  status,
  priority,
  estimated_cost,
  final_cost
) VALUES (
  '5443b130-cc28-45af-a420-cd500b288890',  -- Your tenant_id
  '1e7dc61a-c9e6-4bf6-8a2d-ea47040cb85f',  -- Customer from previous pega
  '6fff4120-a4d2-4158-9286-b4c4d8129bf9',  -- Bike from previous pega
  'PENDIENTE',
  'NORMAL',
  10000,
  10000
)
RETURNING id, job_number, invoice_id;

-- Step 2: The trigger should auto-create an invoice. Copy the pega id and check:
-- SELECT id, job_number, invoice_id FROM mechanic_jobs WHERE id = 'PASTE_PEGA_ID_HERE';

-- Step 3: Copy the invoice_id from step 2 and delete it:
-- DELETE FROM sales_invoices WHERE id = 'PASTE_INVOICE_ID_HERE';

-- Step 4: Check if the pega was deleted:
-- SELECT * FROM mechanic_jobs WHERE id = 'PASTE_PEGA_ID_HERE';
-- Should return 0 rows if cascade delete worked!

-- Step 5: Check Postgres logs in Supabase Dashboard
-- Look for messages like:
-- "🗑️ [TRIGGER] Invoice ... deleted"
-- "🔍 Found pega ... linked to invoice ..."
-- "✅ Deleted pega ..." or "❌ Failed to delete pega ..."
