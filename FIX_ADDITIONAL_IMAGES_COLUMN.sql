-- 🔧 FIX: Add missing additional_images column to products table
-- Run this in Supabase SQL Editor (STAGING first!)
-- Staging: https://supabase.com/dashboard/project/kyvgmapifacpzuyreasy/sql
-- Production: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/sql
-- Date: Jan 5, 2025

-- Add additional_images array (Flutter model compatibility)
do $$
begin
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'additional_images') then
    alter table products add column additional_images text[] not null default array[]::text[];
    raise notice 'Added additional_images column to products table';
  else
    raise notice 'Column additional_images already exists';
  end if;
end $$;

-- Verify the column was added
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_name = 'products'
  and column_name in ('image_url', 'image_urls', 'additional_images')
order by column_name;
