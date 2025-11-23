-- Phase 1 Verification: Check compatibility metadata in categories
-- Run this in Supabase SQL Editor

-- Test 1: Verify columns exist
SELECT 
  column_name, 
  data_type 
FROM information_schema.columns 
WHERE table_name = 'product_categories' 
  AND column_name IN ('compatibility_metadata', 'discipline_scope', 'icon_name')
ORDER BY column_name;

-- Expected: 3 rows (compatibility_metadata: jsonb, discipline_scope: text[], icon_name: text)

-- Test 2: Count categories with metadata
SELECT 
  COUNT(*) as total_categories,
  COUNT(compatibility_metadata) as categories_with_metadata,
  COUNT(discipline_scope) as categories_with_discipline,
  COUNT(icon_name) as categories_with_icon
FROM product_categories
WHERE tenant_id = '5de4e246-f30d-4614-b571-6fc146274cfb';

-- Expected: 144 total, 23 with metadata, 23 with discipline, 23 with icon

-- Test 3: List all categories with metadata
SELECT 
  name,
  full_path,
  compatibility_metadata->>'component_code' as component_code,
  discipline_scope,
  icon_name,
  jsonb_array_length(compatibility_metadata->'attributes') as attribute_count
FROM product_categories
WHERE tenant_id = '5de4e246-f30d-4614-b571-6fc146274cfb'
  AND compatibility_metadata IS NOT NULL
ORDER BY full_path;

-- Expected: 23 rows showing all mapped components

-- Test 4: Deep dive into one category (Cassette)
SELECT 
  name,
  full_path,
  compatibility_metadata
FROM product_categories
WHERE tenant_id = '5de4e246-f30d-4614-b571-6fc146274cfb'
  AND name = 'Cassette'
  AND compatibility_metadata IS NOT NULL;

-- Expected: JSON with component_code='cassette', 4 attributes (speeds, range_min, range_max, freehub_standard)

-- Test 5: Verify attribute structure for Mazas (Hubs)
SELECT 
  name,
  jsonb_pretty(compatibility_metadata) as metadata
FROM product_categories
WHERE tenant_id = '5de4e246-f30d-4614-b571-6fc146274cfb'
  AND name = 'Mazas'
  AND compatibility_metadata IS NOT NULL;

-- Expected: 10 attributes including spoke_holes, hub_spacing_mm, axle_type, freehub_standard, brake_interface, flange measurements

-- Test 6: Validate all components have required fields
SELECT 
  name,
  full_path,
  compatibility_metadata->>'component_code' as component_code,
  CASE 
    WHEN compatibility_metadata ? 'attributes' THEN '✅'
    ELSE '❌'
  END as has_attributes,
  CASE 
    WHEN compatibility_metadata ? 'discipline_scope' THEN '✅'
    ELSE '❌'
  END as has_discipline_scope,
  CASE 
    WHEN compatibility_metadata ? 'icon_name' THEN '✅'
    ELSE '❌'
  END as has_icon_name
FROM product_categories
WHERE tenant_id = '5de4e246-f30d-4614-b571-6fc146274cfb'
  AND compatibility_metadata IS NOT NULL
ORDER BY full_path;

-- Expected: All rows show ✅ for all three fields
