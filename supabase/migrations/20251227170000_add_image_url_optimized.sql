-- Migration: Add image_url_optimized column to products table
-- This column stores the URL of the optimized WebP version of product images

ALTER TABLE products ADD COLUMN IF NOT EXISTS image_url_optimized text;

COMMENT ON COLUMN products.image_url_optimized IS 'URL of optimized WebP image for fast web loading';
