-- ============================================================================
-- Diagnostic: Check Current State of consume_sales_invoice_inventory Function
-- ============================================================================
-- This query will show you the current definition of the function
-- to verify if the fix has been applied
-- ============================================================================

-- Check the function source code
SELECT 
  proname AS function_name,
  pg_get_functiondef(oid) AS function_definition
FROM pg_proc
WHERE proname = 'consume_sales_invoice_inventory'
  AND pronamespace = 'public'::regnamespace;

-- ============================================================================
-- What to look for:
-- ============================================================================
-- In the function definition, you should see:
--
-- ✅ CORRECT (after fix):
--   IF v_status = ANY (ARRAY[
--     'draft', 'borrador',
--     'sent', 'enviado', 'enviada', 'issued', 'emitido', 'emitida',  ← HAS "sent"
--     'cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada'
--   ]) THEN
--
-- ❌ WRONG (before fix):
--   if v_status = any (array[
--     'draft','borrador','cancelled','cancelado','cancelada','anulado','anulada'  ← MISSING "sent"
--   ]) then
--
-- If you see the WRONG version, the fix SQL hasn't been applied yet!
-- ============================================================================
