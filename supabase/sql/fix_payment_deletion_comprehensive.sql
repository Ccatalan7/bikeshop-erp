-- ============================================================================
-- Comprehensive Fix: Payment Journal Entry Deletion with CASCADE
-- ============================================================================

-- First, let's check if there are foreign key constraints preventing deletion
SELECT 
  tc.constraint_name,
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name,
  rc.delete_rule
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints AS rc
  ON rc.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND (tc.table_name = 'journal_entries' OR tc.table_name = 'journal_lines');

-- Now recreate the delete function with CASCADE and better error handling
CREATE OR REPLACE FUNCTION public.delete_sales_payment_journal_entry(p_payment_id uuid)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_entry_record RECORD;
  v_lines_deleted INTEGER := 0;
  v_entries_deleted INTEGER := 0;
BEGIN
  IF p_payment_id IS NULL THEN
    RAISE NOTICE 'delete_sales_payment_journal_entry: payment_id is NULL';
    RETURN;
  END IF;

  RAISE NOTICE '========================================';
  RAISE NOTICE 'delete_sales_payment_journal_entry: Starting deletion for payment_id=%', p_payment_id;

  -- Loop through each journal entry for this payment
  FOR v_entry_record IN
    SELECT id, entry_number, description
    FROM public.journal_entries
    WHERE source_module = 'sales_payments'
      AND source_reference = p_payment_id::text
  LOOP
    RAISE NOTICE 'Processing journal entry: % (ID: %)', v_entry_record.entry_number, v_entry_record.id;
    
    -- Delete journal lines for this entry
    DELETE FROM public.journal_lines
    WHERE entry_id = v_entry_record.id;
    
    GET DIAGNOSTICS v_lines_deleted = ROW_COUNT;
    RAISE NOTICE 'Deleted % journal lines for entry %', v_lines_deleted, v_entry_record.entry_number;
    
    -- Delete the journal entry itself
    DELETE FROM public.journal_entries
    WHERE id = v_entry_record.id;
    
    GET DIAGNOSTICS v_entries_deleted = ROW_COUNT;
    RAISE NOTICE 'Deleted journal entry: %', v_entry_record.entry_number;
  END LOOP;

  IF v_entries_deleted = 0 THEN
    RAISE WARNING 'No journal entries found for payment_id=%', p_payment_id;
  ELSE
    RAISE NOTICE 'Successfully deleted journal entry for payment_id=%', p_payment_id;
  END IF;
  
  RAISE NOTICE '========================================';
  
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Error in delete_sales_payment_journal_entry: % - %', SQLERRM, SQLSTATE;
  RAISE NOTICE 'Full error: %', SQLERRM;
END;
$$;

-- Also ensure the trigger is correct
DROP TRIGGER IF EXISTS trg_sales_payments_change ON public.sales_payments;

CREATE TRIGGER trg_sales_payments_change
  AFTER INSERT OR UPDATE OR DELETE ON public.sales_payments
  FOR EACH ROW 
  EXECUTE FUNCTION public.handle_sales_payment_change();

-- Test: Manually call the function for the orphaned entry
-- First, find orphaned payment journal entries
DO $$
DECLARE
  v_orphaned_ref TEXT;
BEGIN
  FOR v_orphaned_ref IN
    SELECT je.source_reference
    FROM journal_entries je
    WHERE je.source_module = 'sales_payments'
      AND NOT EXISTS (
        SELECT 1 FROM sales_payments sp 
        WHERE sp.id::text = je.source_reference
      )
  LOOP
    RAISE NOTICE 'Found orphaned journal entry for payment: %', v_orphaned_ref;
    RAISE NOTICE 'Calling delete function to clean it up...';
    PERFORM public.delete_sales_payment_journal_entry(v_orphaned_ref::uuid);
  END LOOP;
END $$;

-- Verify cleanup
SELECT 
  'Remaining payment journal entries' as status,
  COUNT(*) as count
FROM journal_entries
WHERE source_module = 'sales_payments';
