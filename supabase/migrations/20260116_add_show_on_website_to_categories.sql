-- Add show_on_website column to product_categories
-- This flag controls which categories appear in the public store navigation

ALTER TABLE product_categories 
ADD COLUMN IF NOT EXISTS show_on_website boolean NOT NULL DEFAULT false;

-- Create index for efficient filtering
CREATE INDEX IF NOT EXISTS idx_product_categories_show_on_website 
ON product_categories(show_on_website) 
WHERE show_on_website = true;

COMMENT ON COLUMN product_categories.show_on_website IS 
'Whether this category should appear in the public store navigation';
