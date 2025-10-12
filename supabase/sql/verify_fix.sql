-- ============================================================================
-- Quick Test: Verify the Fix is Working
-- ============================================================================

-- Step 1: Check that the function now has "sent" in the skip list
-- Run this and look for 'sent', 'enviado' in the output
SELECT pg_get_functiondef(oid)::text LIKE '%sent%' AS has_sent_fix
FROM pg_proc 
WHERE proname = 'consume_sales_invoice_inventory'
  AND pronamespace = 'public'::regnamespace;

-- Expected result: has_sent_fix = true

-- ============================================================================
-- Manual Test in Your App:
-- ============================================================================
-- 1. Go to a product and note its current inventory (e.g., 10 units)
-- 2. Create a new invoice with 2 units of that product
-- 3. Mark as "Sent" → Check inventory (should still be 10)
-- 4. Mark as "Confirmed" → Check inventory (should be 8)
-- 5. Revert to "Sent" → Check inventory (should be back to 10) ✅
--
-- If step 5 shows inventory = 6 instead of 10, something else is wrong
-- ============================================================================
