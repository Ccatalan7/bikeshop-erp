-- ============================================================================
-- Diagnostic Query: Check Current Database State
-- ============================================================================

-- 1. Check if restore function has ABS() in it
SELECT 
  proname as function_name,
  pg_get_functiondef(oid) as definition
FROM pg_proc
WHERE proname = 'restore_sales_invoice_inventory';

-- 2. Check recent stock movements
SELECT 
  id,
  product_id,
  quantity,
  movement_type,
  reference,
  created_at
FROM stock_movements
ORDER BY created_at DESC
LIMIT 20;

-- 3. Check sales invoices with their status
SELECT 
  id,
  invoice_number,
  customer_id,
  status,
  total_amount,
  created_at,
  updated_at
FROM sales_invoices
ORDER BY updated_at DESC
LIMIT 10;

-- 4. Check product inventory levels
SELECT 
  id,
  name,
  sku,
  inventory_qty,
  stock_quantity
FROM products
WHERE inventory_qty IS NOT NULL OR stock_quantity IS NOT NULL
ORDER BY updated_at DESC
LIMIT 10;

-- 5. Check if consume function skips 'sent'
SELECT 
  proname as function_name,
  pg_get_functiondef(oid) as definition
FROM pg_proc
WHERE proname = 'consume_sales_invoice_inventory';
