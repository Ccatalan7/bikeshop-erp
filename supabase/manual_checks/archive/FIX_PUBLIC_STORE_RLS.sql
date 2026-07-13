-- FIX: Add public access policy for website_pages and website_blocks
-- Anonymous users need to view published pages to show the public store

-- =====================================================
-- WEBSITE_PAGES - Allow anon to read published pages
-- =====================================================
drop policy if exists "website_pages_select_public" on website_pages;
create policy "website_pages_select_public" on website_pages
  for select to anon
  using (is_published = true);

-- =====================================================
-- WEBSITE_BLOCKS - Allow anon to read blocks for published pages
-- =====================================================
drop policy if exists "website_blocks_select_public" on website_blocks;
create policy "website_blocks_select_public" on website_blocks
  for select to anon
  using (
    exists (
      select 1 from website_pages wp 
      where wp.id = website_blocks.page_id 
        and wp.is_published = true
    )
    or is_visible = true -- Fallback for blocks without page_id
  );

-- =====================================================
-- WEBSITE_SETTINGS - Allow anon to read settings
-- =====================================================
drop policy if exists "website_settings_select_public" on website_settings;
create policy "website_settings_select_public" on website_settings
  for select to anon
  using (true);

-- =====================================================
-- PRODUCTS - Allow anon to read published products
-- =====================================================
drop policy if exists "products_select_public" on products;
create policy "products_select_public" on products
  for select to anon
  using (is_active = true and show_on_website = true);

-- =====================================================
-- PRODUCT_CATEGORIES - Allow anon to read categories
-- =====================================================
drop policy if exists "product_categories_select_public" on product_categories;
create policy "product_categories_select_public" on product_categories
  for select to anon
  using (true);

-- =====================================================
-- PRODUCT_BRANDS - Allow anon to read brands
-- =====================================================
drop policy if exists "product_brands_select_public" on product_brands;
create policy "product_brands_select_public" on product_brands
  for select to anon
  using (true);

-- Verify policies were created
select tablename, policyname, roles, cmd 
from pg_policies 
where policyname like '%public%'
order by tablename;
