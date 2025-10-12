-- ============================================================================
-- Final Fix: Ensure Trigger Bypasses RLS for Journal Entry Deletion
-- ============================================================================

-- Check current RLS policies on journal_entries
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE tablename IN ('journal_entries', 'journal_lines')
ORDER BY tablename, policyname;

-- The delete function MUST use SECURITY DEFINER to bypass RLS
-- Let's recreate it one more time with absolute certainty
CREATE OR REPLACE FUNCTION public.delete_sales_payment_journal_entry(p_payment_id uuid)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER  -- This is CRITICAL - runs as the function owner, not the caller
SET search_path = public
AS $$
DECLARE
  v_entry_id UUID;
  v_entry_number TEXT;
  v_lines_deleted INTEGER := 0;
  v_entry_deleted INTEGER := 0;
BEGIN
  IF p_payment_id IS NULL THEN
    RETURN;
  END IF;

  -- Get the journal entry details
  SELECT id, entry_number INTO v_entry_id, v_entry_number
  FROM public.journal_entries
  WHERE source_module = 'sales_payments'
    AND source_reference = p_payment_id::text
  LIMIT 1;

  IF v_entry_id IS NULL THEN
    -- No journal entry found, nothing to delete
    RETURN;
  END IF;

  -- Delete journal lines (bypasses RLS because of SECURITY DEFINER)
  DELETE FROM public.journal_lines
  WHERE entry_id = v_entry_id;
  
  GET DIAGNOSTICS v_lines_deleted = ROW_COUNT;

  -- Delete the journal entry (bypasses RLS because of SECURITY DEFINER)
  DELETE FROM public.journal_entries
  WHERE id = v_entry_id;
  
  GET DIAGNOSTICS v_entry_deleted = ROW_COUNT;

  RAISE NOTICE 'Deleted payment journal entry % (% lines, % entry)', 
    v_entry_number, v_lines_deleted, v_entry_deleted;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Error deleting payment journal entry: %', SQLERRM;
END;
$$;

-- Grant execute to authenticated (the role used by Supabase Auth)
GRANT EXECUTE ON FUNCTION public.delete_sales_payment_journal_entry(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_sales_payment_journal_entry(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.delete_sales_payment_journal_entry(uuid) TO service_role;

-- Verify
SELECT '✅ Function recreated with SECURITY DEFINER and proper grants' as status;
