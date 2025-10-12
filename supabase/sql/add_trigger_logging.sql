-- ============================================================================
-- Fix: Add Comprehensive Logging to Payment Trigger
-- ============================================================================

-- Recreate the trigger function with extensive logging
CREATE OR REPLACE FUNCTION public.handle_sales_payment_change()
RETURNS TRIGGER AS $$
BEGIN
  RAISE NOTICE '======================================== TRIGGER START ========================================';
  RAISE NOTICE 'Trigger fired: TG_OP=%, TG_TABLE_NAME=%', TG_OP, TG_TABLE_NAME;
  
  IF TG_OP = 'INSERT' THEN
    RAISE NOTICE 'INSERT operation - payment_id=%, invoice_id=%, amount=%', NEW.id, NEW.invoice_id, NEW.amount;
    RAISE NOTICE 'Calling create_sales_payment_journal_entry...';
    PERFORM public.create_sales_payment_journal_entry(NEW);
    RAISE NOTICE 'Calling recalculate_sales_invoice_payments...';
    PERFORM public.recalculate_sales_invoice_payments(NEW.invoice_id);
    RAISE NOTICE 'INSERT completed successfully';
    RETURN NEW;
    
  ELSIF TG_OP = 'UPDATE' THEN
    RAISE NOTICE 'UPDATE operation - payment_id=%', NEW.id;
    RAISE NOTICE 'Deleting old journal entry for payment_id=%', OLD.id;
    PERFORM public.delete_sales_payment_journal_entry(OLD.id);
    RAISE NOTICE 'Creating new journal entry for payment_id=%', NEW.id;
    PERFORM public.create_sales_payment_journal_entry(NEW);
    IF NEW.invoice_id IS DISTINCT FROM OLD.invoice_id THEN
      RAISE NOTICE 'Invoice changed, recalculating old invoice=%', OLD.invoice_id;
      PERFORM public.recalculate_sales_invoice_payments(OLD.invoice_id);
    END IF;
    RAISE NOTICE 'Recalculating new invoice=%', NEW.invoice_id;
    PERFORM public.recalculate_sales_invoice_payments(NEW.invoice_id);
    RAISE NOTICE 'UPDATE completed successfully';
    RETURN NEW;
    
  ELSIF TG_OP = 'DELETE' THEN
    RAISE NOTICE '🔴 DELETE operation triggered!';
    RAISE NOTICE '🔴 Deleting payment_id=%, invoice_id=%, amount=%', OLD.id, OLD.invoice_id, OLD.amount;
    RAISE NOTICE '🔴 Calling delete_sales_payment_journal_entry for payment_id=%', OLD.id;
    PERFORM public.delete_sales_payment_journal_entry(OLD.id);
    RAISE NOTICE '🔴 Calling recalculate_sales_invoice_payments for invoice_id=%', OLD.invoice_id;
    PERFORM public.recalculate_sales_invoice_payments(OLD.invoice_id);
    RAISE NOTICE '🔴 DELETE completed successfully';
    RETURN OLD;
  END IF;
  
  RAISE NOTICE '======================================== TRIGGER END ========================================';
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Ensure trigger exists and is enabled
DROP TRIGGER IF EXISTS trg_sales_payments_change ON public.sales_payments;

CREATE TRIGGER trg_sales_payments_change
  AFTER INSERT OR UPDATE OR DELETE ON public.sales_payments
  FOR EACH ROW 
  EXECUTE FUNCTION public.handle_sales_payment_change();

-- Verify trigger was created
SELECT 
  t.tgname as trigger_name,
  CASE t.tgenabled 
    WHEN 'O' THEN 'Enabled ✅'
    WHEN 'D' THEN 'Disabled ❌'
    ELSE 'Unknown'
  END as status,
  t.tgtype,
  p.proname as function_name
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
WHERE t.tgrelid = 'public.sales_payments'::regclass
  AND t.tgname = 'trg_sales_payments_change';

SELECT '✅ Trigger updated with logging. Now delete a payment and check Supabase Logs!' as message;
