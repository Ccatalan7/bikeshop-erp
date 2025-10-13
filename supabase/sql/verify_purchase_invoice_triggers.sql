-- =====================================================
-- PURCHASE INVOICE WORKFLOW VERIFICATION & FIX
-- =====================================================
-- This script verifies the trigger is installed correctly
-- and tests the complete workflow with DELETE-based reversals
-- =====================================================

-- =====================================================
-- PART 1: Verify Trigger Installation
-- =====================================================

DO $$
DECLARE
  v_trigger_exists BOOLEAN;
  v_function_exists BOOLEAN;
BEGIN
  -- Check if main trigger exists
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'purchase_invoice_change_trigger'
  ) INTO v_trigger_exists;
  
  -- Check if main function exists
  SELECT EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'handle_purchase_invoice_change'
  ) INTO v_function_exists;
  
  IF v_trigger_exists AND v_function_exists THEN
    RAISE NOTICE '✅ Trigger and function are installed correctly';
  ELSE
    IF NOT v_trigger_exists THEN
      RAISE WARNING '❌ Trigger "purchase_invoice_change_trigger" NOT FOUND!';
      RAISE WARNING '   Run: purchase_invoice_triggers.sql';
    END IF;
    IF NOT v_function_exists THEN
      RAISE WARNING '❌ Function "handle_purchase_invoice_change" NOT FOUND!';
      RAISE WARNING '   Run: purchase_invoice_triggers.sql';
    END IF;
  END IF;
END $$;

-- =====================================================
-- PART 2: Check Journal Entry Deletion Logic
-- =====================================================

-- Show the current trigger definition
SELECT 
  p.proname AS function_name,
  pg_get_functiondef(p.oid) AS function_definition
FROM pg_proc p
WHERE p.proname = 'handle_purchase_invoice_change';

-- =====================================================
-- PART 3: Manual Test - Confirmada → Enviada Reversal
-- =====================================================

DO $$
DECLARE
  v_test_invoice_id UUID;
  v_journal_count_before INT;
  v_journal_count_after INT;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'TESTING: Confirmada → Enviada Reversal';
  RAISE NOTICE '========================================';
  
  -- Find a confirmed invoice (or create a test one)
  SELECT id INTO v_test_invoice_id
  FROM purchase_invoices
  WHERE status = 'confirmed'
  LIMIT 1;
  
  IF v_test_invoice_id IS NULL THEN
    RAISE NOTICE '⚠️  No confirmed invoices found to test';
    RAISE NOTICE '   Please confirm an invoice first, then re-run this test';
    RETURN;
  END IF;
  
  -- Count journal entries BEFORE revert
  SELECT COUNT(*) INTO v_journal_count_before
  FROM journal_entries
  WHERE source_module = 'purchase_invoices'
    AND source_reference = v_test_invoice_id::TEXT
    AND entry_type IN ('purchase_invoice', 'purchase_confirmation');
  
  RAISE NOTICE '';
  RAISE NOTICE 'Test Invoice ID: %', v_test_invoice_id;
  RAISE NOTICE 'Journal Entries BEFORE revert: %', v_journal_count_before;
  
  IF v_journal_count_before = 0 THEN
    RAISE WARNING '⚠️  No journal entries found for this invoice!';
    RAISE WARNING '   The invoice may not have been properly confirmed';
    RETURN;
  END IF;
  
  -- Perform the revert (this should trigger the DELETE)
  UPDATE purchase_invoices
  SET status = 'sent', updated_at = NOW()
  WHERE id = v_test_invoice_id;
  
  -- Count journal entries AFTER revert
  SELECT COUNT(*) INTO v_journal_count_after
  FROM journal_entries
  WHERE source_module = 'purchase_invoices'
    AND source_reference = v_test_invoice_id::TEXT
    AND entry_type IN ('purchase_invoice', 'purchase_confirmation');
  
  RAISE NOTICE 'Journal Entries AFTER revert: %', v_journal_count_after;
  RAISE NOTICE '';
  
  IF v_journal_count_after = 0 THEN
    RAISE NOTICE '✅ ✅ ✅  SUCCESS! Journal entry was deleted!';
    RAISE NOTICE '';
    RAISE NOTICE 'The trigger is working correctly!';
    
    -- Restore the invoice to confirmed for further testing
    UPDATE purchase_invoices
    SET status = 'confirmed', confirmed_date = NOW(), updated_at = NOW()
    WHERE id = v_test_invoice_id;
    
    RAISE NOTICE '';
    RAISE NOTICE '(Invoice restored to "confirmed" status for you)';
  ELSE
    RAISE WARNING '❌ FAILED! Journal entry was NOT deleted!';
    RAISE WARNING '';
    RAISE WARNING 'Possible issues:';
    RAISE WARNING '  1. Trigger not installed (run purchase_invoice_triggers.sql)';
    RAISE WARNING '  2. Trigger disabled';
    RAISE WARNING '  3. Different entry_type value than expected';
    
    -- Show the actual entry_type values
    RAISE WARNING '';
    RAISE WARNING 'Actual entry_type values found:';
    FOR rec IN 
      SELECT entry_type, entry_number, notes
      FROM journal_entries
      WHERE source_module = 'purchase_invoices'
        AND source_reference = v_test_invoice_id::TEXT
    LOOP
      RAISE WARNING '  - entry_type: %, entry_number: %', rec.entry_type, rec.entry_number;
    END LOOP;
  END IF;
END $$;

-- =====================================================
-- PART 4: Verify Entry Types Match
-- =====================================================

SELECT 
  'Check if entry_type values match trigger DELETE condition:' AS info;

SELECT 
  COUNT(*) AS count,
  entry_type,
  CASE 
    WHEN entry_type IN ('purchase_invoice', 'purchase_confirmation') 
    THEN '✅ Will be deleted'
    ELSE '❌ Will NOT be deleted'
  END AS will_be_deleted
FROM journal_entries
WHERE source_module = 'purchase_invoices'
GROUP BY entry_type
ORDER BY count DESC;

-- =====================================================
-- PART 5: Show All Journal Entries for Purchase Invoices
-- =====================================================

SELECT 
  '=== All Purchase Invoice Journal Entries ===' AS separator;

SELECT 
  je.entry_number,
  je.entry_type,
  je.status,
  je.notes,
  pi.invoice_number,
  pi.status AS invoice_status,
  pi.prepayment_model,
  je.created_at
FROM journal_entries je
JOIN purchase_invoices pi ON je.source_reference = pi.id::TEXT
WHERE je.source_module = 'purchase_invoices'
ORDER BY je.created_at DESC
LIMIT 20;

-- =====================================================
-- PART 6: Fix Script (if needed)
-- =====================================================

-- If the test above shows that journal entries are NOT being deleted,
-- run this to ensure the trigger is properly installed:

/*
-- Uncomment and run if trigger is broken:

DROP TRIGGER IF EXISTS purchase_invoice_change_trigger ON purchase_invoices;

CREATE TRIGGER purchase_invoice_change_trigger
  AFTER UPDATE OF status
  ON purchase_invoices
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION handle_purchase_invoice_change();

-- Then test again
*/

-- =====================================================
-- SUMMARY
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'VERIFICATION COMPLETE';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE '📋 What to check:';
  RAISE NOTICE '  1. Trigger exists: purchase_invoice_change_trigger';
  RAISE NOTICE '  2. Function exists: handle_purchase_invoice_change';
  RAISE NOTICE '  3. Journal entries deleted when reverting Confirmada → Enviada';
  RAISE NOTICE '  4. entry_type values match: purchase_invoice OR purchase_confirmation';
  RAISE NOTICE '';
  RAISE NOTICE '🔍 If journal entries are NOT being deleted:';
  RAISE NOTICE '  1. Check if trigger is enabled';
  RAISE NOTICE '  2. Check PostgreSQL logs for errors';
  RAISE NOTICE '  3. Verify entry_type values match exactly';
  RAISE NOTICE '  4. Re-run purchase_invoice_triggers.sql file';
END $$;
