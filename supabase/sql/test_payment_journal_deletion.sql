-- ============================================================================
-- Manual Test Script: Payment Journal Entry Deletion
-- ============================================================================
-- Use this script to manually test the payment deletion workflow
-- Run these queries step by step to verify the fix is working
-- ============================================================================

-- ============================================================================
-- SETUP: Create a test invoice and payment
-- ============================================================================

-- Step 1: Check if we have any confirmed invoices to test with
SELECT 
  '📋 Available confirmed invoices for testing:' as info,
  id,
  invoice_number,
  customer_name,
  total,
  balance,
  status
FROM sales_invoices
WHERE status = 'confirmed' 
  AND balance > 0
ORDER BY created_at DESC
LIMIT 5;

-- ============================================================================
-- If you need to create a test invoice, use these queries:
-- ============================================================================
/*
-- Create a test customer if needed
INSERT INTO customers (name, email, rut, phone, address)
VALUES ('Test Customer', 'test@example.com', '11111111-1', '912345678', 'Test Address')
RETURNING id;

-- Create a test invoice (replace customer_id with actual ID)
INSERT INTO sales_invoices (
  invoice_number, customer_id, customer_name, date, status, 
  subtotal, tax, total, paid_amount, balance
)
VALUES (
  'TEST-' || EXTRACT(EPOCH FROM NOW())::TEXT,
  'YOUR_CUSTOMER_ID_HERE',
  'Test Customer',
  NOW(),
  'confirmed',
  100000,
  19000,
  119000,
  0,
  119000
)
RETURNING id, invoice_number;

-- Add a line item to the invoice
INSERT INTO sales_invoice_items (invoice_id, product_name, quantity, unit_price, total)
VALUES ('YOUR_INVOICE_ID_HERE', 'Test Product', 1, 100000, 100000);
*/

-- ============================================================================
-- TEST PART 1: Create a payment and verify journal entry is created
-- ============================================================================

-- Step 2: Create a payment (replace with your invoice ID)
DO $$
DECLARE
  v_invoice_id UUID := 'YOUR_INVOICE_ID_HERE'; -- ⚠️ REPLACE THIS
  v_payment_id UUID;
BEGIN
  -- Create payment
  INSERT INTO sales_payments (
    invoice_id,
    amount,
    method,
    date,
    reference,
    notes
  )
  VALUES (
    v_invoice_id,
    119000,
    'transfer',
    NOW(),
    'TEST-PAYMENT-001',
    'Test payment for journal entry deletion'
  )
  RETURNING id INTO v_payment_id;

  RAISE NOTICE '✅ Created test payment with ID: %', v_payment_id;
  RAISE NOTICE 'Use this ID in the next queries';
END $$;

-- Step 3: Verify payment was created
SELECT 
  '✅ Payment created:' as step,
  id,
  invoice_id,
  amount,
  method,
  reference
FROM sales_payments
WHERE reference = 'TEST-PAYMENT-001'
ORDER BY created_at DESC
LIMIT 1;

-- Step 4: Verify payment journal entry was created
SELECT 
  '✅ Payment journal entry created:' as step,
  je.id,
  je.entry_number,
  je.description,
  je.source_module,
  je.source_reference as payment_id,
  je.total_debit,
  je.total_credit
FROM journal_entries je
WHERE je.source_module = 'sales_payments'
  AND je.source_reference IN (
    SELECT id::text FROM sales_payments WHERE reference = 'TEST-PAYMENT-001'
  );

-- Step 5: Verify journal lines were created
SELECT 
  '✅ Payment journal lines:' as step,
  jl.id,
  jl.account_code,
  jl.account_name,
  jl.debit_amount,
  jl.credit_amount,
  jl.description
FROM journal_lines jl
WHERE jl.entry_id IN (
  SELECT je.id FROM journal_entries je
  WHERE je.source_module = 'sales_payments'
    AND je.source_reference IN (
      SELECT id::text FROM sales_payments WHERE reference = 'TEST-PAYMENT-001'
    )
);

-- Step 6: Verify invoice status updated to 'paid'
SELECT 
  '✅ Invoice status:' as step,
  id,
  invoice_number,
  status,
  paid_amount,
  balance
FROM sales_invoices
WHERE id IN (
  SELECT invoice_id FROM sales_payments WHERE reference = 'TEST-PAYMENT-001'
);

-- ============================================================================
-- TEST PART 2: Delete the payment and verify journal entry is deleted
-- ============================================================================

-- Step 7: Delete the payment
DELETE FROM sales_payments
WHERE reference = 'TEST-PAYMENT-001'
RETURNING id, invoice_id, amount, reference;

-- ⚠️ WAIT FOR THIS TO COMPLETE BEFORE RUNNING NEXT QUERIES ⚠️

-- Step 8: Verify payment was deleted
SELECT 
  CASE 
    WHEN COUNT(*) = 0 THEN '✅ Payment deleted successfully'
    ELSE '❌ Payment still exists!'
  END as result
FROM sales_payments
WHERE reference = 'TEST-PAYMENT-001';

-- Step 9: Verify payment journal entry was DELETED (THIS IS THE KEY TEST!)
SELECT 
  CASE 
    WHEN COUNT(*) = 0 THEN '✅✅✅ Payment journal entry DELETED successfully! Fix is working!'
    ELSE '❌❌❌ Payment journal entry STILL EXISTS! Fix did not work!'
  END as result,
  COUNT(*) as orphaned_entries
FROM journal_entries je
WHERE je.source_module = 'sales_payments'
  AND je.source_reference NOT IN (SELECT id::text FROM sales_payments);

-- Step 10: Verify invoice status reverted to 'confirmed'
SELECT 
  '✅ Invoice status after payment deletion:' as step,
  id,
  invoice_number,
  status,
  paid_amount,
  balance,
  CASE 
    WHEN status = 'confirmed' THEN '✅ Status correctly reverted to confirmed'
    WHEN status = 'paid' THEN '❌ Status still paid (should be confirmed)'
    ELSE '⚠️ Unexpected status'
  END as status_check
FROM sales_invoices
WHERE invoice_number LIKE 'TEST-%'
ORDER BY created_at DESC
LIMIT 1;

-- ============================================================================
-- VERIFICATION: Check for any orphaned payment journal entries
-- ============================================================================

-- Step 11: List all orphaned payment journal entries (should be empty!)
SELECT 
  '🔍 Orphaned payment journal entries:' as info,
  COUNT(*) as total_orphaned,
  ARRAY_AGG(je.entry_number) as orphaned_entry_numbers
FROM journal_entries je
WHERE je.source_module = 'sales_payments'
  AND NOT EXISTS (
    SELECT 1 FROM sales_payments sp 
    WHERE sp.id::text = je.source_reference
  );

-- Step 12: Show all recent payment journal entries
SELECT 
  '📋 Recent payment journal entries:' as info,
  je.entry_number,
  je.description,
  je.date,
  sp.reference as payment_reference,
  si.invoice_number,
  si.status as invoice_status,
  CASE 
    WHEN sp.id IS NULL THEN '❌ ORPHANED'
    ELSE '✅ OK'
  END as validation_status
FROM journal_entries je
LEFT JOIN sales_payments sp ON sp.id::text = je.source_reference
LEFT JOIN sales_invoices si ON si.id = sp.invoice_id
WHERE je.source_module = 'sales_payments'
ORDER BY je.created_at DESC
LIMIT 10;

-- ============================================================================
-- CLEANUP: Remove test data (optional)
-- ============================================================================
/*
-- Uncomment to clean up test data

-- Delete test invoice and related records (cascade will handle children)
DELETE FROM sales_invoices 
WHERE invoice_number LIKE 'TEST-%';

-- Delete test customer
DELETE FROM customers 
WHERE email = 'test@example.com';
*/

-- ============================================================================
-- SUMMARY
-- ============================================================================
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'TEST SUMMARY';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Expected Results:';
  RAISE NOTICE '1. ✅ Payment created successfully';
  RAISE NOTICE '2. ✅ Payment journal entry created';
  RAISE NOTICE '3. ✅ Invoice status = paid';
  RAISE NOTICE '4. ✅ Payment deleted successfully';
  RAISE NOTICE '5. ✅ Payment journal entry DELETED (not orphaned)';
  RAISE NOTICE '6. ✅ Invoice status = confirmed (reverted)';
  RAISE NOTICE '7. ✅ No orphaned payment journal entries';
  RAISE NOTICE '';
  RAISE NOTICE 'If all checks pass, the fix is working correctly!';
  RAISE NOTICE '========================================';
END $$;
