-- ============================================================================
-- Diagnostic: Check BOTH the trigger AND the function
-- ============================================================================

-- 1. Check the trigger definition
SELECT 
  tgname AS trigger_name,
  pg_get_triggerdef(oid) AS trigger_definition
FROM pg_trigger
WHERE tgname = 'trg_sales_invoice_changes';

-- Look for: Does it call handle_sales_invoice_change()?

-- 2. Check the trigger function definition  
SELECT pg_get_functiondef(oid)
FROM pg_proc 
WHERE proname = 'handle_sales_invoice_change';

-- Look for the v_non_posted array - does it include 'sent'?

-- 3. Check the consume function definition
SELECT pg_get_functiondef(oid)
FROM pg_proc 
WHERE proname = 'consume_sales_invoice_inventory';

-- Look for: Does it skip 'sent', 'enviado', 'enviada'?

-- ============================================================================
-- Expected Results:
-- ============================================================================
-- All three should have 'sent' in their non-posted/skip lists
-- If ANY of them is missing 'sent', that's the problem
-- ============================================================================
