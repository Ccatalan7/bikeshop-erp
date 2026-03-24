-- =============================================================================
-- Cleanup: Remove test invoice TEST-IVA-001 and its journal entry from production
--
-- Created 2026-03-24 during IVA fix validation testing.
-- Fake invoice: customer="Cliente Prueba Fix", total=11900, status=confirmed
-- Created a real posted JE (AS-00822) with $11,900 on the books.
-- =============================================================================

-- 1. Delete journal lines first (FK constraint)
DELETE FROM public.journal_lines
WHERE entry_id = '6a7cd1cf-7092-4a63-93dd-7013735a83af'
  AND tenant_id = '5443b130-cc28-45af-a420-cd500b288890';

-- 2. Delete the journal entry
DELETE FROM public.journal_entries
WHERE id = '6a7cd1cf-7092-4a63-93dd-7013735a83af'
  AND tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  AND source_reference = 'TEST-IVA-001';

-- 3. Delete the invoice
DELETE FROM public.sales_invoices
WHERE id = '25e298e5-5343-4101-9d96-880dd28f784c'
  AND tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  AND invoice_number = 'TEST-IVA-001';

-- Verify
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.sales_invoices WHERE invoice_number = 'TEST-IVA-001') AND
     NOT EXISTS (SELECT 1 FROM public.journal_entries WHERE source_reference = 'TEST-IVA-001') THEN
    RAISE NOTICE '✅ TEST-IVA-001 and AS-00822 fully removed from production';
  ELSE
    RAISE WARNING '❌ Cleanup incomplete — check manually';
  END IF;
END $$;
