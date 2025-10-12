-- ============================================================================
-- Diagnostic: Check Payment Journal Entries
-- ============================================================================

-- 1. Check all sales payment journal entries
SELECT 
  je.id,
  je.entry_number,
  je.date,
  je.description,
  je.source_module,
  je.source_reference,
  je.total_debit,
  je.total_credit
FROM journal_entries je
WHERE source_module = 'sales_payments'
ORDER BY je.created_at DESC;

-- 2. Check all sales payments
SELECT 
  id,
  invoice_id,
  amount,
  method,
  date,
  created_at
FROM sales_payments
ORDER BY created_at DESC;

-- 3. Check if payment IDs match journal entry references
SELECT 
  sp.id as payment_id,
  sp.amount,
  sp.method,
  je.id as journal_entry_id,
  je.entry_number,
  je.source_reference
FROM sales_payments sp
LEFT JOIN journal_entries je 
  ON je.source_module = 'sales_payments' 
  AND je.source_reference = sp.id::text
ORDER BY sp.created_at DESC;

-- 4. Find orphaned payment journal entries (no matching payment)
SELECT 
  je.id,
  je.entry_number,
  je.description,
  je.source_reference as payment_id_reference,
  je.date
FROM journal_entries je
WHERE je.source_module = 'sales_payments'
  AND NOT EXISTS (
    SELECT 1 FROM sales_payments sp 
    WHERE sp.id::text = je.source_reference
  );
