-- ============================================================================
-- VERIFY ALL TABLES HAVE tenant_id
-- ============================================================================
-- This query checks ALL public tables and verifies they have tenant_id column
-- System tables (tenants, migrations, schema_*) are excluded as they should NOT have tenant_id

WITH all_tables AS (
  SELECT table_name 
  FROM information_schema.tables 
  WHERE table_schema = 'public' 
    AND table_type = 'BASE TABLE'
),
tables_with_tenant AS (
  SELECT DISTINCT table_name
  FROM information_schema.columns
  WHERE column_name = 'tenant_id'
    AND table_schema = 'public'
),
system_tables AS (
  SELECT unnest(ARRAY[
    'tenants',
    'migrations',
    'schema_migrations'
  ]) as table_name
)
SELECT 
  at.table_name,
  CASE 
    WHEN st.table_name IS NOT NULL THEN '✅ System table (no tenant_id needed)'
    WHEN twt.table_name IS NOT NULL THEN '✅ Has tenant_id'
    ELSE '❌ MISSING tenant_id - CRITICAL BUG!'
  END as status,
  CASE 
    WHEN st.table_name IS NOT NULL THEN 0
    WHEN twt.table_name IS NOT NULL THEN 1
    ELSE 2
  END as sort_order
FROM all_tables at
LEFT JOIN tables_with_tenant twt ON at.table_name = twt.table_name
LEFT JOIN system_tables st ON at.table_name = st.table_name
ORDER BY sort_order DESC, at.table_name;

-- ============================================================================
-- COUNT SUMMARY
-- ============================================================================

SELECT 
  COUNT(*) FILTER (WHERE status = '❌ MISSING tenant_id - CRITICAL BUG!') as missing_tenant_id,
  COUNT(*) FILTER (WHERE status = '✅ Has tenant_id') as has_tenant_id,
  COUNT(*) FILTER (WHERE status = '✅ System table (no tenant_id needed)') as system_tables,
  COUNT(*) as total_tables
FROM (
  WITH all_tables AS (
    SELECT table_name 
    FROM information_schema.tables 
    WHERE table_schema = 'public' 
      AND table_type = 'BASE TABLE'
  ),
  tables_with_tenant AS (
    SELECT DISTINCT table_name
    FROM information_schema.columns
    WHERE column_name = 'tenant_id'
      AND table_schema = 'public'
  ),
  system_tables AS (
    SELECT unnest(ARRAY[
      'tenants',
      'migrations',
      'schema_migrations'
    ]) as table_name
  )
  SELECT 
    at.table_name,
    CASE 
      WHEN st.table_name IS NOT NULL THEN '✅ System table (no tenant_id needed)'
      WHEN twt.table_name IS NOT NULL THEN '✅ Has tenant_id'
      ELSE '❌ MISSING tenant_id - CRITICAL BUG!'
    END as status
  FROM all_tables at
  LEFT JOIN tables_with_tenant twt ON at.table_name = twt.table_name
  LEFT JOIN system_tables st ON at.table_name = st.table_name
) summary;
