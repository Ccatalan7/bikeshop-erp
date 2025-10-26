-- Check for duplicate settings in company_settings table
-- Run this in Supabase SQL Editor: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/sql

-- 1. Check for duplicate (tenant_id, key) pairs
SELECT 
  tenant_id,
  key,
  COUNT(*) as count,
  array_agg(id) as duplicate_ids,
  array_agg(value) as values
FROM company_settings
GROUP BY tenant_id, key
HAVING COUNT(*) > 1;
-- Expected: 0 rows (no duplicates)
-- If duplicates exist, this is the root cause of 409 errors

-- 2. Check all settings for your tenant
SELECT 
  id,
  tenant_id,
  key,
  value,
  created_at,
  updated_at
FROM company_settings
WHERE tenant_id = '5fb195aa-2ec5-4a5d-b057-ed61156312ec'
ORDER BY key, created_at;
-- Shows all settings for your tenant

-- 3. DELETE duplicates (if found) - RUN THIS ONLY IF DUPLICATES EXIST
-- Keep the most recent one, delete older ones
/*
DELETE FROM company_settings
WHERE id IN (
  SELECT id
  FROM (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY tenant_id, key ORDER BY updated_at DESC) as rn
    FROM company_settings
  ) sub
  WHERE rn > 1
);
*/

-- 4. Verify unique constraint exists
SELECT
  conname as constraint_name,
  pg_get_constraintdef(oid) as constraint_definition
FROM pg_constraint
WHERE conrelid = 'company_settings'::regclass
  AND contype = 'u';
-- Expected: unique(tenant_id, key)
