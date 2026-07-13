-- ============================================================================
-- FIX: website_pages RLS policy for authenticated users browsing public stores
-- 
-- PROBLEM: When logged into ERP (project-vinabike.web.app), clicking policy
-- pages on vinabike.cl returns null because RLS blocks authenticated users
-- from seeing pages that don't belong to their tenant.
--
-- SOLUTION: Authenticated users should see:
-- 1. ANY published page (for browsing public stores while logged in)
-- 2. Their own tenant's pages (including unpublished, for editing)
--
-- This matches how Shopify/Odoo/WooCommerce work - being logged in as admin
-- doesn't prevent you from seeing public content.
-- ============================================================================

-- Drop the restrictive policy
DROP POLICY IF EXISTS "website_pages_select" ON website_pages;

-- Create new policy that allows viewing published pages from ANY tenant
CREATE POLICY "website_pages_select" ON website_pages
  FOR SELECT TO authenticated
  USING (
    is_published = true  -- Anyone can see published pages (public content)
    OR tenant_id = public.user_tenant_id()  -- Owners see all their pages
  );

-- Verify the change
SELECT 
  policyname, 
  cmd, 
  roles,
  qual as condition
FROM pg_policies 
WHERE tablename = 'website_pages' 
  AND policyname = 'website_pages_select';
