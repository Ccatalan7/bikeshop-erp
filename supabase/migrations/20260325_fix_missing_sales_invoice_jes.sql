-- =============================================================================
-- Migration: Create missing journal entries for 2 posted sales invoices
--
-- ROOT CAUSE
-- ----------
-- Two sales invoices with status='sent' exist without journal entries.
-- Both are no_tax invoices (iva_amount=0). Exact cause unknown (likely created
-- during a period when the trigger was disabled or the function exited early).
--
--   FV-00457  total=155,000  customer=Belén Gardaix    date=2026-03-18
--   FV-00406  total=4,000    customer=Felipe Díaz       date=2026-02-28
--
-- FIX
-- ---
-- Touch (UPDATE) both rows to fire trg_sales_invoices_change → handle_sales_invoice_change()
-- → create_sales_invoice_journal_entry(). The function has a duplicate guard
-- (checks source_reference in journal_entries) so this is safe to run multiple
-- times — it will only create a JE if none exists.
-- =============================================================================

UPDATE public.sales_invoices
SET updated_at = now()
WHERE tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  AND invoice_number IN ('FV-00457', 'FV-00406')
  AND status NOT IN ('draft', 'cancelled');

-- Verify both JEs were created
DO $$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.journal_entries
  WHERE tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    AND source_module = 'sales_invoices'
    AND source_reference IN ('FV-00457', 'FV-00406');

  IF v_count = 2 THEN
    RAISE NOTICE '✅ Both journal entries created successfully (FV-00457, FV-00406)';
  ELSIF v_count = 1 THEN
    RAISE WARNING '⚠️  Only 1 of 2 journal entries was created — check the other invoice manually';
  ELSE
    RAISE WARNING '❌ No journal entries created — check trigger and function status';
  END IF;
END $$;
