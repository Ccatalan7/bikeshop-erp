-- =====================================================
-- QUICK FIX: Journal Entry Not Deleted on Revert
-- =====================================================
-- Run this if journal entries are NOT being deleted
-- when you revert from Confirmada → Enviada
-- =====================================================

-- Step 1: Check if trigger exists and is enabled
SELECT 
  tgname AS trigger_name,
  tgenabled AS enabled_status,
  CASE tgenabled
    WHEN 'O' THEN '✅ Enabled'
    WHEN 'D' THEN '❌ DISABLED'
    ELSE '⚠️  Unknown'
  END AS status_text
FROM pg_trigger
WHERE tgname = 'purchase_invoice_change_trigger';

-- Step 2: Check if function exists
SELECT 
  CASE 
    WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'handle_purchase_invoice_change')
    THEN '✅ Function exists'
    ELSE '❌ Function NOT FOUND - Run purchase_invoice_triggers.sql'
  END AS function_status;

-- Step 3: Check entry_type values (must match trigger DELETE condition)
SELECT 
  'Current entry_type values in database:' AS info;

SELECT 
  entry_type,
  COUNT(*) AS count,
  CASE 
    WHEN entry_type IN ('purchase_invoice', 'purchase_confirmation') 
    THEN '✅ Will be deleted by trigger'
    WHEN entry_type IS NULL
    THEN '❌ NULL - needs fix'
    ELSE '❌ Wrong value - needs fix'
  END AS deletion_status
FROM journal_entries
WHERE source_module = 'purchase_invoices'
GROUP BY entry_type;

-- Step 4: Fix NULL or wrong entry_type values
UPDATE journal_entries
SET entry_type = CASE 
  WHEN pi.prepayment_model THEN 'purchase_confirmation'
  ELSE 'purchase_invoice'
END
FROM purchase_invoices pi
WHERE journal_entries.source_module = 'purchase_invoices'
  AND journal_entries.source_reference = pi.id::TEXT
  AND journal_entries.entry_type NOT IN ('purchase_invoice', 'purchase_confirmation', 'purchase_receipt', 'payment');

-- Step 5: Reinstall trigger (fixes most issues)
DROP TRIGGER IF EXISTS purchase_invoice_change_trigger ON purchase_invoices;

CREATE TRIGGER purchase_invoice_change_trigger
  AFTER UPDATE OF status
  ON purchase_invoices
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION handle_purchase_invoice_change();

-- Step 6: Ensure foreign key has CASCADE delete
ALTER TABLE journal_lines
DROP CONSTRAINT IF EXISTS journal_lines_journal_entry_id_fkey;

ALTER TABLE journal_lines
ADD CONSTRAINT journal_lines_journal_entry_id_fkey
FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE CASCADE;

-- Step 7: Clean up orphaned entries (sent invoices that still have journal entries)
DO $$
DECLARE
  v_deleted_count INT;
BEGIN
  WITH deleted AS (
    DELETE FROM journal_entries
    WHERE id IN (
      SELECT je.id
      FROM purchase_invoices pi
      JOIN journal_entries je ON je.source_reference = pi.id::TEXT
      WHERE pi.status = 'sent'
        AND je.source_module = 'purchase_invoices'
        AND je.entry_type IN ('purchase_invoice', 'purchase_confirmation')
    )
    RETURNING id
  )
  SELECT COUNT(*) INTO v_deleted_count FROM deleted;
  
  IF v_deleted_count > 0 THEN
    RAISE NOTICE 'Deleted % orphaned journal entries', v_deleted_count;
  ELSE
    RAISE NOTICE 'No orphaned entries found (good!)';
  END IF;
END $$;

-- Step 8: Test the trigger
DO $$
DECLARE
  v_test_invoice_id UUID;
  v_before INT;
  v_after INT;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'TESTING TRIGGER';
  RAISE NOTICE '========================================';
  
  -- Find a confirmed invoice
  SELECT id INTO v_test_invoice_id
  FROM purchase_invoices
  WHERE status = 'confirmed'
  LIMIT 1;
  
  IF v_test_invoice_id IS NULL THEN
    RAISE NOTICE '⚠️  No confirmed invoices to test with';
    RETURN;
  END IF;
  
  -- Count entries before
  SELECT COUNT(*) INTO v_before
  FROM journal_entries
  WHERE source_reference = v_test_invoice_id::TEXT
    AND source_module = 'purchase_invoices';
  
  RAISE NOTICE 'Test invoice: %', v_test_invoice_id;
  RAISE NOTICE 'Journal entries BEFORE: %', v_before;
  
  IF v_before = 0 THEN
    RAISE NOTICE '⚠️  No entries to delete (invoice may not be properly confirmed)';
    RETURN;
  END IF;
  
  -- Revert to sent (should trigger DELETE)
  UPDATE purchase_invoices
  SET status = 'sent'
  WHERE id = v_test_invoice_id;
  
  -- Count after
  SELECT COUNT(*) INTO v_after
  FROM journal_entries
  WHERE source_reference = v_test_invoice_id::TEXT
    AND source_module = 'purchase_invoices';
  
  RAISE NOTICE 'Journal entries AFTER: %', v_after;
  RAISE NOTICE '';
  
  IF v_after = 0 THEN
    RAISE NOTICE '✅ ✅ ✅  SUCCESS! Trigger is working!';
    RAISE NOTICE '';
    RAISE NOTICE 'Reverting test invoice back to confirmed...';
    
    -- Restore for further use
    UPDATE purchase_invoices
    SET status = 'confirmed', confirmed_date = NOW()
    WHERE id = v_test_invoice_id;
    
    RAISE NOTICE '✅ Test complete. Invoice restored.';
  ELSE
    RAISE WARNING '❌ FAILED! Entries still exist after revert!';
    RAISE WARNING '';
    RAISE WARNING 'Check the function definition:';
    RAISE WARNING 'SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = ''handle_purchase_invoice_change'';';
  END IF;
END $$;

-- Step 9: Final verification
SELECT 
  '========================================' AS separator,
  'FINAL STATUS' AS title,
  '========================================' AS separator2;

SELECT 
  CASE 
    WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'purchase_invoice_change_trigger')
    THEN '✅ Trigger installed'
    ELSE '❌ Trigger missing'
  END AS trigger_status,
  
  CASE 
    WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'handle_purchase_invoice_change')
    THEN '✅ Function exists'
    ELSE '❌ Function missing'
  END AS function_status,
  
  (
    SELECT COUNT(*)
    FROM purchase_invoices pi
    JOIN journal_entries je ON je.source_reference = pi.id::TEXT
    WHERE pi.status = 'sent'
      AND je.source_module = 'purchase_invoices'
  ) AS orphaned_entries_count,
  
  CASE 
    WHEN (
      SELECT COUNT(*)
      FROM purchase_invoices pi
      JOIN journal_entries je ON je.source_reference = pi.id::TEXT
      WHERE pi.status = 'sent'
        AND je.source_module = 'purchase_invoices'
    ) = 0
    THEN '✅ No orphaned entries'
    ELSE '⚠️  Orphaned entries exist'
  END AS cleanup_status;

-- Final message
DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ QUICK FIX COMPLETE';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Next steps:';
  RAISE NOTICE '  1. Check the status table above';
  RAISE NOTICE '  2. Try reverting an invoice in the app';
  RAISE NOTICE '  3. Verify journal entry is deleted';
  RAISE NOTICE '';
  RAISE NOTICE 'If still not working:';
  RAISE NOTICE '  - Check Supabase logs for errors';
  RAISE NOTICE '  - Run verify_purchase_invoice_triggers.sql';
  RAISE NOTICE '  - See PURCHASE_WORKFLOW_TROUBLESHOOTING.md';
END $$;
