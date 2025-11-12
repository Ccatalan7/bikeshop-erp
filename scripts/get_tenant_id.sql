-- ====================================================================================================
-- FIND YOUR TENANT_ID
-- ====================================================================================================
-- Run this query first to find your tenant_id, then use it in factory_reset.sql

SELECT 
  id as tenant_id,
  subdomain,
  created_at
FROM tenants
ORDER BY created_at DESC;

-- Copy the 'tenant_id' UUID from the result above
-- Example: 12345678-1234-1234-1234-123456789abc

-- OR if you know your user email, find tenant via user_profiles:
-- SELECT 
--   up.tenant_id,
--   t.subdomain,
--   up.email,
--   up.role
-- FROM user_profiles up
-- JOIN tenants t ON up.tenant_id = t.id
-- WHERE up.email = 'your.email@example.com';
