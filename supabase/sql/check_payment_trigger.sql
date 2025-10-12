-- ============================================================================
-- Diagnostic: Check if Payment Trigger Exists
-- ============================================================================

-- 1. Check if the trigger exists
SELECT 
  t.tgname as trigger_name,
  c.relname as table_name,
  p.proname as function_name,
  pg_get_triggerdef(t.oid) as trigger_definition
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE n.nspname = 'public'
  AND c.relname = 'sales_payments'
ORDER BY t.tgname;

-- 2. Check if the function exists
SELECT 
  proname as function_name,
  pg_get_functiondef(oid) as function_definition
FROM pg_proc
WHERE proname IN ('handle_sales_payment_change', 'create_sales_payment_journal_entry', 'delete_sales_payment_journal_entry')
ORDER BY proname;

-- 3. Check all triggers on sales_payments table
SELECT 
  tgname,
  tgenabled,
  pg_get_triggerdef(oid) as definition
FROM pg_trigger
WHERE tgrelid = 'public.sales_payments'::regclass;
