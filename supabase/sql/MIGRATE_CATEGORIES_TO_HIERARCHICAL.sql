-- ============================================================================
-- MIGRATION: categories → product_categories (Hierarchical)
-- ============================================================================
-- This migration converts the flat 'categories' table to the new hierarchical
-- 'product_categories' table with full_path support.
-- 
-- Run this in Supabase SQL Editor ONCE to migrate your data.
-- ============================================================================

-- Step 1: Create the new product_categories table if it doesn't exist
create table if not exists product_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  full_path text not null unique, -- e.g., "Accesorios / Asientos / Tija"
  parent_id uuid references product_categories(id) on delete cascade,
  level integer not null default 0, -- 0 = root, 1 = child, 2 = grandchild, etc.
  description text,
  image_url text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Step 2: Create indexes for product_categories
create index if not exists idx_product_categories_parent_id on product_categories(parent_id);
create index if not exists idx_product_categories_full_path on product_categories(full_path);
create index if not exists idx_product_categories_level on product_categories(level);
create index if not exists idx_product_categories_is_active on product_categories(is_active);
create index if not exists idx_product_categories_name on product_categories using gin (to_tsvector('spanish', coalesce(name, '')));

-- Step 3: Migrate existing data from 'categories' to 'product_categories'
-- (Only if the old 'categories' table exists)
do $$
declare
  old_table_exists boolean;
begin
  -- Check if old 'categories' table exists
  select exists (
    select from pg_tables
    where schemaname = 'public'
    and tablename = 'categories'
  ) into old_table_exists;

  if old_table_exists then
    -- Migrate data: set full_path = name for root categories
    insert into product_categories (id, name, full_path, parent_id, level, description, image_url, is_active, sort_order, created_at, updated_at)
    select 
      id,
      name,
      name as full_path, -- For flat categories, full_path = name
      null as parent_id, -- All old categories become root (level 0)
      0 as level,
      description,
      image_url,
      is_active,
      coalesce(sort_order, 0) as sort_order,
      created_at,
      updated_at
    from categories
    on conflict (id) do nothing; -- Skip if already migrated

    raise notice 'Migrated % categories from old table', (select count(*) from categories);
  else
    raise notice 'Old categories table does not exist, skipping migration';
  end if;
end $$;

-- Step 4: Drop the old foreign key constraint if it exists
do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conrelid = 'public.products'::regclass
    and conname = 'products_category_id_fkey'
  ) then
    alter table products drop constraint products_category_id_fkey;
    raise notice 'Dropped old products_category_id_fkey constraint';
  end if;
end $$;

-- Step 5: Add new foreign key constraint pointing to product_categories
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.products'::regclass
    and conname = 'products_category_id_fkey'
  ) then
    alter table products
      add constraint products_category_id_fkey
        foreign key (category_id) references public.product_categories(id) on delete set null;
    raise notice 'Added new products_category_id_fkey constraint';
  end if;
end $$;

-- Step 6: Create index on products.category_id
create index if not exists idx_products_category_id on products(category_id);

-- Step 7: Drop the old 'categories' table (OPTIONAL - uncomment if you want to remove it)
-- WARNING: This will permanently delete the old table!
-- drop table if exists categories cascade;
-- raise notice 'Dropped old categories table';

-- ============================================================================
-- MIGRATION COMPLETE!
-- ============================================================================
-- Next steps:
-- 1. Verify that product_categories has your data: SELECT * FROM product_categories;
-- 2. Verify products can save: Try editing a product in the UI
-- 3. If everything works, uncomment Step 7 above and run again to drop old table
-- ============================================================================
