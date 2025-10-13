-- =====================================================
-- 🚀 COMPLETE PURCHASE INVOICE TRIGGERS DEPLOYMENT
-- =====================================================
-- This script creates ALL purchase invoice triggers
-- Mirrors the sales invoice flow EXACTLY
-- Run this in Supabase SQL Editor
-- =====================================================

-- =====================================================
-- FUNCTION 1: Create Purchase Invoice Journal Entry
-- =====================================================
-- Mirrors: create_sales_invoice_journal_entry(p_invoice)

CREATE OR REPLACE FUNCTION public.create_purchase_invoice_journal_entry(p_invoice public.purchase_invoices)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists boolean;
  v_entry_id uuid := gen_random_uuid();
  v_inventory_account_code text := '1150';
  v_inventory_account_name text := 'Inventarios de Mercaderías';
  v_inventory_account_id uuid;
  v_iva_account_code text := '1140';
  v_iva_account_name text := 'IVA Crédito Fiscal';
  v_iva_account_id uuid;
  v_ap_account_code text := '2120';
  v_ap_account_name text := 'Cuentas por Pagar';
  v_ap_account_id uuid;
  v_invoice_number text;
  v_supplier_name text;
  v_description text;
  v_subtotal numeric(12,2);
  v_iva numeric(12,2);
  v_total numeric(12,2);
BEGIN
  -- Validation: invoice must exist
  IF p_invoice.id IS NULL THEN
    RETURN;
  END IF;

  -- Don't create entries for draft/cancelled status
  IF COALESCE(p_invoice.status, 'draft') IN ('draft', 'cancelled') THEN
    RETURN;
  END IF;

  -- Check if journal entry already exists
  SELECT EXISTS (
    SELECT 1
    FROM public.journal_entries
    WHERE source_module = 'purchase_invoices'
      AND source_reference = p_invoice.id::text
  ) INTO v_exists;

  IF v_exists THEN
    RETURN;
  END IF;

  -- Get amounts
  v_subtotal := COALESCE(p_invoice.subtotal, 0);
  v_iva := COALESCE(p_invoice.iva_amount, 0);
  v_total := COALESCE(p_invoice.total, v_subtotal + v_iva);

  IF v_total = 0 THEN
    RETURN;
  END IF;

  -- Ensure accounts exist
  v_inventory_account_id := public.ensure_account(
    v_inventory_account_code,
    v_inventory_account_name,
    'asset',
    'currentAsset',
    'Inventario disponible para la venta',
    null
  );

  v_iva_account_id := public.ensure_account(
    v_iva_account_code,
    v_iva_account_name,
    'asset',
    'currentAsset',
    'IVA recuperable en compras',
    null
  );

  v_ap_account_id := public.ensure_account(
    v_ap_account_code,
    v_ap_account_name,
    'liability',
    'currentLiability',
    'Cuentas por pagar a proveedores',
    null
  );

  v_invoice_number := COALESCE(NULLIF(p_invoice.invoice_number, ''), p_invoice.id::text);
  v_supplier_name := COALESCE(NULLIF(p_invoice.supplier_name, ''), 'Proveedor');
  v_description := format('Factura compra %s - %s', v_invoice_number, v_supplier_name);

  -- Create journal entry (matches sales schema exactly)
  INSERT INTO public.journal_entries (
    id,
    entry_number,
    date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) VALUES (
    v_entry_id,
    CONCAT('PURCH-', TO_CHAR(NOW(), 'YYYYMMDDHH24MISS')),
    COALESCE(p_invoice.date, NOW()),
    v_description,
    'purchase',
    'purchase_invoices',
    p_invoice.id::text,
    'posted',
    v_total,
    v_total,
    NOW(),
    NOW()
  );

  -- Line 1: Debit Inventory
  INSERT INTO public.journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_inventory_account_id,
    v_inventory_account_code,
    v_inventory_account_name,
    format('Inventario - Factura %s', v_invoice_number),
    v_subtotal,
    0,
    NOW(),
    NOW()
  );

  -- Line 2: Debit IVA Crédito Fiscal
  IF v_iva <> 0 THEN
    INSERT INTO public.journal_lines (
      id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) VALUES (
      gen_random_uuid(),
      v_entry_id,
      v_iva_account_id,
      v_iva_account_code,
      v_iva_account_name,
      format('IVA Crédito Fiscal - Factura %s', v_invoice_number),
      v_iva,
      0,
      NOW(),
      NOW()
    );
  END IF;

  -- Line 3: Credit Accounts Payable
  INSERT INTO public.journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_ap_account_id,
    v_ap_account_code,
    v_ap_account_name,
    format('Cuentas por Pagar - %s', v_supplier_name),
    0,
    v_total,
    NOW(),
    NOW()
  );

  RAISE NOTICE 'Created journal entry % for purchase invoice %', v_entry_id, v_invoice_number;
END;
$$;

-- =====================================================
-- FUNCTION 2: Delete Purchase Invoice Journal Entry
-- =====================================================
-- Mirrors: delete_sales_invoice_journal_entry(p_invoice_id)

CREATE OR REPLACE FUNCTION public.delete_purchase_invoice_journal_entry(p_invoice_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.journal_entries
  WHERE source_module = 'purchase_invoices'
    AND source_reference = p_invoice_id::text;
  
  RAISE NOTICE 'Deleted journal entry for purchase invoice %', p_invoice_id;
END;
$$;

-- =====================================================
-- FUNCTION 3: Handle Purchase Invoice Change
-- =====================================================
-- Mirrors: handle_sales_invoice_change()

CREATE OR REPLACE FUNCTION public.handle_purchase_invoice_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_non_posted CONSTANT TEXT[] := ARRAY['draft', 'borrador', 'cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada'];
  v_old_status TEXT;
  v_new_status TEXT;
  v_old_posted BOOLEAN;
  v_new_posted BOOLEAN;
BEGIN
  RAISE NOTICE 'handle_purchase_invoice_change: TG_OP=%', TG_OP;

  -- Prevent infinite recursion
  IF pg_trigger_depth() > 1 THEN
    RAISE NOTICE 'handle_purchase_invoice_change: trigger depth > 1, returning';
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    ELSE
      RETURN NEW;
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    v_new_status := lower(COALESCE(NEW.status, 'draft'));
    RAISE NOTICE 'handle_purchase_invoice_change: INSERT invoice %, status %', NEW.id, v_new_status;
    
    -- Create journal entry if not draft/cancelled
    PERFORM public.create_purchase_invoice_journal_entry(NEW);
    
    RETURN NEW;
    
  ELSIF TG_OP = 'UPDATE' THEN
    v_old_status := lower(COALESCE(OLD.status, 'draft'));
    v_new_status := lower(COALESCE(NEW.status, 'draft'));
    
    RAISE NOTICE 'handle_purchase_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    v_old_posted := NOT (v_old_status = ANY (v_non_posted));
    v_new_posted := NOT (v_new_status = ANY (v_non_posted));

    -- Update journal entries (delete old, create new)
    PERFORM public.delete_purchase_invoice_journal_entry(OLD.id);
    PERFORM public.create_purchase_invoice_journal_entry(NEW);
    
    RETURN NEW;
    
  ELSIF TG_OP = 'DELETE' THEN
    v_old_status := lower(COALESCE(OLD.status, 'draft'));
    RAISE NOTICE 'handle_purchase_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;
    
    -- Delete journal entry
    PERFORM public.delete_purchase_invoice_journal_entry(OLD.id);
    
    RETURN OLD;
  END IF;
  
  RETURN NULL;
END;
$$;

-- =====================================================
-- FUNCTION 4: Create Purchase Payment Journal Entry
-- =====================================================
-- Mirrors: create_sales_payment_journal_entry(p_payment)

CREATE OR REPLACE FUNCTION public.create_purchase_payment_journal_entry(p_payment public.purchase_payments)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists boolean;
  v_entry_id uuid := gen_random_uuid();
  v_invoice RECORD;
  v_cash_account_code text;
  v_cash_account_name text;
  v_cash_account_id uuid;
  v_ap_account_code text := '2120';
  v_ap_account_name text := 'Cuentas por Pagar';
  v_ap_account_id uuid;
  v_description text;
  v_payment_amount numeric(12,2);
BEGIN
  IF p_payment.id IS NULL THEN
    RETURN;
  END IF;

  -- Get invoice data
  SELECT 
    id,
    invoice_number,
    supplier_name,
    total
  INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_payment.purchase_invoice_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Check if payment journal entry already exists
  SELECT EXISTS (
    SELECT 1
    FROM public.journal_entries
    WHERE source_module = 'purchase_payments'
      AND source_reference = p_payment.id::text
  ) INTO v_exists;

  IF v_exists THEN
    RETURN;
  END IF;

  v_payment_amount := COALESCE(p_payment.amount, 0);

  IF v_payment_amount = 0 THEN
    RETURN;
  END IF;

  -- Determine cash/bank account (same logic as sales)
  CASE COALESCE(p_payment.payment_method, 'transfer')
    WHEN 'cash' THEN
      v_cash_account_code := '1101';
      v_cash_account_name := 'Caja General';
    WHEN 'card' THEN
      v_cash_account_code := '1110';
      v_cash_account_name := 'Bancos - Cuenta Corriente';
    WHEN 'transfer' THEN
      v_cash_account_code := '1110';
      v_cash_account_name := 'Bancos - Cuenta Corriente';
    WHEN 'check' THEN
      v_cash_account_code := '1110';
      v_cash_account_name := 'Bancos - Cuenta Corriente';
    ELSE
      v_cash_account_code := '1190';
      v_cash_account_name := 'Otros Activos Corrientes';
  END CASE;

  -- Ensure accounts exist
  v_cash_account_id := public.ensure_account(
    v_cash_account_code,
    v_cash_account_name,
    'asset',
    'currentAsset',
    v_cash_account_name,
    null
  );

  v_ap_account_id := public.ensure_account(
    v_ap_account_code,
    v_ap_account_name,
    'liability',
    'currentLiability',
    'Cuentas por pagar a proveedores',
    null
  );

  v_description := format('Pago factura compra %s',
    COALESCE(v_invoice.invoice_number, v_invoice.id::text));

  -- Create payment journal entry (matches sales schema)
  INSERT INTO public.journal_entries (
    id,
    entry_number,
    date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) VALUES (
    v_entry_id,
    CONCAT('PAY-PURCH-', TO_CHAR(NOW(), 'YYYYMMDDHH24MISS')),
    COALESCE(p_payment.payment_date, NOW()),
    v_description,
    'payment',
    'purchase_payments',
    p_payment.id::text,
    'posted',
    v_payment_amount,
    v_payment_amount,
    NOW(),
    NOW()
  );

  -- Line 1: Debit Accounts Payable (reduce liability)
  INSERT INTO public.journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_ap_account_id,
    v_ap_account_code,
    v_ap_account_name,
    format('Pago proveedor'),
    v_payment_amount,
    0,
    NOW(),
    NOW()
  );

  -- Line 2: Credit Cash/Bank (reduce asset)
  INSERT INTO public.journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_cash_account_id,
    v_cash_account_code,
    v_cash_account_name,
    format('Pago factura %s', COALESCE(v_invoice.invoice_number, 'S/N')),
    0,
    v_payment_amount,
    NOW(),
    NOW()
  );

  RAISE NOTICE 'Created payment journal entry % for purchase payment %', v_entry_id, p_payment.id;
END;
$$;

-- =====================================================
-- FUNCTION 5: Handle Purchase Payment Change
-- =====================================================
-- Mirrors: sales payment trigger logic

CREATE OR REPLACE FUNCTION public.handle_purchase_payment_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.create_purchase_payment_journal_entry(NEW);
    RETURN NEW;
    
  ELSIF TG_OP = 'DELETE' THEN
    -- Delete payment journal entry
    DELETE FROM public.journal_entries
    WHERE source_module = 'purchase_payments'
      AND source_reference = OLD.id::text;
    
    RAISE NOTICE 'Deleted payment journal entry for payment %', OLD.id;
    RETURN OLD;
  END IF;
  
  RETURN NEW;
END;
$$;

-- =====================================================
-- DROP EXISTING TRIGGERS
-- =====================================================

DROP TRIGGER IF EXISTS purchase_invoice_change_trigger ON purchase_invoices;
DROP TRIGGER IF EXISTS trg_purchase_invoices_change ON purchase_invoices;
DROP TRIGGER IF EXISTS purchase_payment_insert_trigger ON purchase_payments;
DROP TRIGGER IF EXISTS purchase_payment_delete_trigger ON purchase_payments;
DROP TRIGGER IF EXISTS purchase_payment_change_trigger ON purchase_payments;
DROP TRIGGER IF EXISTS trg_purchase_payments_change ON purchase_payments;

-- =====================================================
-- CREATE TRIGGERS (same pattern as sales)
-- =====================================================

CREATE TRIGGER trg_purchase_invoices_change
  AFTER INSERT OR UPDATE OR DELETE ON public.purchase_invoices
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_purchase_invoice_change();

CREATE TRIGGER trg_purchase_payments_change
  AFTER INSERT OR DELETE ON public.purchase_payments
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_purchase_payment_change();

-- =====================================================
-- VERIFICATION & SUCCESS MESSAGE
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ ✅ ✅  PURCHASE TRIGGERS DEPLOYED!';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Pattern: MIRRORS sales invoice flow exactly';
  RAISE NOTICE '';
  RAISE NOTICE 'Functions created:';
  RAISE NOTICE '  ✅ create_purchase_invoice_journal_entry(p_invoice)';
  RAISE NOTICE '  ✅ delete_purchase_invoice_journal_entry(p_invoice_id)';
  RAISE NOTICE '  ✅ handle_purchase_invoice_change()';
  RAISE NOTICE '  ✅ create_purchase_payment_journal_entry(p_payment)';
  RAISE NOTICE '  ✅ handle_purchase_payment_change()';
  RAISE NOTICE '';
  RAISE NOTICE 'Triggers installed:';
  RAISE NOTICE '  ✅ trg_purchase_invoices_change (INSERT/UPDATE/DELETE)';
  RAISE NOTICE '  ✅ trg_purchase_payments_change (INSERT/DELETE)';
  RAISE NOTICE '';
  RAISE NOTICE '📊 Shared accounts with sales:';
  RAISE NOTICE '   - 1150: Inventarios de Mercaderías';
  RAISE NOTICE '   - 1101: Caja General';
  RAISE NOTICE '   - 1110: Bancos - Cuenta Corriente';
  RAISE NOTICE '';
  RAISE NOTICE '📊 Purchase-specific accounts:';
  RAISE NOTICE '   - 1140: IVA Crédito Fiscal';
  RAISE NOTICE '   - 2120: Cuentas por Pagar';
  RAISE NOTICE '';
  RAISE NOTICE 'Now test:';
  RAISE NOTICE '  1. Create purchase invoice (draft)';
  RAISE NOTICE '  2. Change to "sent" → No journal entry';
  RAISE NOTICE '  3. Change to "confirmed" → Journal entry created!';
  RAISE NOTICE '  4. Register payment → Payment entry created!';
  RAISE NOTICE '  5. Check journal_entries table';
  RAISE NOTICE '';
END;
$$;
