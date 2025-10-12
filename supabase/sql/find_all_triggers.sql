-- ============================================================================
-- Find ALL triggers on sales_invoices table
-- ============================================================================

SELECT 
  t.tgname AS trigger_name,
  p.proname AS function_name,
  pg_get_triggerdef(t.oid) AS trigger_definition
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE t.tgrelid = 'public.sales_invoices'::regclass
ORDER BY t.tgname;

-- This will show ALL triggers that fire on sales_invoices
-- Look for multiple triggers that might be conflicting!
