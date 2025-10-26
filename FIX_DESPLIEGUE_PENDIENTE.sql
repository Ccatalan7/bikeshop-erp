-- Fix "Despliegue Pendiente" stuck status
-- Run this in Supabase SQL Editor to manually set status to 'deployed'

-- Check current status
SELECT 
  tenant_id,
  website_status,
  website_subdomain,
  website_url,
  updated_at
FROM company_settings
WHERE website_status IS NOT NULL
ORDER BY updated_at DESC;

-- Update status to 'deployed' for all pending websites
UPDATE company_settings
SET website_status = 'deployed',
    updated_at = NOW()
WHERE website_status = 'pending';

-- Verify the update
SELECT 
  tenant_id,
  website_status,
  website_subdomain,
  website_url,
  updated_at
FROM company_settings
WHERE website_status IS NOT NULL
ORDER BY updated_at DESC;
