-- =====================================================
-- Add product_type column to products table
-- =====================================================
-- Allows classification between physical products and services
-- Products can be purchased, services can only be sold
-- =====================================================

-- Add product_type column
ALTER TABLE products 
ADD COLUMN IF NOT EXISTS product_type TEXT NOT NULL DEFAULT 'product'
CHECK (product_type IN ('product', 'service'));

-- Create index for filtering
CREATE INDEX IF NOT EXISTS idx_products_product_type ON products(product_type);

-- Update existing products to default type
UPDATE products
SET product_type = 'product'
WHERE product_type IS NULL;

-- Set services category items to service type
UPDATE products
SET product_type = 'service'
WHERE category = 'services';

-- Display summary
DO $$
DECLARE
  v_product_count INTEGER;
  v_service_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_product_count FROM products WHERE product_type = 'product';
  SELECT COUNT(*) INTO v_service_count FROM products WHERE product_type = 'service';
  
  RAISE NOTICE '✅ Product type column added successfully!';
  RAISE NOTICE '';
  RAISE NOTICE '📊 Summary:';
  RAISE NOTICE '   Products: %', v_product_count;
  RAISE NOTICE '   Services: %', v_service_count;
  RAISE NOTICE '   Total: %', v_product_count + v_service_count;
  RAISE NOTICE '';
  RAISE NOTICE '✨ Business Rules:';
  RAISE NOTICE '   - Products: Can be purchased and sold';
  RAISE NOTICE '   - Services: Can only be sold (not purchased)';
  RAISE NOTICE '';
  RAISE NOTICE '🔍 Filtering:';
  RAISE NOTICE '   - Purchase invoices: Only show products';
  RAISE NOTICE '   - Sales invoices: Show both products and services';
END $$;
