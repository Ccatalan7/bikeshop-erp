-- ============================================================================
-- Complete Fix: Payment Journal Entry Deletion on Payment Reversal
-- ============================================================================
-- Problem: When deleting a payment (Paid → Confirmed), the payment record 
--          is deleted but the payment journal entry remains orphaned.
--
-- Root Cause: The delete_sales_payment_journal_entry function may not be 
--             bypassing RLS or the trigger might not be firing correctly.
--
-- Solution: Recreate the function with SECURITY DEFINER, proper grants,
--           and verify the trigger is configured correctly.
-- ============================================================================

-- ============================================================================
-- Step 1: Check current state
-- ============================================================================
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Diagnosing Payment Journal Entry Deletion Issue';
  RAISE NOTICE '========================================';
END $$;

-- Check for orphaned payment journal entries
SELECT 
  'Orphaned payment journal entries found:' as status,
  COUNT(*) as count
FROM journal_entries je
WHERE je.source_module = 'sales_payments'
  AND NOT EXISTS (
    SELECT 1 FROM sales_payments sp 
    WHERE sp.id::text = je.source_reference
  );

-- ============================================================================
-- Step 2: Recreate the deletion function with absolute certainty
-- ============================================================================
CREATE OR REPLACE FUNCTION public.delete_sales_payment_journal_entry(p_payment_id uuid)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER  -- CRITICAL: This bypasses RLS and runs as function owner
SET search_path = public
AS $$
DECLARE
  v_entry_ids UUID[];
  v_lines_deleted INTEGER := 0;
  v_entries_deleted INTEGER := 0;
BEGIN
  -- Validate input
  IF p_payment_id IS NULL THEN
    RAISE WARNING 'delete_sales_payment_journal_entry: payment_id is NULL';
    RETURN;
  END IF;

  RAISE NOTICE 'delete_sales_payment_journal_entry: Deleting for payment_id=%', p_payment_id;

  -- Get all journal entry IDs for this payment
  SELECT ARRAY_AGG(id) INTO v_entry_ids
  FROM public.journal_entries
  WHERE source_module = 'sales_payments'
    AND source_reference = p_payment_id::text;

  IF v_entry_ids IS NULL OR array_length(v_entry_ids, 1) IS NULL THEN
    RAISE NOTICE 'delete_sales_payment_journal_entry: No journal entries found for payment_id=%', p_payment_id;
    RETURN;
  END IF;

  RAISE NOTICE 'delete_sales_payment_journal_entry: Found % entries to delete', array_length(v_entry_ids, 1);

  -- Delete journal lines first (child records)
  DELETE FROM public.journal_lines
  WHERE entry_id = ANY(v_entry_ids);
  
  GET DIAGNOSTICS v_lines_deleted = ROW_COUNT;
  RAISE NOTICE 'delete_sales_payment_journal_entry: Deleted % journal lines', v_lines_deleted;

  -- Delete the journal entries (parent records)
  DELETE FROM public.journal_entries
  WHERE id = ANY(v_entry_ids);
  
  GET DIAGNOSTICS v_entries_deleted = ROW_COUNT;
  RAISE NOTICE 'delete_sales_payment_journal_entry: Deleted % journal entries', v_entries_deleted;

  IF v_entries_deleted = 0 THEN
    RAISE WARNING 'delete_sales_payment_journal_entry: Expected to delete entries but none were deleted!';
  END IF;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'delete_sales_payment_journal_entry: Error - % (%)', SQLERRM, SQLSTATE;
  -- Don't re-raise, allow the payment deletion to proceed
END;
$$;

-- ============================================================================
-- Step 3: Grant execution permissions to all relevant roles
-- ============================================================================
GRANT EXECUTE ON FUNCTION public.delete_sales_payment_journal_entry(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_sales_payment_journal_entry(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.delete_sales_payment_journal_entry(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.delete_sales_payment_journal_entry(uuid) TO postgres;

-- ============================================================================
-- Step 4: Verify and recreate the payment trigger
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_sales_payment_change()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE NOTICE 'handle_sales_payment_change: Operation=%, payment_id=%', 
    TG_OP, COALESCE(NEW.id::text, OLD.id::text);

  IF TG_OP = 'INSERT' THEN
    RAISE NOTICE 'handle_sales_payment_change: INSERT - Creating journal entry';
    PERFORM public.recalculate_sales_invoice_payments(NEW.invoice_id);
    PERFORM public.create_sales_payment_journal_entry(NEW);
    RETURN NEW;
    
  ELSIF TG_OP = 'UPDATE' THEN
    RAISE NOTICE 'handle_sales_payment_change: UPDATE - Recreating journal entry';
    IF NEW.invoice_id IS DISTINCT FROM OLD.invoice_id THEN
      PERFORM public.recalculate_sales_invoice_payments(OLD.invoice_id);
    END IF;
    PERFORM public.delete_sales_payment_journal_entry(OLD.id);
    PERFORM public.recalculate_sales_invoice_payments(NEW.invoice_id);
    PERFORM public.create_sales_payment_journal_entry(NEW);
    RETURN NEW;
    
  ELSIF TG_OP = 'DELETE' THEN
    RAISE NOTICE 'handle_sales_payment_change: DELETE - Deleting journal entry and recalculating';
    
    -- Delete the payment journal entry FIRST
    PERFORM public.delete_sales_payment_journal_entry(OLD.id);
    
    -- Then recalculate invoice payments (which updates invoice status)
    PERFORM public.recalculate_sales_invoice_payments(OLD.invoice_id);
    
    RAISE NOTICE 'handle_sales_payment_change: DELETE completed for payment_id=%', OLD.id;
    RETURN OLD;
  END IF;
  
  RETURN NULL;
END;
$$;

-- ============================================================================
-- Step 5: Drop and recreate the trigger to ensure it's using the latest function
-- ============================================================================
DROP TRIGGER IF EXISTS trg_sales_payments_change ON public.sales_payments;

CREATE TRIGGER trg_sales_payments_change
  AFTER INSERT OR UPDATE OR DELETE ON public.sales_payments
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_sales_payment_change();

-- ============================================================================
-- Step 6: Clean up any existing orphaned payment journal entries
-- ============================================================================
DO $$
DECLARE
  v_orphaned_count INTEGER;
  v_orphaned_ref TEXT;
BEGIN
  -- Find and delete orphaned payment journal entries
  FOR v_orphaned_ref IN 
    SELECT je.source_reference
    FROM journal_entries je
    WHERE je.source_module = 'sales_payments'
      AND NOT EXISTS (
        SELECT 1 FROM sales_payments sp 
        WHERE sp.id::text = je.source_reference
      )
  LOOP
    RAISE NOTICE 'Cleaning up orphaned payment journal entry: %', v_orphaned_ref;
    PERFORM public.delete_sales_payment_journal_entry(v_orphaned_ref::uuid);
  END LOOP;

  -- Count remaining orphans
  SELECT COUNT(*) INTO v_orphaned_count
  FROM journal_entries je
  WHERE je.source_module = 'sales_payments'
    AND NOT EXISTS (
      SELECT 1 FROM sales_payments sp 
      WHERE sp.id::text = je.source_reference
    );

  IF v_orphaned_count = 0 THEN
    RAISE NOTICE '✅ All orphaned payment journal entries cleaned up';
  ELSE
    RAISE WARNING '⚠️  Still have % orphaned payment journal entries', v_orphaned_count;
  END IF;
END $$;

-- ============================================================================
-- Step 7: Verification
-- ============================================================================
DO $$
DECLARE
  v_function_exists BOOLEAN;
  v_trigger_exists BOOLEAN;
  v_function_is_security_definer BOOLEAN;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Verification Results';
  RAISE NOTICE '========================================';

  -- Check function exists
  SELECT EXISTS (
    SELECT 1 FROM pg_proc 
    WHERE proname = 'delete_sales_payment_journal_entry'
      AND pronamespace = 'public'::regnamespace
  ) INTO v_function_exists;

  -- Check if function has SECURITY DEFINER
  SELECT prosecdef INTO v_function_is_security_definer
  FROM pg_proc 
  WHERE proname = 'delete_sales_payment_journal_entry'
    AND pronamespace = 'public'::regnamespace;

  -- Check trigger exists
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE t.tgname = 'trg_sales_payments_change'
      AND c.relname = 'sales_payments'
  ) INTO v_trigger_exists;

  IF v_function_exists THEN
    RAISE NOTICE '✅ Function delete_sales_payment_journal_entry exists';
  ELSE
    RAISE WARNING '❌ Function delete_sales_payment_journal_entry NOT FOUND';
  END IF;

  IF v_function_is_security_definer THEN
    RAISE NOTICE '✅ Function has SECURITY DEFINER (bypasses RLS)';
  ELSE
    RAISE WARNING '❌ Function does NOT have SECURITY DEFINER';
  END IF;

  IF v_trigger_exists THEN
    RAISE NOTICE '✅ Trigger trg_sales_payments_change exists';
  ELSE
    RAISE WARNING '❌ Trigger trg_sales_payments_change NOT FOUND';
  END IF;

  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ Payment journal entry deletion fix applied!';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Test the fix:';
  RAISE NOTICE '1. Create a sales invoice and confirm it';
  RAISE NOTICE '2. Register a payment (status → paid)';
  RAISE NOTICE '3. Delete the payment via "Deshacer pago" button';
  RAISE NOTICE '4. Check Contabilidad > Asientos Contables';
  RAISE NOTICE '5. The payment journal entry should be DELETED';
  RAISE NOTICE '';
END $$;

-- ============================================================================
-- Step 8: Show current payment journal entries for reference
-- ============================================================================
SELECT 
  '📋 Current payment journal entries:' as info,
  je.entry_number,
  je.description,
  sp.id as payment_id,
  sp.amount,
  si.invoice_number,
  si.status as invoice_status
FROM journal_entries je
LEFT JOIN sales_payments sp ON sp.id::text = je.source_reference
LEFT JOIN sales_invoices si ON si.id = sp.invoice_id
WHERE je.source_module = 'sales_payments'
ORDER BY je.created_at DESC
LIMIT 10;
