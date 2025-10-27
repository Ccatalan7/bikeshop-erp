-- Check if the auth trigger still exists
SELECT 
    trigger_name,
    event_object_table,
    action_statement,
    action_timing,
    event_manipulation
FROM information_schema.triggers
WHERE event_object_schema = 'auth'
  AND event_object_table = 'users';

-- Check if handle_new_user function exists
SELECT proname, prosrc 
FROM pg_proc 
WHERE proname = 'handle_new_user';

-- List all triggers on auth.users
SELECT * FROM pg_trigger 
WHERE tgrelid = 'auth.users'::regclass;
