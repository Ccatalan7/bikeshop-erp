-- Get all users (with their authentication details) for tenant 46e169a4-ba62-4f86-92cd-778ece1b0afa

SELECT 
  au.id as user_id,
  au.email,
  au.created_at as user_created_at,
  au.email_confirmed_at,
  au.last_sign_in_at,
  up.id as profile_id,
  up.tenant_id,
  t.name as tenant_name,
  t.subdomain,
  up.role,
  up.permissions,
  up.is_active
FROM auth.users au
JOIN user_profiles up ON au.id = up.user_id
JOIN tenants t ON up.tenant_id = t.id
WHERE up.tenant_id = '46e169a4-ba62-4f86-92cd-778ece1b0afa'::uuid
ORDER BY au.created_at DESC;

-- NOTE: Passwords are encrypted and stored in auth.users.encrypted_password
-- They CANNOT be retrieved in plain text for security reasons
-- You can only see email addresses that can be used to login
-- To access the account, you need to either:
--   1. Use the email shown above with the password you set during registration
--   2. Reset the password via Supabase Auth dashboard
--   3. Use Supabase CLI: supabase auth reset-password <email>
