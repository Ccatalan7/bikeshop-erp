-- Deploy to Supabase: Add Category Support to Smart Purchase List
-- Modified core_schema.sql lines 2111-2118

-- Add category columns to smart_purchase_list table
alter table smart_purchase_list add column if not exists category_id uuid references product_categories(id) on delete set null;
alter table smart_purchase_list add column if not exists category_name text;

-- Add index for category filtering performance
create index if not exists idx_smart_purchase_list_category on smart_purchase_list(category_id);

-- INSTRUCTIONS:
-- 1. Copy this SQL code
-- 2. Go to Supabase Dashboard → SQL Editor
-- 3. Paste and run this query
-- 4. Restart your Flutter app to pick up the schema changes
