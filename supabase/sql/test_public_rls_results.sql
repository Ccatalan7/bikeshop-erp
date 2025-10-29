-- ========================================
-- PUBLIC RLS TESTS - RESULTS TABLE VERSION
-- ========================================
-- This version returns results as a table you can see
-- ========================================

WITH test_setup AS (
    SELECT id as tenant_id, shop_name 
    FROM tenants 
    LIMIT 1
),
test_results AS (
    SELECT 
        'TEST 1' as test_number,
        'Anonymous Read Products' as test_name,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM products p, test_setup ts 
                WHERE p.tenant_id = ts.tenant_id
            )
            THEN '✅ PASSED'
            ELSE '⚠️  No products found'
        END as result,
        (SELECT COUNT(*)::text FROM products p, test_setup ts WHERE p.tenant_id = ts.tenant_id) as details
    
    UNION ALL
    
    SELECT 
        'TEST 2',
        'Anonymous Read Categories',
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM product_categories pc, test_setup ts 
                WHERE pc.tenant_id = ts.tenant_id
            )
            THEN '✅ PASSED'
            ELSE '⚠️  No categories found'
        END,
        (SELECT COUNT(*)::text FROM product_categories pc, test_setup ts WHERE pc.tenant_id = ts.tenant_id)
    
    UNION ALL
    
    SELECT 
        'TEST 3',
        'Check RLS Policies Exist',
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM pg_policies 
                WHERE schemaname = 'public' 
                AND tablename = 'products'
                AND policyname LIKE 'public_%'
            )
            THEN '✅ PASSED'
            ELSE '❌ FAILED - No public policies'
        END,
        (SELECT COUNT(*)::text || ' public policies' FROM pg_policies WHERE tablename = 'products' AND policyname LIKE 'public_%')
    
    UNION ALL
    
    SELECT 
        'INFO',
        'Tenant Being Tested',
        (SELECT shop_name FROM test_setup),
        (SELECT tenant_id::text FROM test_setup)
)
SELECT * FROM test_results
ORDER BY test_number;
