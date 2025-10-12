-- ============================================================================
-- Complete Test: Sales Invoice Inventory Flow
-- ============================================================================
-- This test will help identify exactly where the double deduction happens
-- ============================================================================

-- Step 1: Check current product inventory
SELECT id, sku, name, inventory_qty 
FROM products 
WHERE sku = 'BIC-NEU-95432'  -- Replace with your test product SKU
LIMIT 1;

-- Expected: Let's say inventory_qty = 10

-- Step 2: Create a test invoice in DRAFT status
DO $$
DECLARE
  v_invoice_id UUID;
  v_product_id UUID;
BEGIN
  -- Get product ID
  SELECT id INTO v_product_id FROM products WHERE sku = 'BIC-NEU-95432' LIMIT 1;
  
  -- Create invoice
  INSERT INTO sales_invoices (
    id, invoice_number, customer_name, date, status,
    subtotal, iva_amount, total,
    items,
    created_at, updated_at
  ) VALUES (
    gen_random_uuid(),
    'TEST-001',
    'Test Customer',
    NOW(),
    'draft',  -- Start as draft
    10000,
    1900,
    11900,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', v_product_id,
        'product_sku', 'BIC-NEU-95432',
        'quantity', 2,
        'price', 5000
      )
    ),
    NOW(),
    NOW()
  )
  RETURNING id INTO v_invoice_id;
  
  RAISE NOTICE 'Created test invoice: %', v_invoice_id;
END $$;

-- Step 3: Check inventory after DRAFT (should be unchanged)
SELECT id, sku, name, inventory_qty 
FROM products 
WHERE sku = 'BIC-NEU-95432';
-- Expected: inventory_qty = 10 (unchanged)

-- Step 4: Update to SENT
UPDATE sales_invoices
SET status = 'sent', updated_at = NOW()
WHERE invoice_number = 'TEST-001';

-- Step 5: Check inventory after SENT (should be unchanged)
SELECT id, sku, name, inventory_qty 
FROM products 
WHERE sku = 'BIC-NEU-95432';
-- Expected: inventory_qty = 10 (unchanged)

-- Step 6: Update to CONFIRMED
UPDATE sales_invoices
SET status = 'confirmed', updated_at = NOW()
WHERE invoice_number = 'TEST-001';

-- Step 7: Check inventory after CONFIRMED (should be deducted)
SELECT id, sku, name, inventory_qty 
FROM products 
WHERE sku = 'BIC-NEU-95432';
-- Expected: inventory_qty = 8 (deducted 2)

-- Step 8: Check stock movements
SELECT id, product_id, type, quantity, reference, notes
FROM stock_movements
WHERE reference LIKE '%' || (SELECT id FROM sales_invoices WHERE invoice_number = 'TEST-001')::text || '%';
-- Expected: 1 row, type='OUT', quantity=-2

-- Step 9: Update back to SENT (THE BUG TEST!)
UPDATE sales_invoices
SET status = 'sent', updated_at = NOW()
WHERE invoice_number = 'TEST-001';

-- Step 10: Check inventory after reverting to SENT
SELECT id, sku, name, inventory_qty 
FROM products 
WHERE sku = 'BIC-NEU-95432';
-- ✅ EXPECTED (after fix): inventory_qty = 10 (restored)
-- ❌ BUG (before fix): inventory_qty = 6 (deducted again!)

-- Step 11: Check stock movements after revert
SELECT id, product_id, type, quantity, reference, notes
FROM stock_movements
WHERE reference LIKE '%' || (SELECT id FROM sales_invoices WHERE invoice_number = 'TEST-001')::text || '%';
-- ✅ EXPECTED: 0 rows (movements deleted when reverting)
-- ❌ BUG: Still shows movement

-- Clean up
DELETE FROM sales_invoices WHERE invoice_number = 'TEST-001';
