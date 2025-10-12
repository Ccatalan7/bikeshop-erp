-- ============================================================================
-- Test: Manually Trigger Payment Deletion to See What Happens
-- ============================================================================

-- First, create a test payment to delete
DO $$
DECLARE
  v_test_payment_id UUID;
  v_test_invoice_id UUID;
BEGIN
  -- Get an existing invoice
  SELECT id INTO v_test_invoice_id
  FROM sales_invoices
  WHERE status = 'confirmed'
  LIMIT 1;
  
  IF v_test_invoice_id IS NULL THEN
    RAISE NOTICE 'No confirmed invoice found to test with';
    RETURN;
  END IF;
  
  -- Create a test payment
  INSERT INTO sales_payments (id, invoice_id, amount, method, date)
  VALUES (
    gen_random_uuid(),
    v_test_invoice_id,
    1000,
    'cash',
    NOW()
  )
  RETURNING id INTO v_test_payment_id;
  
  RAISE NOTICE 'Created test payment with ID: %', v_test_payment_id;
  
  -- Wait a moment
  PERFORM pg_sleep(1);
  
  -- Check if journal entry was created
  IF EXISTS (
    SELECT 1 FROM journal_entries 
    WHERE source_module = 'sales_payments' 
    AND source_reference = v_test_payment_id::text
  ) THEN
    RAISE NOTICE 'Journal entry was created successfully!';
  ELSE
    RAISE NOTICE 'WARNING: Journal entry was NOT created!';
  END IF;
  
  -- Now delete the payment
  RAISE NOTICE 'Deleting test payment...';
  DELETE FROM sales_payments WHERE id = v_test_payment_id;
  
  -- Check if journal entry was deleted
  IF EXISTS (
    SELECT 1 FROM journal_entries 
    WHERE source_module = 'sales_payments' 
    AND source_reference = v_test_payment_id::text
  ) THEN
    RAISE NOTICE 'ERROR: Journal entry still exists after payment deletion!';
  ELSE
    RAISE NOTICE 'SUCCESS: Journal entry was deleted!';
  END IF;
END $$;

-- Show the results
SELECT 
  'Test Complete' as status,
  (SELECT COUNT(*) FROM sales_payments) as remaining_payments,
  (SELECT COUNT(*) FROM journal_entries WHERE source_module = 'sales_payments') as remaining_payment_journal_entries;
