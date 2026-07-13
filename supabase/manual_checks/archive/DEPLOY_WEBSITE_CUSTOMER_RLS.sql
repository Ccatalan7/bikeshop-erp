-- ============================================================================
-- DEPLOY: Website Customer RLS Policies
-- 
-- PROBLEM: Website customers who log in become "authenticated" but don't have
-- user_profiles records. The existing products_select policy uses user_tenant_id()
-- which returns NULL for them → products don't load.
--
-- SOLUTION: Add _authenticated versions of all public store policies so that
-- logged-in website customers can still browse products (using app-layer tenant filter).
--
-- Date: December 8, 2025
-- ============================================================================

-- Drop all existing public store policies first
drop policy if exists "public_products_select" on products;
drop policy if exists "public_products_select_authenticated" on products;
drop policy if exists "public_categories_select" on categories;
drop policy if exists "public_categories_select_authenticated" on categories;
drop policy if exists "public_product_categories_select" on product_categories;
drop policy if exists "public_product_categories_select_authenticated" on product_categories;
drop policy if exists "public_website_banners_select" on website_banners;
drop policy if exists "public_website_banners_select_authenticated" on website_banners;
drop policy if exists "public_website_content_select" on website_content;
drop policy if exists "public_website_content_select_authenticated" on website_content;
drop policy if exists "public_website_settings_select" on website_settings;
drop policy if exists "public_website_settings_select_authenticated" on website_settings;
drop policy if exists "public_website_blocks_select" on website_blocks;
drop policy if exists "public_website_blocks_select_authenticated" on website_blocks;
drop policy if exists "public_tenants_select" on tenants;
drop policy if exists "public_tenants_select_authenticated" on tenants;
drop policy if exists "public_online_orders_insert" on online_orders;
drop policy if exists "public_online_orders_insert_authenticated" on online_orders;
drop policy if exists "public_online_order_items_insert" on online_order_items;
drop policy if exists "public_online_order_items_insert_authenticated" on online_order_items;
drop policy if exists "public_online_orders_select_authenticated" on online_orders;
drop policy if exists "public_online_order_items_select_authenticated" on online_order_items;
drop policy if exists "public_featured_products_select" on featured_products;
drop policy if exists "public_featured_products_select_authenticated" on featured_products;
drop policy if exists "public_product_brands_select" on product_brands;
drop policy if exists "public_product_brands_select_authenticated" on product_brands;
drop policy if exists "public_customers_select_own" on customers;
drop policy if exists "public_customers_update_own" on customers;
drop policy if exists "public_customers_insert_own" on customers;
drop policy if exists "public_mechanic_jobs_select_own" on mechanic_jobs;
drop policy if exists "public_bikes_select_own" on bikes;

-- ============================================================================
-- TENANT DETECTION POLICIES
-- ============================================================================

-- Tenants: anon can lookup for subdomain detection
create policy "public_tenants_select" on tenants 
  for select to anon using (is_active = true);

-- Tenants: authenticated users (website customers) can also lookup
create policy "public_tenants_select_authenticated" on tenants 
  for select to authenticated using (is_active = true);

-- ============================================================================
-- WEBSITE CONTENT POLICIES (anon + authenticated)
-- ============================================================================

-- Website blocks: anon
create policy "public_website_blocks_select" on website_blocks 
  for select to anon using (is_visible = true);

-- Website blocks: authenticated
create policy "public_website_blocks_select_authenticated" on website_blocks 
  for select to authenticated using (is_visible = true);

-- ============================================================================
-- PRODUCT CATALOG POLICIES (anon + authenticated)
-- ============================================================================

-- Products: anon can browse
create policy "public_products_select" on products 
  for select to anon using (is_active = true);

-- Products: authenticated website customers can also browse
-- (App layer filters by tenant_id explicitly)
create policy "public_products_select_authenticated" on products 
  for select to authenticated using (is_active = true);

-- Product Categories: anon
create policy "public_product_categories_select" on product_categories 
  for select to anon using (is_active = true);

-- Product Categories: authenticated
create policy "public_product_categories_select_authenticated" on product_categories 
  for select to authenticated using (is_active = true);

-- Legacy Categories (if exists)
do $$
begin
  if exists (select 1 from information_schema.tables where table_name = 'categories') then
    execute 'create policy "public_categories_select" on categories for select to anon using (true)';
    execute 'create policy "public_categories_select_authenticated" on categories for select to authenticated using (true)';
  end if;
exception when duplicate_object then null;
end $$;

-- Website banners: anon
create policy "public_website_banners_select" on website_banners 
  for select to anon using (active = true);

-- Website banners: authenticated
create policy "public_website_banners_select_authenticated" on website_banners 
  for select to authenticated using (active = true);

-- Website content: anon
do $$ begin
  create policy "public_website_content_select" on website_content 
    for select to anon using (tenant_id is not null);
exception when undefined_table then null; end $$;

-- Website content: authenticated
do $$ begin
  create policy "public_website_content_select_authenticated" on website_content 
    for select to authenticated using (tenant_id is not null);
exception when undefined_table then null; end $$;

-- Website settings: anon
create policy "public_website_settings_select" on website_settings 
  for select to anon using (true);

-- Website settings: authenticated
create policy "public_website_settings_select_authenticated" on website_settings 
  for select to authenticated using (true);

-- Featured products: anon
create policy "public_featured_products_select" on featured_products 
  for select to anon using (active = true);

-- Featured products: authenticated
create policy "public_featured_products_select_authenticated" on featured_products 
  for select to authenticated using (active = true);

-- Product brands: anon
create policy "public_product_brands_select" on product_brands 
  for select to anon using (is_active = true);

-- Product brands: authenticated
create policy "public_product_brands_select_authenticated" on product_brands 
  for select to authenticated using (is_active = true);

-- ============================================================================
-- CUSTOMER ACCOUNT POLICIES
-- Website customers can view/manage their own data
-- ============================================================================

-- Customers: view own record (column is auth_user_id, not user_id)
create policy "public_customers_select_own" on customers 
  for select to authenticated using (auth_user_id = auth.uid());

-- Customers: update own record
create policy "public_customers_update_own" on customers 
  for update to authenticated using (auth_user_id = auth.uid());

-- Customers: INSERT own record (for website signup - user can only create their own customer record)
-- This is CRITICAL because website customers don't have user_profiles, so user_tenant_id() returns NULL
-- and the regular customers_insert policy fails
create policy "public_customers_insert_own" on customers 
  for insert to authenticated
  with check (
    auth_user_id = auth.uid() AND  -- Can only create their own record
    tenant_id IS NOT NULL          -- Must specify a valid tenant
  );

-- Online Orders: view own orders
create policy "public_online_orders_select_authenticated" on online_orders 
  for select to authenticated
  using (customer_id IN (SELECT id FROM customers WHERE auth_user_id = auth.uid()));

-- Online Order Items: view own order items
create policy "public_online_order_items_select_authenticated" on online_order_items 
  for select to authenticated
  using (order_id IN (
    SELECT id FROM online_orders WHERE customer_id IN (
      SELECT id FROM customers WHERE auth_user_id = auth.uid()
    )
  ));

-- Mechanic Jobs (Pegas): Website customers can view their own service history
create policy "public_mechanic_jobs_select_own" on mechanic_jobs 
  for select to authenticated
  using (customer_id IN (
    SELECT id FROM customers WHERE auth_user_id = auth.uid()
  ));

-- Bikes: Website customers can view their own bikes
create policy "public_bikes_select_own" on bikes 
  for select to authenticated
  using (customer_id IN (
    SELECT id FROM customers WHERE auth_user_id = auth.uid()
  ));

-- ============================================================================
-- CHECKOUT POLICIES (anon + authenticated)
-- ============================================================================

-- Online Orders: anon can create (guest checkout)
create policy "public_online_orders_insert" on online_orders 
  for insert to anon
  with check (tenant_id is not null and status in ('pending', 'processing'));

-- Online Orders: authenticated can also create
create policy "public_online_orders_insert_authenticated" on online_orders 
  for insert to authenticated
  with check (tenant_id is not null and status in ('pending', 'processing'));

-- Online Order Items: anon can create
create policy "public_online_order_items_insert" on online_order_items 
  for insert to anon with check (tenant_id is not null);

-- Online Order Items: authenticated can also create
create policy "public_online_order_items_insert_authenticated" on online_order_items 
  for insert to authenticated with check (tenant_id is not null);

-- ============================================================================
-- VERIFICATION
-- ============================================================================
SELECT 'Policies created successfully!' as status;

-- Show all public store policies
SELECT tablename, policyname, roles, cmd 
FROM pg_policies 
WHERE policyname LIKE 'public_%'
ORDER BY tablename, policyname;
