-- =====================================================
-- PURCHASE INVOICE TRIGGERS - MIRROR OF SALES PATTERN
-- =====================================================
-- This script follows the EXACT SAME PATTERN as the sales invoice flow
-- Shares accounts: 1150 (Inventory), 1101 (Cash), 1110 (Bank)
-- Purchase-specific accounts: 1140 (IVA Credit), 2120 (AP)
-- =====================================================

-- =====================================================
-- Function 1: Create Purchase Invoice Journal Entry
-- =====================================================
-- MIRRORS: create_sales_invoice_journal_entry(p_invoice)
-- Receives entire ROW, not just UUID

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
  v_inventory_account_name text := 'Inventarios de Mercaderías';  -- SHARED with sales
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
  -- Validation checks (same pattern as sales)
  IF p_invoice.id IS NULL THEN
    RETURN;
  END IF;

  IF COALESCE(p_invoice.status, 'draft') IN ('draft', 'sent', 'cancelled') THEN
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

  -- Get account IDs using ensure_account (same as sales)
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

  -- Create journal entry (same column names as sales)
  INSERT INTO public.journal_entries (
    id,
    entry_number,
    entry_date,
    notes,
    entry_type,
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
    COALESCE(p_invoice.date, NOW()),  -- Uses 'date' column, not 'invoice_date'
    v_description,
    'purchase',  -- entry_type
    'purchase_invoices',
    p_invoice.id::text,
    'posted',
    v_total,
    v_total,
    NOW(),
    NOW()
  );

  -- Line 1: Debit Inventory (increase asset)
  INSERT INTO public.journal_lines (
    id,
    journal_entry_id,
    account_id,
    debit,
    credit,
    description,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_inventory_account_id,
    v_subtotal,
    0,
    format('Inventario - Factura %s', v_invoice_number),
    NOW(),
    NOW()
  );

  -- Line 2: Debit IVA Crédito Fiscal (if iva > 0)
  IF v_iva <> 0 THEN
    INSERT INTO public.journal_lines (
      id,
      journal_entry_id,
      account_id,
      debit,
      credit,
      description,
      created_at,
      updated_at
    ) VALUES (
      gen_random_uuid(),
      v_entry_id,
      v_iva_account_id,
      v_iva,
      0,
      format('IVA Crédito Fiscal - Factura %s', v_invoice_number),
      NOW(),
      NOW()
    );
  END IF;

  -- Line 3: Credit Accounts Payable (increase liability)
  INSERT INTO public.journal_lines (
    id,
    journal_entry_id,
    account_id,
    debit,
    credit,
    description,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_ap_account_id,
    0,
    v_total,
    format('Cuentas por Pagar - %s', v_supplier_name),
    NOW(),
    NOW()
  );

  RAISE NOTICE 'Created journal entry % for purchase invoice %', v_entry_id, v_invoice_number;
END;
$$;

-- =====================================================
-- Function 2: Handle Purchase Invoice Change
-- =====================================================
-- MIRRORS: handle_sales_invoice_change()
-- Same logic: DELETE journal entries when going backward

CREATE OR REPLACE FUNCTION public.handle_purchase_invoice_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_non_posted CONSTANT TEXT[] := ARRAY[
    'draft', 'borrador',
    'sent', 'enviado', 'enviada',
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
    
    -- Only process if status is "confirmed", "received", or "paid"
    IF NOT (v_new_status = ANY (v_non_posted)) THEN
      PERFORM public.create_purchase_invoice_journal_entry(NEW);
    END IF;
    
    RETURN NEW;
    
  ELSIF TG_OP = 'UPDATE' THEN
    v_old_status := lower(COALESCE(OLD.status, 'draft'));
    v_new_status := lower(COALESCE(NEW.status, 'draft'));
    
    v_old_posted := NOT (v_old_status = ANY (v_non_posted));
    v_new_posted := NOT (v_new_status = ANY (v_non_posted));
    
    -- Handle journal entries: DELETE (not reverse) when going backward
    IF v_old_posted AND NOT v_new_posted THEN
      -- Going from confirmed/received/paid to sent/draft: DELETE journal entry
      DELETE FROM public.journal_entries
      WHERE source_module = 'purchase_invoices'
        AND source_reference = OLD.id::text;
      
      RAISE NOTICE 'Deleted journal entry for purchase invoice % (status: % → %)',
        OLD.invoice_number, v_old_status, v_new_status;
        
    ELSIF NOT v_old_posted AND v_new_posted THEN
      -- Going from sent/draft to confirmed: CREATE journal entry
      PERFORM public.create_purchase_invoice_journal_entry(NEW);
      
    ELSIF v_old_posted AND v_new_posted THEN
      -- Both posted: delete old, create new
      DELETE FROM public.journal_entries
      WHERE source_module = 'purchase_invoices'
        AND source_reference = OLD.id::text;
      
      PERFORM public.create_purchase_invoice_journal_entry(NEW);
    END IF;
    
    RETURN NEW;
    
  ELSIF TG_OP = 'DELETE' THEN
    -- Delete journal entry if invoice is deleted
    DELETE FROM public.journal_entries
    WHERE source_module = 'purchase_invoices'
      AND source_reference = OLD.id::text;
    
    RETURN OLD;
  END IF;
  
  RETURN NEW;
END;
$$;

-- =====================================================
-- Function 3: Create Purchase Payment Journal Entry
-- =====================================================
-- MIRRORS: create_sales_payment_journal_entry(p_payment)

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
  SELECT * INTO v_invoice
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

  -- Determine cash/bank account based on payment method (same as sales)
  CASE COALESCE(p_payment.payment_method, 'transfer')
    WHEN 'cash' THEN
      v_cash_account_code := '1101';
      v_cash_account_name := 'Caja General';
    ELSE
      -- transfer, card, check, other → all go to bank
      v_cash_account_code := '1110';
      v_cash_account_name := 'Bancos - Cuenta Corriente';
  END CASE;

  -- Get account IDs
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

  v_description := format('Pago factura compra %s - %s',
    COALESCE(v_invoice.invoice_number, 'S/N'),
    COALESCE(v_invoice.supplier_name, 'Proveedor'));

  -- Create payment journal entry
  INSERT INTO public.journal_entries (
    id,
    entry_number,
    entry_date,
    notes,
    entry_type,
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
    COALESCE(p_payment.date, NOW()),  -- Uses 'date' column, not 'payment_date'
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
    journal_entry_id,
    account_id,
    debit,
    credit,
    description,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_ap_account_id,
    v_payment_amount,
    0,
    format('Pago a %s', COALESCE(v_invoice.supplier_name, 'Proveedor')),
    NOW(),
    NOW()
  );

  -- Line 2: Credit Cash/Bank (reduce asset)
  INSERT INTO public.journal_lines (
    id,
    journal_entry_id,
    account_id,
    debit,
    credit,
    description,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_cash_account_id,
    0,
    v_payment_amount,
    format('Pago factura %s', COALESCE(v_invoice.invoice_number, 'S/N')),
    NOW(),
    NOW()
  );

  RAISE NOTICE 'Created payment journal entry % for purchase payment %', v_entry_id, p_payment.id;
END;
$$;

-- =====================================================
-- Function 4: Handle Purchase Payment Change
-- =====================================================
-- MIRRORS: sales payment trigger logic

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
-- VERIFICATION
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ ✅ ✅  PURCHASE TRIGGERS INSTALLED!';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Pattern: MIRRORS sales invoice flow exactly';
  RAISE NOTICE '';
  RAISE NOTICE 'Functions created:';
  RAISE NOTICE '  ✅ create_purchase_invoice_journal_entry(p_invoice)';
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
  RAISE NOTICE 'Workflow: draft → sent → confirmed → received/paid';
  RAISE NOTICE 'Journal entries: Created when status = confirmed/received/paid';
  RAISE NOTICE 'Reversals: DELETE entries (not reversal entries)';
  RAISE NOTICE '';
END;
$$;
