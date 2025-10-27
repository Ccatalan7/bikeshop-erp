-- ============================================================================
-- ENABLE AUTO-SIGNUP TRIGGER
-- ============================================================================
-- This will automatically create tenant + user_profile when users sign up
-- No need for Flutter to handle tenant creation
-- ============================================================================

-- Create trigger on new user signup
CREATE TRIGGER on_auth_user_created
  BEFORE INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Verify trigger exists
SELECT 
  tgname as trigger_name,
  tgenabled as enabled,
  proname as function_name
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE tgname = 'on_auth_user_created';

-- ============================================================================
-- ✅ Done! Now signup will automatically create tenants
-- ============================================================================
