-- ============================================================
-- DROP the interfering BEFORE DELETE trigger
-- ============================================================

-- This trigger is setting invoice_id = NULL BEFORE the FK CASCADE can run
DROP TRIGGER IF EXISTS trg_invoice_deleted_clear_job ON sales_invoices;
DROP FUNCTION IF EXISTS handle_invoice_deleted_for_job();

-- Verify it's gone
SELECT 
    t.tgname as trigger_name,
    p.proname as function_name
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE t.tgrelid = 'sales_invoices'::regclass
  AND NOT t.tgisinternal
  AND t.tgtype::integer & 8 = 8;

-- Should only show the AFTER DELETE trigger: trg_delete_invoice_cascade_pega
