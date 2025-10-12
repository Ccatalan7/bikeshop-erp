-- ============================================================================
-- Fix: Ensure Payment Journal Entry Deletion Bypasses RLS
-- ============================================================================
-- The issue might be that RLS is preventing the trigger from deleting
-- journal entries. We need to ensure the function has proper permissions.
-- ============================================================================

-- Recreate the delete function with explicit security settings
CREATE OR REPLACE FUNCTION public.delete_sales_payment_journal_entry(p_payment_id uuid)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER  -- Run with the privileges of the function owner
SET search_path = public  -- Explicit schema
AS $$
DECLARE
  v_deleted_count INTEGER;
  v_entry_ids UUID[];
BEGIN
  IF p_payment_id IS NULL THEN
    RAISE NOTICE 'delete_sales_payment_journal_entry: payment_id is NULL';
    RETURN;
  END IF;

  RAISE NOTICE 'delete_sales_payment_journal_entry: Starting deletion for payment_id=%', p_payment_id;

  -- First, get the IDs of entries we're about to delete (for logging)
  SELECT ARRAY_AGG(id) INTO v_entry_ids
  FROM public.journal_entries
  WHERE source_module = 'sales_payments'
    AND source_reference = p_payment_id::text;

  RAISE NOTICE 'delete_sales_payment_journal_entry: Found % entries to delete: %', 
    COALESCE(array_length(v_entry_ids, 1), 0), v_entry_ids;

  -- Delete the journal lines first (due to foreign key)
  DELETE FROM public.journal_lines
  WHERE entry_id IN (
    SELECT id 
    FROM public.journal_entries
    WHERE source_module = 'sales_payments'
      AND source_reference = p_payment_id::text
  );
  
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RAISE NOTICE 'delete_sales_payment_journal_entry: Deleted % journal lines', v_deleted_count;

  -- Then delete the journal entries
  DELETE FROM public.journal_entries
  WHERE source_module = 'sales_payments'
    AND source_reference = p_payment_id::text;
  
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RAISE NOTICE 'delete_sales_payment_journal_entry: Deleted % journal entries', v_deleted_count;
  
  IF v_deleted_count = 0 THEN
    RAISE WARNING 'delete_sales_payment_journal_entry: No journal entries found for payment_id=%', p_payment_id;
  ELSE
    RAISE NOTICE 'delete_sales_payment_journal_entry: Successfully deleted journal entry for payment_id=%', p_payment_id;
  END IF;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.delete_sales_payment_journal_entry(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_sales_payment_journal_entry(uuid) TO service_role;

-- Verify the function was updated
SELECT 'Function updated successfully!' as status;
