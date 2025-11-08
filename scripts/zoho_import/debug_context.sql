-- Debug: Check if session variables work in same transaction
BEGIN;

-- Set variables
SELECT set_config('app.stock_adjustment_context', 'import', true);
SELECT set_config('app.import_reference', 'debug_test', true);

-- Read them back
SELECT 
  current_setting('app.stock_adjustment_context', true) as context,
  current_setting('app.import_reference', true) as reference;

-- Update product
UPDATE products SET stock_quantity = 456, inventory_qty = 456 WHERE sku = '2854';

COMMIT;

-- Check if adjustment was created
SELECT * FROM stock_adjustments WHERE reference = 'debug_test' ORDER BY created_at DESC LIMIT 1;
