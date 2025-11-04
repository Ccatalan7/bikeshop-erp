-- ============================================================
-- FIX: Change FK from "ON DELETE SET NULL" to "ON DELETE CASCADE"
-- ============================================================

-- Step 1: Drop the old FK constraint with SET NULL
ALTER TABLE mechanic_jobs 
DROP CONSTRAINT IF EXISTS mechanic_jobs_invoice_id_fkey;

-- Step 2: Re-add FK with CASCADE (so deleting invoice deletes pega)
ALTER TABLE mechanic_jobs 
ADD CONSTRAINT mechanic_jobs_invoice_id_fkey 
FOREIGN KEY (invoice_id) 
REFERENCES sales_invoices(id) 
ON DELETE CASCADE;

-- Step 3: Verify the change
SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    rc.delete_rule,
    rc.update_rule
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints AS rc
  ON rc.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_name = 'mechanic_jobs'
  AND kcu.column_name = 'invoice_id';

-- Expected: delete_rule should be "CASCADE" (not "SET NULL")
