-- ============================================================================
-- Test: Manually Delete Payment Journal Entry
-- ============================================================================

-- First, let's see what payment journal entries exist
SELECT 
  je.id as journal_entry_id,
  je.entry_number,
  je.description,
  je.source_reference as payment_id,
  je.total_debit,
  je.created_at
FROM journal_entries je
WHERE source_module = 'sales_payments'
ORDER BY created_at DESC;

-- Now let's see what payments exist
SELECT 
  id as payment_id,
  invoice_id,
  amount,
  method,
  created_at
FROM sales_payments
ORDER BY created_at DESC;

-- Find orphaned journal entries (journal entry exists but payment doesn't)
-- These are the ones that should have been deleted
SELECT 
  je.id as orphaned_journal_entry_id,
  je.entry_number,
  je.description,
  je.source_reference as missing_payment_id,
  je.total_debit,
  je.created_at,
  'This journal entry should have been deleted!' as note
FROM journal_entries je
WHERE je.source_module = 'sales_payments'
  AND NOT EXISTS (
    SELECT 1 
    FROM sales_payments sp 
    WHERE sp.id::text = je.source_reference
  );

-- If you want to manually clean up orphaned entries, uncomment this:
-- DELETE FROM journal_entries
-- WHERE source_module = 'sales_payments'
--   AND NOT EXISTS (
--     SELECT 1 
--     FROM sales_payments sp 
--     WHERE sp.id::text = source_reference
--   );
