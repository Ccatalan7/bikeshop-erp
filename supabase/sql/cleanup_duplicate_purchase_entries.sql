-- =====================================================
-- Cleanup Duplicate Purchase Invoice Journal Entries
-- =====================================================
-- This script removes duplicate journal entries created
-- for purchase invoices before the fix was applied.
-- =====================================================

-- Step 1: Identify duplicates
SELECT 
  source_reference,
  COUNT(*) as entry_count,
  STRING_AGG(entry_number, ', ') as entry_numbers,
  STRING_AGG(id::text, ', ') as entry_ids
FROM journal_entries
WHERE source_module = 'purchase_invoice'
GROUP BY source_reference
HAVING COUNT(*) > 1
ORDER BY source_reference;

-- Step 2: Delete duplicate entries (keeps the one with 'COMP-' prefix)
-- Run this after reviewing the results above
DO $$
DECLARE
  dup_record RECORD;
  keep_id UUID;
  delete_id UUID;
BEGIN
  -- Find all purchase invoices with duplicate entries
  FOR dup_record IN
    SELECT source_reference
    FROM journal_entries
    WHERE source_module = 'purchase_invoice'
    GROUP BY source_reference
    HAVING COUNT(*) > 1
  LOOP
    -- Keep the entry with 'COMP-' prefix (created by trigger)
    SELECT id INTO keep_id
    FROM journal_entries
    WHERE source_module = 'purchase_invoice'
      AND source_reference = dup_record.source_reference
      AND entry_number LIKE 'COMP-%'
    LIMIT 1;
    
    -- If no COMP- entry, keep the oldest one
    IF keep_id IS NULL THEN
      SELECT id INTO keep_id
      FROM journal_entries
      WHERE source_module = 'purchase_invoice'
        AND source_reference = dup_record.source_reference
      ORDER BY created_at ASC
      LIMIT 1;
    END IF;
    
    RAISE NOTICE 'Keeping entry % for invoice %', keep_id, dup_record.source_reference;
    
    -- Delete all other entries for this invoice
    DELETE FROM journal_lines
    WHERE entry_id IN (
      SELECT id FROM journal_entries
      WHERE source_module = 'purchase_invoice'
        AND source_reference = dup_record.source_reference
        AND id != keep_id
    );
    
    DELETE FROM journal_entries
    WHERE source_module = 'purchase_invoice'
      AND source_reference = dup_record.source_reference
      AND id != keep_id;
      
    RAISE NOTICE 'Deleted duplicate entries for invoice %', dup_record.source_reference;
  END LOOP;
END;
$$;

-- Step 3: Verify cleanup
SELECT 
  source_reference,
  COUNT(*) as entry_count,
  STRING_AGG(entry_number, ', ') as entry_numbers
FROM journal_entries
WHERE source_module = 'purchase_invoice'
GROUP BY source_reference
ORDER BY source_reference;

-- Step 4: Show remaining purchase invoice entries
SELECT
  je.entry_number,
  je.date,
  je.description,
  je.source_reference,
  (SELECT SUM(debit_amount) FROM journal_lines WHERE entry_id = je.id) as total_debit,
  (SELECT SUM(credit_amount) FROM journal_lines WHERE entry_id = je.id) as total_credit
FROM journal_entries je
WHERE je.source_module = 'purchase_invoice'
ORDER BY je.date DESC;

-- =====================================================
-- IMPORTANT NOTES:
-- =====================================================
-- 1. This script will DELETE duplicate journal entries
-- 2. It keeps entries with 'COMP-' prefix (created by trigger)
-- 3. If no COMP- entry exists, it keeps the oldest one
-- 4. Review Step 1 results before running Step 2
-- 5. Step 2 is wrapped in DO block and executes automatically
-- =====================================================
