-- ============================================================================
-- FIND ALL TABLES MISSING tenant_id
-- ============================================================================

-- List ALL public tables
WITH all_tables AS (
  SELECT table_name 
  FROM information_schema.tables 
  WHERE table_schema = 'public' 
    AND table_type = 'BASE TABLE'
),
-- Tables that HAVE tenant_id
tables_with_tenant AS (
  SELECT DISTINCT table_name
  FROM information_schema.columns
  WHERE column_name = 'tenant_id'
    AND table_schema = 'public'
)
-- Tables that DON'T have tenant_id
SELECT 
  at.table_name,
  CASE 
    WHEN at.table_name = 'tenants' THEN '✓ System table - OK'
    WHEN at.table_name LIKE '%migrations%' THEN '✓ System table - OK'
    WHEN at.table_name LIKE 'schema_%' THEN '✓ System table - OK'
    ELSE '❌ MISSING tenant_id - NEEDS FIX'
  END as status
FROM all_tables at
LEFT JOIN tables_with_tenant twt ON at.table_name = twt.table_name
WHERE twt.table_name IS NULL
ORDER BY 
  CASE 
    WHEN at.table_name = 'tenants' THEN 1
    WHEN at.table_name LIKE '%migrations%' THEN 1
    WHEN at.table_name LIKE 'schema_%' THEN 1
    ELSE 0
  END,
  at.table_name;
