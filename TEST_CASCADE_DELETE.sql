-- ============================================================
-- TEST: Verify cascade delete is working
-- Run this in Supabase SQL Editor
-- ============================================================

-- Step 1: Check foreign key constraint ✅ PASSED - delete_rule is CASCADE
SELECT 
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    rc.delete_rule
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
    AND ccu.table_schema = tc.table_schema
JOIN information_schema.referential_constraints AS rc
    ON tc.constraint_name = rc.constraint_name
WHERE tc.table_name = 'mechanic_jobs' 
  AND kcu.column_name = 'invoice_id';

-- Step 2: Check what triggers exist on sales_invoices
SELECT 
    tgname AS trigger_name,
    tgenabled AS enabled,
    tgtype AS trigger_type,
    CASE 
        WHEN tgtype::int & 1 = 1 THEN 'ROW'
        ELSE 'STATEMENT'
    END AS level,
    CASE 
        WHEN tgtype::int & 2 = 2 THEN 'BEFORE'
        WHEN tgtype::int & 64 = 64 THEN 'INSTEAD OF'
        ELSE 'AFTER'
    END AS timing,
    CASE 
        WHEN tgtype::int & 4 = 4 THEN 'INSERT'
        WHEN tgtype::int & 8 = 8 THEN 'DELETE'
        WHEN tgtype::int & 16 = 16 THEN 'UPDATE'
        WHEN tgtype::int & 32 = 32 THEN 'TRUNCATE'
    END AS event
FROM pg_trigger
WHERE tgrelid = 'sales_invoices'::regclass
  AND tgisinternal = false
ORDER BY tgname;

-- Step 3: Test actual delete with logging
-- Find a pega with an invoice
SELECT 
    mj.id as pega_id, 
    mj.invoice_id,
    mj.job_number,
    si.invoice_number,
    mj.tenant_id
FROM mechanic_jobs mj
JOIN sales_invoices si ON mj.invoice_id = si.id
WHERE mj.invoice_id IS NOT NULL 
LIMIT 1;

-- Copy the IDs from above and run:
-- DELETE FROM sales_invoices WHERE id = 'PASTE-INVOICE-ID-HERE';
-- Then check if pega still exists:
-- SELECT * FROM mechanic_jobs WHERE id = 'PASTE-PEGA-ID-HERE';

