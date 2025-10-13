-- =====================================================
-- REAL-TIME TRIGGER TEST
-- =====================================================
-- Run this WHILE you test in the Flutter app
-- to see exactly what's happening
-- =====================================================

-- Step 1: Find your current confirmed invoice
SELECT 
  id,
  invoice_number,
  status,
  prepayment_model,
  supplier_name
FROM purchase_invoices
WHERE status = 'confirmed'
ORDER BY created_at DESC
LIMIT 5;

-- Note the ID of the invoice you want to test
-- Replace <INVOICE_ID> below with the actual UUID

-- Step 2: Check current journal entries for this invoice
SELECT 
  je.id AS journal_entry_id,
  je.entry_number,
  je.entry_type,
  je.status,
  je.notes,
  COUNT(jl.id) AS line_count
FROM journal_entries je
LEFT JOIN journal_lines jl ON jl.journal_entry_id = je.id
WHERE je.source_module = 'purchase_invoices'
  AND je.source_reference = '<INVOICE_ID>' -- Replace with actual ID
GROUP BY je.id, je.entry_number, je.entry_type, je.status, je.notes;

-- Step 3: Enable trigger logging (to see NOTICE messages)
-- This helps you see what the trigger is doing

-- Step 4: Now go to your Flutter app and click "Volver a Enviada"

-- Step 5: Immediately after clicking, run this query:
SELECT 
  je.id AS journal_entry_id,
  je.entry_number,
  je.entry_type,
  je.status,
  je.notes
FROM journal_entries je
WHERE je.source_module = 'purchase_invoices'
  AND je.source_reference = '<INVOICE_ID>' -- Replace with actual ID;

-- Should return 0 rows if trigger worked! ✅

-- Step 6: Check the invoice status changed
SELECT 
  invoice_number,
  status,
  sent_date,
  confirmed_date
FROM purchase_invoices
WHERE id = '<INVOICE_ID>'; -- Replace with actual ID

-- Status should be 'sent' ✅

-- =====================================================
-- ALTERNATIVE: Monitor in real-time
-- =====================================================

-- Watch for changes (run this in a separate query window)
SELECT 
  pi.invoice_number,
  pi.status,
  COUNT(je.id) AS journal_entry_count,
  NOW() AS checked_at
FROM purchase_invoices pi
LEFT JOIN journal_entries je ON je.source_reference = pi.id::TEXT 
  AND je.source_module = 'purchase_invoices'
WHERE pi.id = '<INVOICE_ID>' -- Replace with actual ID
GROUP BY pi.id, pi.invoice_number, pi.status;

-- Refresh this query repeatedly to see changes

-- =====================================================
-- DEBUG: Check if UPDATE actually happens
-- =====================================================

-- Before clicking in app, run:
SELECT id, status, updated_at FROM purchase_invoices WHERE id = '<INVOICE_ID>';

-- After clicking in app, run again:
SELECT id, status, updated_at FROM purchase_invoices WHERE id = '<INVOICE_ID>';

-- Compare the updated_at timestamp - should be newer ✅

-- =====================================================
-- MANUAL TEST (bypasses Flutter app)
-- =====================================================

-- This tests the trigger directly in SQL
DO $$
DECLARE
  v_invoice_id UUID := '<INVOICE_ID>'; -- Replace with actual ID
  v_je_before INT;
  v_je_after INT;
BEGIN
  -- Count before
  SELECT COUNT(*) INTO v_je_before
  FROM journal_entries
  WHERE source_reference = v_invoice_id::TEXT
    AND source_module = 'purchase_invoices';
  
  RAISE NOTICE 'Journal entries BEFORE: %', v_je_before;
  
  -- Do the update (same as Flutter app does)
  UPDATE purchase_invoices
  SET status = 'sent', updated_at = NOW()
  WHERE id = v_invoice_id;
  
  -- Count after
  SELECT COUNT(*) INTO v_je_after
  FROM journal_entries
  WHERE source_reference = v_invoice_id::TEXT
    AND source_module = 'purchase_invoices';
  
  RAISE NOTICE 'Journal entries AFTER: %', v_je_after;
  
  IF v_je_after = 0 THEN
    RAISE NOTICE '✅ Trigger worked! Entry deleted!';
    
    -- Restore to confirmed
    UPDATE purchase_invoices
    SET status = 'confirmed', confirmed_date = NOW(), updated_at = NOW()
    WHERE id = v_invoice_id;
    
    RAISE NOTICE 'Invoice restored to confirmed for you';
  ELSE
    RAISE WARNING '❌ Trigger did NOT work! Entry still exists!';
    RAISE WARNING 'Check trigger definition and logs';
  END IF;
END $$;

-- =====================================================
-- TROUBLESHOOTING: Check trigger is actually firing
-- =====================================================

-- Check PostgreSQL logs for trigger activity
-- (In Supabase Dashboard → Database → Logs)
-- Filter by: "purchase_invoice"
-- Look for: "Deleted accounting entry for reverted invoice"

-- If you don't see log messages, the trigger might not be firing!

-- =====================================================
-- FINAL CHECK: Verify exact trigger condition
-- =====================================================

-- The trigger only fires when status changes
-- Show trigger definition:
SELECT 
  pg_get_triggerdef(oid) AS trigger_definition
FROM pg_trigger
WHERE tgname = 'purchase_invoice_change_trigger';

-- Should show:
-- WHEN (OLD.status IS DISTINCT FROM NEW.status)
-- This means it ONLY fires when status actually changes

-- =====================================================
-- TIP: Test with a fresh invoice
-- =====================================================

-- If your test invoice has been changed many times,
-- try with a fresh one:

-- 1. Create new invoice at 'sent' status
-- 2. Change to 'confirmed' (creates journal entry)
-- 3. Change back to 'sent' (should delete journal entry)

-- Create test invoice:
INSERT INTO purchase_invoices (
  id, invoice_number, status, prepayment_model, 
  total, subtotal, iva_amount, supplier_id, items, created_at, updated_at
)
VALUES (
  gen_random_uuid(),
  'TEST-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS'),
  'sent',
  false,
  119000,
  100000,
  19000,
  (SELECT id FROM suppliers LIMIT 1),
  '[]'::JSONB,
  NOW(),
  NOW()
)
RETURNING id, invoice_number;

-- Note the returned ID, then:
-- 1. Change to 'confirmed' in Flutter app
-- 2. Check journal entry created
-- 3. Change to 'sent' in Flutter app
-- 4. Check journal entry deleted ✅
