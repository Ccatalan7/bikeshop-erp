-- =====================================================
-- Sales Invoice Workflow Redesign
-- =====================================================
-- Changes the sales invoice flow to: Draft → Sent → Confirmed → Paid
-- Key changes:
-- 1. Add "confirmed" status
-- 2. Journal entries created only when "confirmed" (not "sent")
-- 3. DELETE journal entries when going backward (not reverse)
-- 4. Inventory consumed only when "confirmed"
-- =====================================================

-- =====================================================
-- Step 1: Update sales_invoices status constraint
-- =====================================================
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
        'confirmed', 'confirmado', 'confirmada',
        'paid', 'pagado', 'pagada',
        'overdue', 'vencido', 'vencida',
        'cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada'
      ]));
  
  RAISE NOTICE '✅ Updated sales_invoices status constraint to include "confirmed"';
END $$;

-- =====================================================
-- Step 2: Update existing "sent" invoices to "confirmed"
-- =====================================================
-- This ensures existing invoices that were "sent" (and already have
-- journal entries) are migrated to "confirmed" status
DO $$
DECLARE
  v_updated INTEGER;
BEGIN
  UPDATE public.sales_invoices
  SET status = 'confirmed',
      updated_at = NOW()
  WHERE lower(status) IN ('sent', 'enviado', 'enviada', 'issued', 'emitido', 'emitida')
    AND EXISTS (
      SELECT 1 FROM public.journal_entries
      WHERE source_module = 'sales_invoices'
        AND source_reference = sales_invoices.id::text
    );
  
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  
  IF v_updated > 0 THEN
    RAISE NOTICE '✅ Migrated % existing "sent" invoices to "confirmed"', v_updated;
  ELSE
    RAISE NOTICE 'ℹ️  No existing "sent" invoices needed migration';
  END IF;
END $$;

-- =====================================================
-- Step 3: Replace the sales invoice trigger function
-- =====================================================
CREATE OR REPLACE FUNCTION public.handle_sales_invoice_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_non_posted CONSTANT TEXT[] := ARRAY[
    'draft', 'borrador',
    'sent', 'enviado', 'enviada', 'issued', 'emitido', 'emitida',
    'cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada'
  ];
  v_old_status TEXT;
  v_new_status TEXT;
  v_old_posted BOOLEAN;
  v_new_posted BOOLEAN;
BEGIN
  -- Prevent infinite recursion
  IF pg_trigger_depth() > 1 THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    ELSE
      RETURN NEW;
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_new_status := lower(COALESCE(NEW.status, 'draft'));
    
    -- Only process if status is "confirmed" or "paid" (not "sent")
    IF NOT (v_new_status = ANY (v_non_posted)) THEN
      PERFORM public.consume_sales_invoice_inventory(NEW);
      PERFORM public.create_sales_invoice_journal_entry(NEW);
    END IF;
    
    PERFORM public.recalculate_sales_invoice_payments(NEW.id);
    RETURN NEW;
    
  ELSIF TG_OP = 'UPDATE' THEN
    v_old_status := lower(COALESCE(OLD.status, 'draft'));
    v_new_status := lower(COALESCE(NEW.status, 'draft'));
    
    v_old_posted := NOT (v_old_status = ANY (v_non_posted));
    v_new_posted := NOT (v_new_status = ANY (v_non_posted));
    
    -- Handle inventory changes
    IF v_old_posted THEN
      IF v_new_posted THEN
        -- Both posted: restore old, consume new
        PERFORM public.restore_sales_invoice_inventory(OLD);
        PERFORM public.consume_sales_invoice_inventory(NEW);
      ELSE
        -- Going backward: restore inventory
        PERFORM public.restore_sales_invoice_inventory(OLD);
      END IF;
    ELSIF v_new_posted THEN
      -- Going forward: consume inventory
      PERFORM public.consume_sales_invoice_inventory(NEW);
    END IF;
    
    -- Handle journal entries: DELETE (not reverse) when going backward
    IF v_old_posted AND NOT v_new_posted THEN
      -- Going from confirmed/paid to sent/draft: DELETE journal entry
      DELETE FROM public.journal_entries
      WHERE source_module = 'sales_invoices'
        AND source_reference = OLD.id::text;
      
      RAISE NOTICE 'Deleted journal entry for invoice % (status: % → %)',
        OLD.invoice_number, v_old_status, v_new_status;
    ELSIF NOT v_old_posted AND v_new_posted THEN
      -- Going from sent/draft to confirmed: CREATE journal entry
      PERFORM public.create_sales_invoice_journal_entry(NEW);
    ELSIF v_old_posted AND v_new_posted THEN
      -- Both posted: delete old, create new
      DELETE FROM public.journal_entries
      WHERE source_module = 'sales_invoices'
        AND source_reference = OLD.id::text;
      
      PERFORM public.create_sales_invoice_journal_entry(NEW);
    END IF;
    
    PERFORM public.recalculate_sales_invoice_payments(NEW.id);
    RETURN NEW;
    
  ELSIF TG_OP = 'DELETE' THEN
    v_old_status := lower(COALESCE(OLD.status, 'draft'));
    
    -- Restore inventory if it was posted
    IF NOT (v_old_status = ANY (v_non_posted)) THEN
      PERFORM public.restore_sales_invoice_inventory(OLD);
    END IF;
    
    -- DELETE journal entry (don't reverse)
    DELETE FROM public.journal_entries
    WHERE source_module = 'sales_invoices'
      AND source_reference = OLD.id::text;
    
    RAISE NOTICE 'Deleted journal entry for deleted invoice %', OLD.invoice_number;
    
    RETURN OLD;
  END IF;
  
  RETURN NULL;
END;
$$;

-- =====================================================
-- Step 4: Update journal entry creation to be idempotent
-- =====================================================
CREATE OR REPLACE FUNCTION public.create_sales_invoice_journal_entry(p_invoice public.sales_invoices)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists BOOLEAN;
  v_entry_id UUID;
  v_receivable_account_id UUID;
  v_receivable_account_code TEXT;
  v_receivable_account_name TEXT;
  v_revenue_account_id UUID;
  v_revenue_account_code TEXT := '4100';
  v_revenue_account_name TEXT := 'Ingresos por Ventas';
  v_iva_account_id UUID;
  v_iva_account_code TEXT := '2150';
  v_iva_account_name TEXT := 'IVA Débito Fiscal';
  v_inventory_account_id UUID;
  v_inventory_account_code TEXT := '1150';
  v_inventory_account_name TEXT := 'Inventarios de Mercaderías';
  v_cogs_account_id UUID;
  v_cogs_account_code TEXT := '5101';
  v_cogs_account_name TEXT := 'Costo de Ventas';
  v_invoice_number TEXT;
  v_customer_name TEXT;
  v_description TEXT;
  v_subtotal NUMERIC(12,2);
  v_iva NUMERIC(12,2);
  v_total NUMERIC(12,2);
  v_total_cost NUMERIC(12,2);
BEGIN
  IF p_invoice.id IS NULL THEN
    RETURN;
  END IF;

  -- Only create for "confirmed" or "paid" status (not "sent")
  IF COALESCE(p_invoice.status, 'draft') IN ('draft', 'sent', 'cancelled') THEN
    RETURN;
  END IF;

  -- Check if entry already exists (should not, but be safe)
  SELECT EXISTS (
    SELECT 1 FROM public.journal_entries
    WHERE source_module = 'sales_invoices'
      AND source_reference = p_invoice.id::text
  ) INTO v_exists;

  IF v_exists THEN
    RAISE NOTICE 'Journal entry already exists for invoice %, skipping', p_invoice.invoice_number;
    RETURN;
  END IF;

  v_subtotal := COALESCE(p_invoice.subtotal, 0);
  v_iva := COALESCE(p_invoice.iva_amount, 0);
  v_total := COALESCE(p_invoice.total, v_subtotal + v_iva);

  -- Calculate total cost from items
  SELECT COALESCE(SUM(
    (item->>'quantity')::NUMERIC * 
    COALESCE((item->>'cost')::NUMERIC, 0)
  ), 0)
  INTO v_total_cost
  FROM jsonb_array_elements(COALESCE(p_invoice.items, '[]'::jsonb)) AS item;

  -- Get account IDs
  v_receivable_account_id := public.ensure_account(
    '1120', 'Cuentas por Cobrar', 'asset', 'currentAsset',
    'Montos a cobrar de clientes', NULL
  );

  SELECT code, name INTO v_receivable_account_code, v_receivable_account_name
  FROM public.accounts WHERE id = v_receivable_account_id;

  v_revenue_account_id := public.ensure_account(
    v_revenue_account_code, v_revenue_account_name, 'income', 'operatingIncome',
    'Ingresos por ventas de productos/servicios', NULL
  );

  v_iva_account_id := public.ensure_account(
    v_iva_account_code, v_iva_account_name, 'liability', 'currentLiability',
    'IVA débito fiscal por ventas', NULL
  );

  IF v_total_cost > 0 THEN
    v_inventory_account_id := public.ensure_account(
      v_inventory_account_code, v_inventory_account_name, 'asset', 'currentAsset',
      'Inventario disponible para la venta', NULL
    );

    v_cogs_account_id := public.ensure_account(
      v_cogs_account_code, v_cogs_account_name, 'expense', 'costOfGoodsSold',
      'Costo de ventas', NULL
    );
  END IF;

  v_invoice_number := COALESCE(NULLIF(p_invoice.invoice_number, ''), p_invoice.id::TEXT);
  v_customer_name := COALESCE(NULLIF(p_invoice.customer_name, ''), 'Cliente');
  v_description := format('Factura %s - %s', v_invoice_number, v_customer_name);

  v_entry_id := gen_random_uuid();

  -- Create journal entry
  INSERT INTO public.journal_entries (
    id, entry_number, date, description, type,
    source_module, source_reference, status,
    total_debit, total_credit, created_at, updated_at
  ) VALUES (
    v_entry_id,
    concat('INV-', to_char(NOW(), 'YYYYMMDDHH24MISS')),
    COALESCE(p_invoice.date, NOW()),
    v_description,
    'sales',
    'sales_invoices',
    p_invoice.id::TEXT,
    'posted',
    v_total,
    v_total,
    NOW(),
    NOW()
  );

  -- Debit: Accounts Receivable
  INSERT INTO public.journal_lines (
    id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_entry_id, v_receivable_account_id,
    v_receivable_account_code, v_receivable_account_name,
    v_description, v_total, 0, NOW(), NOW()
  );

  -- Credit: Revenue
  IF v_subtotal <> 0 THEN
    INSERT INTO public.journal_lines (
      id, entry_id, account_id, account_code, account_name,
      description, debit_amount, credit_amount, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), v_entry_id, v_revenue_account_id,
      v_revenue_account_code, v_revenue_account_name,
      format('Ingreso por venta %s', v_invoice_number),
      0, v_subtotal, NOW(), NOW()
    );
  END IF;

  -- Credit: IVA
  IF v_iva <> 0 THEN
    INSERT INTO public.journal_lines (
      id, entry_id, account_id, account_code, account_name,
      description, debit_amount, credit_amount, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), v_entry_id, v_iva_account_id,
      v_iva_account_code, v_iva_account_name,
      format('IVA débito factura %s', v_invoice_number),
      0, v_iva, NOW(), NOW()
    );
  END IF;

  -- COGS entry if applicable
  IF v_total_cost > 0 THEN
    INSERT INTO public.journal_lines (
      id, entry_id, account_id, account_code, account_name,
      description, debit_amount, credit_amount, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), v_entry_id, v_cogs_account_id,
      v_cogs_account_code, v_cogs_account_name,
      format('Costo de venta %s', v_invoice_number),
      v_total_cost, 0, NOW(), NOW()
    );

    INSERT INTO public.journal_lines (
      id, entry_id, account_id, account_code, account_name,
      description, debit_amount, credit_amount, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), v_entry_id, v_inventory_account_id,
      v_inventory_account_code, v_inventory_account_name,
      format('Salida inventario venta %s', v_invoice_number),
      0, v_total_cost, NOW(), NOW()
    );
  END IF;

  RAISE NOTICE 'Created journal entry % for invoice %', v_entry_id, v_invoice_number;
END;
$$;

-- =====================================================
-- Step 5: Remove the old delete function (no longer needed)
-- =====================================================
DROP FUNCTION IF EXISTS public.delete_sales_invoice_journal_entry(UUID);

-- =====================================================
-- Step 6: Recreate the trigger
-- =====================================================
DROP TRIGGER IF EXISTS trg_sales_invoices_change ON public.sales_invoices;

CREATE TRIGGER trg_sales_invoices_change
  AFTER INSERT OR UPDATE OR DELETE ON public.sales_invoices
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_sales_invoice_change();

-- =====================================================
-- Success Message
-- =====================================================
DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ Sales Invoice Workflow Updated!';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'New workflow: Draft → Sent → Confirmed → Paid';
  RAISE NOTICE '';
  RAISE NOTICE 'Changes applied:';
  RAISE NOTICE '  ✓ Added "confirmed" status';
  RAISE NOTICE '  ✓ Journal entries created only when "confirmed"';
  RAISE NOTICE '  ✓ Journal entries DELETED (not reversed) when going backward';
  RAISE NOTICE '  ✓ Inventory consumed only when "confirmed"';
  RAISE NOTICE '  ✓ Existing "sent" invoices migrated to "confirmed"';
  RAISE NOTICE '========================================';
END $$;
