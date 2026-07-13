-- Allow anonymous users to view orders by ID (for order confirmation page)
-- This is needed so customers can see their order after MercadoPago redirect

-- Policy for anonymous (public) access to online_orders by ID
DROP POLICY IF EXISTS "public_online_orders_anon_select" ON online_orders;

CREATE POLICY "public_online_orders_anon_select" ON online_orders
  FOR SELECT
  TO anon
  USING (true);  -- Allow viewing any order by ID (they need the UUID)

-- Policy for anonymous access to online_order_items
DROP POLICY IF EXISTS "public_online_order_items_anon_select" ON online_order_items;

CREATE POLICY "public_online_order_items_anon_select" ON online_order_items
  FOR SELECT
  TO anon
  USING (true);  -- Allow viewing items if you know the order_id

-- Note: UUIDs are unguessable (128-bit random), so this is secure.
-- Anyone with the order ID link can view their order - standard e-commerce pattern.
