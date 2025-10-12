-- ============================================================================
-- Cleanup: Remove Orphaned Stock Movements
-- ============================================================================
-- If you're testing with an invoice that was created BEFORE the fix,
-- there might be orphaned stock movements causing issues
-- ============================================================================

-- Step 1: Check for duplicate stock movements for the same invoice
SELECT 
  reference,
  COUNT(*) as movement_count,
  SUM(quantity) as total_quantity
FROM stock_movements
WHERE reference LIKE 'sales_invoice:%'
  AND type = 'OUT'
GROUP BY reference
HAVING COUNT(*) > 1;

-- If you see duplicates, that's the problem!

-- Step 2: Clean up duplicate movements (CAREFUL - only run if you see duplicates above)
-- This will keep only the most recent movement for each invoice
/*
DELETE FROM stock_movements
WHERE id IN (
  SELECT id
  FROM (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY reference ORDER BY created_at DESC) as rn
    FROM stock_movements
    WHERE reference LIKE 'sales_invoice:%'
      AND type = 'OUT'
  ) sub
  WHERE rn > 1
);
*/

-- Step 3: For testing, create a FRESH invoice
-- Don't use an old invoice that might have corrupted data
-- Delete test invoices and start fresh:
/*
DELETE FROM sales_invoices WHERE invoice_number LIKE 'FV-2025%';
*/

-- ============================================================================
-- RECOMMENDATION:
-- ============================================================================
-- 1. Create a BRAND NEW invoice from scratch
-- 2. Test the flow: Draft → Sent → Confirmed → Sent
-- 3. Check inventory at each step
--
-- Old invoices might have corrupted stock_movements from before the fix!
-- ============================================================================
