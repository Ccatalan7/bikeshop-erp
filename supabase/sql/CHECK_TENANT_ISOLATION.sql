-- Check which tenant ccatalansandoval7@gmail.com belongs to
SELECT 
  id,
  email,
  raw_app_meta_data->>'tenant_id' as tenant_id,
  raw_app_meta_data->>'role' as role
FROM auth.users
WHERE email = 'ccatalansandoval7@gmail.com';

-- Verify tenant list
SELECT * FROM tenants ORDER BY created_at;

-- Check which tables have tenant_id column
SELECT 
  table_name,
  column_name
FROM information_schema.columns
WHERE column_name = 'tenant_id'
  AND table_schema = 'public'
ORDER BY table_name;
