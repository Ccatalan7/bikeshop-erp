-- Clean up test user - SIMPLE VERSION (for database without user_profiles table yet)
-- User ID: feacb156-140b-49ac-82c9-05aa38607b7b
-- Email: ccatalan.us@gmail.com

-- NOTE: This is a simplified version since user_profiles table doesn't exist yet
-- After deploying core_schema.sql, the full multi-tenant structure will be available

-- Step 1: Delete from auth.users (Supabase auth table)
DELETE FROM auth.users WHERE id = 'feacb156-140b-49ac-82c9-05aa38607b7b';

-- Step 2: Delete from tenants table if it exists
DELETE FROM tenants WHERE owner_email = 'ccatalan.us@gmail.com';

-- Verify deletion
SELECT 'Deleted user from auth.users' as status;

-- Check if user still exists
SELECT 
  CASE 
    WHEN COUNT(*) = 0 THEN '✅ User deleted successfully'
    ELSE '❌ User still exists'
  END as result
FROM auth.users 
WHERE id = 'feacb156-140b-49ac-82c9-05aa38607b7b';
