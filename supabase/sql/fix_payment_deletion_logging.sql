-- ============================================================================
-- Fix: Add Logging to Payment Journal Entry Deletion
-- ============================================================================

CREATE OR REPLACE FUNCTION public.delete_sales_payment_journal_entry(p_payment_id uuid)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted_count INTEGER;
BEGIN
  IF p_payment_id IS NULL THEN
    RAISE NOTICE 'delete_sales_payment_journal_entry: payment_id is NULL';
    RETURN;
  END IF;

  RAISE NOTICE 'delete_sales_payment_journal_entry: deleting for payment_id=%', p_payment_id;

  -- Delete journal entries for this payment
  DELETE FROM public.journal_entries
   WHERE source_module = 'sales_payments'
     AND source_reference = p_payment_id::text;
  
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  
  RAISE NOTICE 'delete_sales_payment_journal_entry: deleted % journal entries', v_deleted_count;
  
  IF v_deleted_count = 0 THEN
    RAISE NOTICE 'delete_sales_payment_journal_entry: WARNING - No journal entries found for payment_id=%', p_payment_id;
  END IF;
END;
$$;

-- Also add logging to the trigger
CREATE OR REPLACE FUNCTION public.handle_sales_payment_change()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    RAISE NOTICE 'handle_sales_payment_change: INSERT payment_id=%', NEW.id;
    PERFORM public.recalculate_sales_invoice_payments(NEW.invoice_id);
    PERFORM public.create_sales_payment_journal_entry(NEW);
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    RAISE NOTICE 'handle_sales_payment_change: UPDATE payment_id=%', NEW.id;
    IF NEW.invoice_id IS DISTINCT FROM OLD.invoice_id THEN
      PERFORM public.recalculate_sales_invoice_payments(OLD.invoice_id);
    END IF;
    PERFORM public.delete_sales_payment_journal_entry(OLD.id);
    PERFORM public.recalculate_sales_invoice_payments(NEW.invoice_id);
    PERFORM public.create_sales_payment_journal_entry(NEW);
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    RAISE NOTICE 'handle_sales_payment_change: DELETE payment_id=%, invoice_id=%', OLD.id, OLD.invoice_id;
    PERFORM public.delete_sales_payment_journal_entry(OLD.id);
    PERFORM public.recalculate_sales_invoice_payments(OLD.invoice_id);
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;
