-- 🔍 Complete Website Module Verification Script
-- Run this in Supabase SQL Editor to verify everything

-- ============================================================================
-- PART 1: Check all tables exist
-- ============================================================================
SELECT 
  tablename,
  CASE 
    WHEN tablename = 'website_banners' THEN '✅ Banners table'
    WHEN tablename = 'featured_products' THEN '✅ Featured products table'
    WHEN tablename = 'website_content' THEN '✅ Content table'
    WHEN tablename = 'website_settings' THEN '✅ Settings table'
    WHEN tablename = 'online_orders' THEN '✅ Orders table'
    WHEN tablename = 'online_order_items' THEN '✅ Order items table'
  END as description
FROM pg_tables 
WHERE schemaname = 'public' 
  AND (tablename LIKE 'website%' OR tablename LIKE 'online_%' OR tablename = 'featured_products')
ORDER BY tablename;

-- Expected: 6 rows

-- ============================================================================
-- PART 2: Check functions exist
-- ============================================================================
SELECT 
  proname as function_name,
  CASE 
    WHEN proname = 'process_online_order' THEN '✅ Order processing function'
    WHEN proname = 'generate_online_order_number' THEN '✅ Order number generator'
    WHEN proname = 'auto_generate_order_number' THEN '✅ Order number trigger function'
  END as description
FROM pg_proc 
WHERE proname IN ('process_online_order', 'generate_online_order_number', 'auto_generate_order_number')
ORDER BY proname;

-- Expected: 3 rows

-- ============================================================================
-- PART 3: Check default data exists
-- ============================================================================

-- Settings should have ~11 rows
SELECT COUNT(*) as settings_count, '✅ Settings seeded' as status
FROM website_settings;

-- Content should have ~6 rows
SELECT COUNT(*) as content_count, '✅ Content seeded' as status
FROM website_content;

-- ============================================================================
-- PART 4: Check product columns added
-- ============================================================================
SELECT 
  column_name,
  data_type,
  '✅ Column exists' as status
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'products'
  AND column_name IN ('show_on_website', 'website_description', 'website_featured')
ORDER BY column_name;

-- Expected: 3 rows

-- ============================================================================
-- PART 5: Check RLS policies
-- ============================================================================
SELECT 
  tablename,
  policyname,
  '✅ Policy active' as status
FROM pg_policies 
WHERE schemaname = 'public'
  AND (tablename LIKE 'website%' OR tablename LIKE 'online_%' OR tablename = 'featured_products')
ORDER BY tablename, policyname;

-- Expected: Multiple rows (at least 2-3 per table)

-- ============================================================================
-- PART 6: Test order number generation
-- ============================================================================
SELECT generate_online_order_number() as sample_order_number;

-- Expected: Something like 'WEB-25-00001'

-- ============================================================================
-- SUMMARY
-- ============================================================================
SELECT '🎉 ALL CHECKS COMPLETE!' as status;
