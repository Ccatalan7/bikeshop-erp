-- EMERGENCY FIX: Disable all auth.users triggers to allow signup
-- Run this in Supabase SQL Editor

-- Step 1: Drop ALL triggers on auth.users
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN 
    SELECT tgname 
    FROM pg_trigger 
    WHERE tgrelid = 'auth.users'::regclass
      AND tgname NOT LIKE 'pg_%'  -- Don't drop system triggers
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON auth.users', r.tgname);
    RAISE NOTICE 'Dropped trigger: %', r.tgname;
  END LOOP;
END $$;

-- Step 2: Verify no custom triggers remain
SELECT 
    tgname as trigger_name,
    pg_get_triggerdef(oid) as trigger_definition
FROM pg_trigger 
WHERE tgrelid = 'auth.users'::regclass
  AND tgname NOT LIKE 'pg_%';

-- Expected: No results (all custom triggers removed)

-- Step 3: Check if handle_new_user function still exists (it's ok if it does, just not being triggered)
SELECT 
  'handle_new_user function exists: ' || 
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'handle_new_user'
  ) THEN 'YES (but not triggered)' ELSE 'NO' END as status;

RAISE NOTICE '✅ All auth triggers have been removed';
RAISE NOTICE '✅ Signup should now work - tenant creation will happen in Flutter app';
