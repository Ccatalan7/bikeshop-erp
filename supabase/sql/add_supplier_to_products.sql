-- Migration: Add supplier_id field to products table
-- Purpose: Enable supplier filtering and tracking for products

-- Step 1: Add supplier_id column (nullable to allow existing products)
ALTER TABLE products
ADD COLUMN supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL;

-- Step 2: Add index for performance on supplier filtering
CREATE INDEX idx_products_supplier_id ON products(supplier_id);

-- Step 3: Add supplier_name for denormalization (faster queries, avoid joins)
ALTER TABLE products
ADD COLUMN supplier_name TEXT;

-- Step 4: Create trigger function to auto-update supplier_name when supplier changes
CREATE OR REPLACE FUNCTION update_product_supplier_name()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.supplier_id IS NOT NULL THEN
    SELECT name INTO NEW.supplier_name
    FROM suppliers
    WHERE id = NEW.supplier_id;
  ELSE
    NEW.supplier_name := NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 5: Create trigger to fire on INSERT or UPDATE
DROP TRIGGER IF EXISTS trigger_update_product_supplier_name ON products;
CREATE TRIGGER trigger_update_product_supplier_name
  BEFORE INSERT OR UPDATE OF supplier_id ON products
  FOR EACH ROW
  EXECUTE FUNCTION update_product_supplier_name();

-- Step 6: Backfill supplier_name for existing products with supplier_id
UPDATE products p
SET supplier_name = s.name
FROM suppliers s
WHERE p.supplier_id = s.id
  AND p.supplier_name IS NULL;

-- Step 7: Add comment for documentation
COMMENT ON COLUMN products.supplier_id IS 'Reference to the supplier who provides this product';
COMMENT ON COLUMN products.supplier_name IS 'Denormalized supplier name for faster queries (auto-updated by trigger)';
