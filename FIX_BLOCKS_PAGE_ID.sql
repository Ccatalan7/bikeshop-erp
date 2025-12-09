-- FIX: Update website_blocks that are missing page_id
-- This happens when blocks were saved with the old saveBlocks() method
-- that didn't include page_id

-- Step 1: Find blocks without page_id and assign them to their tenant's home page
UPDATE website_blocks wb
SET page_id = (
  SELECT wp.id 
  FROM website_pages wp 
  WHERE wp.tenant_id = wb.tenant_id 
    AND wp.is_home = true 
  LIMIT 1
)
WHERE wb.page_id IS NULL;

-- Step 2: For tenants that don't have a home page yet, create one
-- First, insert home pages for tenants that have blocks but no home page
INSERT INTO website_pages (tenant_id, slug, title, is_home, is_published, is_system)
SELECT DISTINCT wb.tenant_id, 'home', 'Inicio', true, true, true
FROM website_blocks wb
WHERE wb.page_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM website_pages wp 
    WHERE wp.tenant_id = wb.tenant_id AND wp.is_home = true
  );

-- Step 3: Now update the remaining blocks that still don't have page_id
UPDATE website_blocks wb
SET page_id = (
  SELECT wp.id 
  FROM website_pages wp 
  WHERE wp.tenant_id = wb.tenant_id 
    AND wp.is_home = true 
  LIMIT 1
)
WHERE wb.page_id IS NULL;

-- Verify: Check if any blocks still don't have page_id
SELECT COUNT(*) as orphan_blocks FROM website_blocks WHERE page_id IS NULL;
