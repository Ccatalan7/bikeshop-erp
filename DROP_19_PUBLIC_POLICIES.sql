-- ============================================================================
-- DROP 19 OLD PUBLIC/CUSTOMER POLICIES THAT VIOLATE TENANT ISOLATION
-- ============================================================================
-- These policies allow cross-tenant data access for public website and customer self-service
-- They must be replaced with tenant-filtered policies for proper multi-tenant SaaS isolation
-- ============================================================================

-- customer_addresses: Drop old customer self-service policies (4 policies)
DROP POLICY IF EXISTS "Customers can delete own addresses" ON customer_addresses;
DROP POLICY IF EXISTS "Customers can insert own addresses" ON customer_addresses;
DROP POLICY IF EXISTS "Customers can update own addresses" ON customer_addresses;
DROP POLICY IF EXISTS "Customers can view own addresses" ON customer_addresses;

-- customers: Drop old customer self-service policies (2 policies)
DROP POLICY IF EXISTS "Customers can create own profile" ON customers;
DROP POLICY IF EXISTS "Customers can update own profile" ON customers;

-- featured_products: Drop public read policy (1 policy)
DROP POLICY IF EXISTS "Public can read active featured" ON featured_products;

-- online_order_items: Drop public/customer policies (3 policies)
DROP POLICY IF EXISTS "Customers can read own order items" ON online_order_items;
DROP POLICY IF EXISTS "Public can create order items" ON online_order_items;
DROP POLICY IF EXISTS "Public can read order items" ON online_order_items;

-- online_orders: Drop public/customer policies (3 policies)
DROP POLICY IF EXISTS "Customers can read own orders" ON online_orders;
DROP POLICY IF EXISTS "Public can create orders" ON online_orders;
DROP POLICY IF EXISTS "Public can read orders" ON online_orders;

-- products: Drop public website read policy (1 policy)
DROP POLICY IF EXISTS "Public website products read" ON products;

-- user_invitations: Drop user self-service policy (1 policy)
DROP POLICY IF EXISTS "users_view_own_invitations" ON user_invitations;

-- website_banners: Drop public read policy (1 policy)
DROP POLICY IF EXISTS "Public can read active banners" ON website_banners;

-- website_blocks: Drop public read policy (1 policy)
DROP POLICY IF EXISTS "Public can read visible blocks" ON website_blocks;

-- website_content: Drop public read policy (1 policy)
DROP POLICY IF EXISTS "Public can read content" ON website_content;

-- website_settings: Drop public read policy (1 policy)
DROP POLICY IF EXISTS "Public can read website settings" ON website_settings;

-- Verify all 19 policies are dropped
SELECT 
  tablename,
  policyname
FROM pg_policies
WHERE schemaname = 'public'
  AND policyname IN (
    'Customers can delete own addresses',
    'Customers can insert own addresses',
    'Customers can update own addresses',
    'Customers can view own addresses',
    'Customers can create own profile',
    'Customers can update own profile',
    'Public can read active featured',
    'Customers can read own order items',
    'Public can create order items',
    'Public can read order items',
    'Customers can read own orders',
    'Public can create orders',
    'Public can read orders',
    'Public website products read',
    'users_view_own_invitations',
    'Public can read active banners',
    'Public can read visible blocks',
    'Public can read content',
    'Public can read website settings'
  );

-- Should return 0 rows if all dropped successfully
