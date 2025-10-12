-- ============================================================================
-- Fix: Recreate Sales Payment Trigger (Force)
-- ============================================================================
-- This will drop and recreate the trigger to ensure it works properly
-- ============================================================================

-- Drop the trigger if it exists
DROP TRIGGER IF EXISTS trg_sales_payments_change ON public.sales_payments;

-- Recreate the trigger function with proper logic
CREATE OR REPLACE FUNCTION public.handle_sales_payment_change()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    RAISE NOTICE 'handle_sales_payment_change: INSERT payment_id=%', NEW.id;
    PERFORM public.create_sales_payment_journal_entry(NEW);
    PERFORM public.recalculate_sales_invoice_payments(NEW.invoice_id);
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    RAISE NOTICE 'handle_sales_payment_change: UPDATE payment_id=%', NEW.id;
    -- Delete old journal entry
    PERFORM public.delete_sales_payment_journal_entry(OLD.id);
    -- Create new journal entry
    PERFORM public.create_sales_payment_journal_entry(NEW);
    -- Recalculate for old invoice if changed
    IF NEW.invoice_id IS DISTINCT FROM OLD.invoice_id THEN
      PERFORM public.recalculate_sales_invoice_payments(OLD.invoice_id);
    END IF;
    -- Recalculate for new invoice
    PERFORM public.recalculate_sales_invoice_payments(NEW.invoice_id);
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    RAISE NOTICE 'handle_sales_payment_change: DELETE payment_id=%, invoice_id=%', OLD.id, OLD.invoice_id;
    -- Delete journal entry
    PERFORM public.delete_sales_payment_journal_entry(OLD.id);
    -- Recalculate invoice
    PERFORM public.recalculate_sales_invoice_payments(OLD.invoice_id);
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger
CREATE TRIGGER trg_sales_payments_change
  AFTER INSERT OR UPDATE OR DELETE ON public.sales_payments
  FOR EACH ROW 
  EXECUTE FUNCTION public.handle_sales_payment_change();

-- Verify the trigger was created
SELECT 
  'Trigger created successfully!' as status,
  tgname as trigger_name,
  tgenabled as enabled,
  tgtype as type
FROM pg_trigger
WHERE tgrelid = 'public.sales_payments'::regclass
  AND tgname = 'trg_sales_payments_change';
