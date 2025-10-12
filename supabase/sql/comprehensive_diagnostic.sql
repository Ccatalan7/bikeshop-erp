-- ============================================================================
-- Comprehensive Diagnostic: Payment and Journal Entry State
-- ============================================================================

-- 1. Count of payments vs payment journal entries
SELECT 
  'Payments' as type,
  COUNT(*) as count
FROM sales_payments
UNION ALL
SELECT 
  'Payment Journal Entries' as type,
  COUNT(*) as count
FROM journal_entries
WHERE source_module = 'sales_payments';

-- 2. All journal entries (not just payments)
SELECT 
  je.id,
  je.entry_number,
  je.date,
  je.description,
  je.source_module,
  je.source_reference,
  je.status,
  je.total_debit,
  je.total_credit,
  je.created_at
FROM journal_entries je
ORDER BY je.created_at DESC
LIMIT 20;

-- 3. Check sales invoices status
SELECT 
  id,
  invoice_number,
  customer_name,
  status,
  total,
  paid_amount,
  balance,
  updated_at
FROM sales_invoices
ORDER BY updated_at DESC;

-- 4. Check if trigger is enabled
SELECT 
  t.tgname as trigger_name,
  CASE t.tgenabled 
    WHEN 'O' THEN 'Enabled'
    WHEN 'D' THEN 'Disabled'
    WHEN 'R' THEN 'Replica'
    WHEN 'A' THEN 'Always'
    ELSE 'Unknown'
  END as status,
  pg_get_triggerdef(t.oid) as definition
FROM pg_trigger t
WHERE t.tgrelid = 'public.sales_payments'::regclass
  AND t.tgname LIKE '%payment%';
