-- =====================================================
-- FIX SALES INVOICE TRIGGERS - CORRECT WORKFLOW
-- =====================================================
-- This fixes the sales invoice flow to match Invoice_status_flow.md:
-- • Draft → Sent: NO accounting, NO inventory change
-- • Sent → Confirmed: CREATE journal entry + DEDUCT inventory
-- • Confirmed → Paid: CREATE payment journal entry
-- • Backward transitions: DELETE journal entries (Zoho Books style)
-- =====================================================

-- Step 1: Update sales_invoices status constraint to include "confirmed"
DO $$
BEGIN
  -- Drop existing constraint
  ALTER TABLE public.sales_invoices
    DROP CONSTRAINT IF EXISTS sales_invoices_status_check;
  
  -- Add new constraint with "confirmed" status
  ALTER TABLE public.sales_invoices
    ADD CONSTRAINT sales_invoices_status_check
      CHECK (lower(status) = ANY (ARRAY[
        'draft', 'borrador',
        'sent', 'enviado', 'enviada', 'emitido', 'emitida', 'issued',
        'confirmed', 'confirmado', 'confirmada',  -- ⭐ ADDED CONFIRMED STATUS!
        'paid', 'pagado', 'pagada',
        'overdue', 'vencido', 'vencida',
        'cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada'
      ]));
  
  RAISE NOTICE '✅ Updated sales_invoices status constraint to include confirmed status';
END $$;

-- Step 2: Fix the handle_sales_invoice_change trigger
CREATE OR REPLACE FUNCTION public.handle_sales_invoice_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_non_posted CONSTANT TEXT[] := ARRAY[
    'draft', 'borrador',
    'sent', 'enviado', 'enviada', 'issued', 'emitido', 'emitida',  -- ⭐ INCLUDES SENT!
    'cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada'
  ];
  v_old_status TEXT;
  v_new_status TEXT;
  v_old_posted BOOLEAN;
  v_new_posted BOOLEAN;
BEGIN
  RAISE NOTICE 'handle_sales_invoice_change: TG_OP=%, invoice=%', TG_OP, 
    CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_number ELSE NEW.invoice_number END;

  -- Prevent infinite recursion
  IF pg_trigger_depth() > 1 THEN
    RAISE NOTICE 'handle_sales_invoice_change: trigger depth > 1, skipping';
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    ELSE
      RETURN NEW;
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_new_status := lower(COALESCE(NEW.status, 'draft'));
    RAISE NOTICE 'handle_sales_invoice_change: INSERT invoice %, status %', NEW.invoice_number, v_new_status;
    
    -- Only process if status is "confirmed" or "paid" (NOT "draft" or "sent")
    IF NOT (v_new_status = ANY (v_non_posted)) THEN
      RAISE NOTICE 'handle_sales_invoice_change: INSERT with posted status, consuming inventory';
      PERFORM public.consume_sales_invoice_inventory(NEW);
      PERFORM public.create_sales_invoice_journal_entry(NEW);
    ELSE
      RAISE NOTICE 'handle_sales_invoice_change: INSERT with non-posted status (%), skipping', v_new_status;
    END IF;
    
    PERFORM public.recalculate_sales_invoice_payments(NEW.id);
    RETURN NEW;
    
  ELSIF TG_OP = 'UPDATE' THEN
    v_old_status := lower(COALESCE(OLD.status, 'draft'));
    v_new_status := lower(COALESCE(NEW.status, 'draft'));
    
    RAISE NOTICE 'handle_sales_invoice_change: UPDATE invoice % from % to %', 
      NEW.invoice_number, v_old_status, v_new_status;
    
    v_old_posted := NOT (v_old_status = ANY (v_non_posted));
    v_new_posted := NOT (v_new_status = ANY (v_non_posted));
    
    -- INVENTORY HANDLING
    IF v_old_posted THEN
      IF v_new_posted THEN
        -- Both posted: restore old, consume new (items might have changed)
        RAISE NOTICE 'handle_sales_invoice_change: both posted, restore and consume';
        PERFORM public.restore_sales_invoice_inventory(OLD);
        PERFORM public.consume_sales_invoice_inventory(NEW);
      ELSE
        -- Confirmed/Paid → Draft/Sent: RESTORE inventory
        RAISE NOTICE 'handle_sales_invoice_change: reverting to non-posted, restore inventory';
        PERFORM public.restore_sales_invoice_inventory(OLD);
      END IF;
    ELSIF v_new_posted THEN
      -- Draft/Sent → Confirmed: CONSUME inventory
      RAISE NOTICE 'handle_sales_invoice_change: changing to posted, consume inventory';
      PERFORM public.consume_sales_invoice_inventory(NEW);
    ELSE
      -- Both non-posted (draft → sent or sent → draft): no inventory change
      RAISE NOTICE 'handle_sales_invoice_change: both non-posted, no inventory change';
    END IF;
    
    -- JOURNAL ENTRY HANDLING (DELETE-based reversals, Zoho Books style)
    IF v_old_posted AND NOT v_new_posted THEN
      -- Confirmed/Paid → Draft/Sent: DELETE journal entry
      RAISE NOTICE 'handle_sales_invoice_change: reverting to non-posted, deleting journal entry';
      DELETE FROM public.journal_entries
      WHERE source_module = 'sales_invoices'
        AND source_reference = OLD.id::text;
        
    ELSIF NOT v_old_posted AND v_new_posted THEN
      -- Draft/Sent → Confirmed: CREATE journal entry
      RAISE NOTICE 'handle_sales_invoice_change: changing to posted, creating journal entry';
      PERFORM public.create_sales_invoice_journal_entry(NEW);
      
    ELSIF v_old_posted AND v_new_posted THEN
      -- Both posted: delete old, create new (amounts might have changed)
      RAISE NOTICE 'handle_sales_invoice_change: both posted, recreating journal entry';
      DELETE FROM public.journal_entries
      WHERE source_module = 'sales_invoices'
        AND source_reference = OLD.id::text;
      PERFORM public.create_sales_invoice_journal_entry(NEW);
    ELSE
      -- Both non-posted: no journal entry action
      RAISE NOTICE 'handle_sales_invoice_change: both non-posted, no journal entry action';
    END IF;
    
    PERFORM public.recalculate_sales_invoice_payments(NEW.id);
    RETURN NEW;
    
  ELSIF TG_OP = 'DELETE' THEN
    v_old_status := lower(COALESCE(OLD.status, 'draft'));
    RAISE NOTICE 'handle_sales_invoice_change: DELETE invoice %, status %', OLD.invoice_number, v_old_status;
    
    -- Restore inventory if it was posted
    IF NOT (v_old_status = ANY (v_non_posted)) THEN
      RAISE NOTICE 'handle_sales_invoice_change: deleting posted invoice, restoring inventory';
      PERFORM public.restore_sales_invoice_inventory(OLD);
    END IF;
    
    -- DELETE journal entry
    DELETE FROM public.journal_entries
    WHERE source_module = 'sales_invoices'
      AND source_reference = OLD.id::text;
    
    RAISE NOTICE 'handle_sales_invoice_change: deleted journal entry for invoice %', OLD.invoice_number;
    
    RETURN OLD;
  END IF;
  
  RETURN NULL;
END;
$$;

-- Step 3: Recreate the trigger (drop and recreate to ensure it's active)
DROP TRIGGER IF EXISTS trg_sales_invoices_change ON public.sales_invoices;

CREATE TRIGGER trg_sales_invoices_change
  AFTER INSERT OR UPDATE OR DELETE ON public.sales_invoices
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_sales_invoice_change();

-- Step 4: Verify trigger is installed
DO $$
DECLARE
  v_trigger_exists BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_sales_invoices_change'
      AND tgrelid = 'public.sales_invoices'::regclass
  ) INTO v_trigger_exists;
  
  IF v_trigger_exists THEN
    RAISE NOTICE '✅ Trigger trg_sales_invoices_change is installed correctly';
  ELSE
    RAISE WARNING '❌ Trigger trg_sales_invoices_change NOT found!';
  END IF;
END $$;

-- Step 5: Show current trigger configuration
SELECT 
  t.tgname AS trigger_name,
  c.relname AS table_name,
  p.proname AS function_name,
  CASE 
    WHEN t.tgtype & 2 = 2 THEN 'BEFORE'
    WHEN t.tgtype & 64 = 64 THEN 'INSTEAD OF'
    ELSE 'AFTER'
  END AS timing,
  array_to_string(
    ARRAY[
      CASE WHEN t.tgtype & 4 = 4 THEN 'INSERT' END,
      CASE WHEN t.tgtype & 8 = 8 THEN 'DELETE' END,
      CASE WHEN t.tgtype & 16 = 16 THEN 'UPDATE' END
    ]::TEXT[], 
    ', '
  ) AS events
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE c.relname = 'sales_invoices'
  AND t.tgname = 'trg_sales_invoices_change';

-- =====================================================
-- DEPLOYMENT INSTRUCTIONS
-- =====================================================
-- 1. Open Supabase Dashboard → SQL Editor
-- 2. Copy and paste this entire file
-- 3. Click "Run"
-- 4. Verify you see "✅ Trigger trg_sales_invoices_change is installed correctly"
-- 5. Test the flow:
--    a) Create draft invoice → No journal entry
--    b) Mark as sent → No journal entry, no inventory change
--    c) Confirm → Journal entry created, inventory deducted
--    d) Revert to sent → Journal entry deleted, inventory restored
-- =====================================================
