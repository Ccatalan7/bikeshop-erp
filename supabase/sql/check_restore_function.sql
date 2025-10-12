-- ============================================================================
-- Check the restore_sales_invoice_inventory function
-- ============================================================================

SELECT pg_get_functiondef(oid)
FROM pg_proc 
WHERE proname = 'restore_sales_invoice_inventory';

-- ============================================================================
-- Look for this line in the function:
-- ============================================================================
-- CORRECT (should ADD):
--   inventory_qty = coalesce(inventory_qty, 0) + $1
--
-- WRONG (if it subtracts):
--   inventory_qty = coalesce(inventory_qty, 0) - $1
--
-- The restore function should be ADDING back the quantity, not subtracting!
-- ============================================================================
