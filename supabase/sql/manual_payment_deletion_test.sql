-- ============================================================================
-- Test: Manual Payment Deletion to See Trigger Logs
-- ============================================================================

-- Enable notices
SET client_min_messages TO NOTICE;

-- 1. Show current payments
SELECT 
  'Current payments:' as info,
  id,
  invoice_id,
  amount,
  method
FROM sales_payments
ORDER BY created_at DESC;

-- 2. Show current payment journal entries
SELECT 
  'Current payment journal entries:' as info,
  je.id,
  je.entry_number,
  je.description,
  je.source_reference as payment_id
FROM journal_entries je
WHERE source_module = 'sales_payments'
ORDER BY created_at DESC;

-- 3. Now delete the most recent payment (THIS WILL TRIGGER THE LOGS)
-- The trigger should fire and you'll see all the RAISE NOTICE messages below
DO $$
DECLARE
  v_payment_id UUID;
BEGIN
  -- Get the most recent payment
  SELECT id INTO v_payment_id
  FROM sales_payments
  ORDER BY created_at DESC
  LIMIT 1;
  
  IF v_payment_id IS NOT NULL THEN
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'About to delete payment: %', v_payment_id;
    RAISE NOTICE '==========================================';
    
    -- Delete it (this will trigger the trigger!)
    DELETE FROM sales_payments WHERE id = v_payment_id;
    
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Payment deleted. Check above for trigger logs!';
    RAISE NOTICE '==========================================';
  ELSE
    RAISE NOTICE 'No payments found to delete';
  END IF;
END $$;

-- 4. Check if journal entry was deleted
SELECT 
  'Remaining payment journal entries after deletion:' as info,
  COUNT(*) as count
FROM journal_entries
WHERE source_module = 'sales_payments';
