-- =====================================================
-- FIX PURCHASE INVOICE TRIGGERS - SIMPLIFIED IMPLEMENTATION
-- =====================================================
-- This script implements the PURCHASE INVOICE WORKFLOW as documented in:
--   - Purchase_Invoice_status_flow.md (Standard Model)
--   - Purchase_Invoice_Prepayment_Flow.md (Prepayment Model)
--
-- Using EXISTING accounts from sales invoice flow:
--   - 1150: Inventarios de Mercaderías (SHARED - THE ONLY INVENTORY ACCOUNT)
--   - 1140: IVA Crédito Fiscal (Purchase VAT credit)
--   - 2120: Cuentas por Pagar (Accounts Payable)
--   - 1101/1110: Cash/Bank accounts (Payments)
--
-- SIMPLIFIED: NO "Inventario en Tránsito" account!
-- Both Standard and Prepayment models use SAME accounting:
--   - Record inventory + AP when invoice confirmed
--   - Record payment when paid
--   - Verify quantities when received (no accounting entry)
--
-- The only difference between models is WORKFLOW (when payment happens):
--   - Standard: Confirm → Receive → Pay
--   - Prepayment: Confirm → Pay → Receive
-- =====================================================

-- =====================================================
-- ACCOUNTING LOGIC (SAME FOR BOTH MODELS)
-- =====================================================
-- When status → 'confirmed':
--   DR: 1150 Inventarios de Mercaderías = Subtotal
--   DR: 1140 IVA Crédito Fiscal = IVA
--   CR: 2120 Cuentas por Pagar = Total
--   + Inventory INCREASED
--
-- When payment made:
--   DR: 2120 Cuentas por Pagar = Payment
--   CR: 1101 Caja General OR 1110 Bancos = Payment
--
-- When status → 'received':
--   + Verify stock quantities (no accounting entry)
-- =====================================================

-- =====================================================
-- Function 1: Create Purchase Invoice Journal Entry
-- =====================================================
-- Called when status changes to 'confirmed'
-- Creates accounting entry for purchase (inventory + IVA / AP)
-- SAME for both Standard and Prepayment models

CREATE OR REPLACE FUNCTION public.create_purchase_invoice_journal_entry(p_invoice_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice RECORD;
  v_entry_id UUID := gen_random_uuid();
  v_exists BOOLEAN;
  v_inventory_account_code TEXT := '1150';
  v_inventory_account_name TEXT := 'Inventarios de Mercaderías';
  v_inventory_account_id UUID;
  v_iva_account_code TEXT := '1140';
  v_iva_account_name TEXT := 'IVA Crédito Fiscal';
  v_iva_account_id UUID;
  v_ap_account_code TEXT := '2120';
  v_ap_account_name TEXT := 'Cuentas por Pagar';
  v_ap_account_id UUID;
  v_entry_number TEXT;
BEGIN
  -- Get invoice data
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Purchase invoice % not found', p_invoice_id;
  END IF;

  -- Check if journal entry already exists
  SELECT EXISTS (
    SELECT 1
    FROM journal_entries
    WHERE source_module = 'purchase_invoices'
      AND source_reference = p_invoice_id::TEXT
  ) INTO v_exists;

  IF v_exists THEN
    RAISE NOTICE 'Journal entry already exists for purchase invoice %', p_invoice_id;
    RETURN NULL;
  END IF;

  -- Validate amounts
  IF v_invoice.total IS NULL OR v_invoice.total = 0 THEN
    RAISE NOTICE 'Purchase invoice % has zero total, skipping journal entry', p_invoice_id;
    RETURN NULL;
  END IF;

  -- Get account IDs using ensure_account
  v_inventory_account_id := public.ensure_account(
    v_inventory_account_code,
    v_inventory_account_name,
    'asset',
    'currentAsset',
    'Inventario disponible para la venta',
    NULL
  );

  v_iva_account_id := public.ensure_account(
    v_iva_account_code,
    v_iva_account_name,
    'asset',
    'currentAsset',
    'IVA recuperable en compras',
    NULL
  );

  v_ap_account_id := public.ensure_account(
    v_ap_account_code,
    v_ap_account_name,
    'liability',
    'currentLiability',
    'Cuentas por pagar a proveedores',
    NULL
  );

  IF v_inventory_account_id IS NULL OR v_iva_account_id IS NULL OR v_ap_account_id IS NULL THEN
    RAISE EXCEPTION 'Required accounts not found for purchase invoice';
  END IF;

  -- Generate entry number
  v_entry_number := CONCAT('PURCH-', TO_CHAR(NOW(), 'YYYYMMDDHH24MISS'));

  -- ✅ Using NEW column names (entry_date, entry_type, notes)
  INSERT INTO journal_entries (
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
    v_entry_number,
    COALESCE(v_invoice.confirmed_date, v_invoice.date, NOW()),
    format('Compra según factura %s - %s', 
           COALESCE(v_invoice.invoice_number, v_invoice.id::TEXT),
           COALESCE(v_invoice.supplier_name, 'Proveedor')),
    'purchase',
    'purchase_invoices',
    p_invoice_id::TEXT,
    'posted',
    v_invoice.total,
    v_invoice.total,
    NOW(),
    NOW()
  );

  -- ✅ Using NEW column names (journal_entry_id, debit, credit)
  -- Line 1: Debit Inventory (subtotal)
  INSERT INTO journal_lines (
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
    COALESCE(v_invoice.subtotal, 0),
    0,
    format('Inventario - Factura %s', COALESCE(v_invoice.invoice_number, 'S/N')),
    NOW(),
    NOW()
  );

  -- Line 2: Debit IVA Crédito Fiscal (if iva_amount > 0)
  IF COALESCE(v_invoice.iva_amount, 0) > 0 THEN
    INSERT INTO journal_lines (
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
      v_invoice.iva_amount,
      0,
      format('IVA Crédito Fiscal - Factura %s', COALESCE(v_invoice.invoice_number, 'S/N')),
      NOW(),
      NOW()
    );
  END IF;

  -- Line 3: Credit Accounts Payable (total)
  INSERT INTO journal_lines (
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
    v_invoice.total,
    format('Cuentas por Pagar - %s', COALESCE(v_invoice.supplier_name, 'Proveedor')),
    NOW(),
    NOW()
  );

  RAISE NOTICE '✅ Created purchase journal entry % for invoice %', v_entry_number, v_invoice.invoice_number;
  RETURN v_entry_id;
END;
$$;

-- =====================================================
-- Function 2: Delete Purchase Invoice Journal Entry
-- =====================================================

CREATE OR REPLACE FUNCTION public.delete_purchase_invoice_journal_entry(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_invoice_id IS NULL THEN
    RETURN;
  END IF;

  -- Delete journal entry (CASCADE will delete journal_lines)
  DELETE FROM journal_entries
  WHERE source_module = 'purchase_invoices'
    AND source_reference = p_invoice_id::TEXT;

  RAISE NOTICE '✅ Deleted purchase journal entry for invoice %', p_invoice_id;
END;
$$;

-- =====================================================
-- Function 3: Create Purchase Payment Journal Entry
-- =====================================================

CREATE OR REPLACE FUNCTION public.create_purchase_payment_journal_entry(p_payment_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payment RECORD;
  v_invoice RECORD;
  v_entry_id UUID := gen_random_uuid();
  v_exists BOOLEAN;
  v_cash_account_code TEXT;
  v_cash_account_name TEXT;
  v_cash_account_id UUID;
  v_ap_account_id UUID;
  v_ap_account_code TEXT := '2120';
  v_ap_account_name TEXT := 'Cuentas por Pagar';
  v_entry_number TEXT;
BEGIN
  -- Get payment data
  SELECT * INTO v_payment
  FROM purchase_payments
  WHERE id = p_payment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Purchase payment % not found', p_payment_id;
  END IF;

  -- Get invoice data
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = v_payment.purchase_invoice_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Purchase invoice % not found for payment %', v_payment.purchase_invoice_id, p_payment_id;
  END IF;

  -- Check if payment journal entry already exists
  SELECT EXISTS (
    SELECT 1
    FROM journal_entries
    WHERE source_module = 'purchase_payments'
      AND source_reference = p_payment_id::TEXT
  ) INTO v_exists;

  IF v_exists THEN
    RAISE NOTICE 'Payment journal entry already exists for payment %', p_payment_id;
    RETURN NULL;
  END IF;

  -- Determine cash/bank account based on payment method
  CASE COALESCE(v_payment.method, 'other')
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

  -- Get account IDs
  v_cash_account_id := public.ensure_account(
    v_cash_account_code,
    v_cash_account_name,
    'asset',
    'currentAsset',
    v_cash_account_name,
    NULL
  );

  v_ap_account_id := public.ensure_account(
    v_ap_account_code,
    v_ap_account_name,
    'liability',
    'currentLiability',
    'Cuentas por pagar a proveedores',
    NULL
  );

  -- Generate entry number
  v_entry_number := CONCAT('PAY-PURCH-', TO_CHAR(NOW(), 'YYYYMMDDHH24MISS'));

  -- Create payment journal entry
  INSERT INTO journal_entries (
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
    v_entry_number,
    COALESCE(v_payment.date, NOW()),
    format('Pago factura compra %s - %s', 
           COALESCE(v_invoice.invoice_number, v_invoice.id::TEXT),
           COALESCE(v_invoice.supplier_name, 'Proveedor')),
    'payment',
    'purchase_payments',
    p_payment_id::TEXT,
    'posted',
    v_payment.amount,
    v_payment.amount,
    NOW(),
    NOW()
  );

  -- Line 1: Debit Accounts Payable (reduce liability)
  INSERT INTO journal_lines (
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
    v_payment.amount,
    0,
    format('Pago a %s', COALESCE(v_invoice.supplier_name, 'Proveedor')),
    NOW(),
    NOW()
  );

  -- Line 2: Credit Cash/Bank (reduce cash)
  INSERT INTO journal_lines (
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
    v_payment.amount,
    format('Pago factura %s', COALESCE(v_invoice.invoice_number, 'S/N')),
    NOW(),
    NOW()
  );

  RAISE NOTICE '✅ Created payment journal entry % for payment %', v_entry_number, p_payment_id;
  RETURN v_entry_id;
END;
$$;

-- =====================================================
-- Function 4: Delete Purchase Payment Journal Entry
-- =====================================================

CREATE OR REPLACE FUNCTION public.delete_purchase_payment_journal_entry(p_payment_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_payment_id IS NULL THEN
    RETURN;
  END IF;

  -- Delete payment journal entry
  DELETE FROM journal_entries
  WHERE source_module = 'purchase_payments'
    AND source_reference = p_payment_id::TEXT;

  RAISE NOTICE '✅ Deleted payment journal entry for payment %', p_payment_id;
END;
$$;

-- =====================================================
-- TRIGGER FUNCTION: Handle Purchase Invoice Status Changes
-- =====================================================

CREATE OR REPLACE FUNCTION public.handle_purchase_invoice_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- When invoice status changes to 'confirmed', create journal entry
  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    
    -- Confirmed: Create journal entry (DR Inventory, DR IVA / CR AP)
    IF NEW.status = 'confirmed' AND OLD.status != 'confirmed' THEN
      PERFORM create_purchase_invoice_journal_entry(NEW.id);
      RAISE NOTICE '✅ Created journal entry for confirmed invoice %', NEW.id;
    END IF;
    
    -- Revert to draft: Delete journal entry
    IF NEW.status = 'draft' AND OLD.status != 'draft' THEN
      PERFORM delete_purchase_invoice_journal_entry(NEW.id);
      RAISE NOTICE '✅ Deleted journal entry for reverted invoice %', NEW.id;
    END IF;
    
  END IF;
  
  RETURN NEW;
END;
$$;

-- =====================================================
-- TRIGGER FUNCTION: Handle Purchase Payment Insert
-- =====================================================

CREATE OR REPLACE FUNCTION public.handle_purchase_payment_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Create payment journal entry (DR AP / CR Cash or Bank)
  PERFORM create_purchase_payment_journal_entry(NEW.id);
  RAISE NOTICE '✅ Created journal entry for payment %', NEW.id;
  RETURN NEW;
END;
$$;

-- =====================================================
-- TRIGGER FUNCTION: Handle Purchase Payment Delete
-- =====================================================

CREATE OR REPLACE FUNCTION public.handle_purchase_payment_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Delete payment journal entry
  PERFORM delete_purchase_payment_journal_entry(OLD.id);
  RAISE NOTICE '✅ Deleted journal entry for payment %', OLD.id;
  RETURN OLD;
END;
$$;

-- =====================================================
-- DROP EXISTING TRIGGERS (if they exist)
-- =====================================================

DROP TRIGGER IF EXISTS purchase_invoice_change_trigger ON purchase_invoices;
DROP TRIGGER IF EXISTS purchase_payment_insert_trigger ON purchase_payments;
DROP TRIGGER IF EXISTS purchase_payment_delete_trigger ON purchase_payments;

-- =====================================================
-- CREATE TRIGGERS
-- =====================================================

-- Trigger 1: Purchase Invoice Status Changes
CREATE TRIGGER purchase_invoice_change_trigger
  AFTER UPDATE OF status
  ON purchase_invoices
  FOR EACH ROW
  EXECUTE FUNCTION handle_purchase_invoice_change();

-- Trigger 2: Purchase Payment Insert
CREATE TRIGGER purchase_payment_insert_trigger
  AFTER INSERT
  ON purchase_payments
  FOR EACH ROW
  EXECUTE FUNCTION handle_purchase_payment_insert();

-- Trigger 3: Purchase Payment Delete
CREATE TRIGGER purchase_payment_delete_trigger
  BEFORE DELETE
  ON purchase_payments
  FOR EACH ROW
  EXECUTE FUNCTION handle_purchase_payment_delete();

-- =====================================================
-- VERIFICATION
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ ✅ ✅  PURCHASE TRIGGERS CREATED!';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Functions created:';
  RAISE NOTICE '  ✅ create_purchase_invoice_journal_entry()';
  RAISE NOTICE '  ✅ delete_purchase_invoice_journal_entry()';
  RAISE NOTICE '  ✅ create_purchase_payment_journal_entry()';
  RAISE NOTICE '  ✅ delete_purchase_payment_journal_entry()';
  RAISE NOTICE '  ✅ handle_purchase_invoice_change()';
  RAISE NOTICE '  ✅ handle_purchase_payment_insert()';
  RAISE NOTICE '  ✅ handle_purchase_payment_delete()';
  RAISE NOTICE '';
  RAISE NOTICE 'Triggers installed:';
  RAISE NOTICE '  ✅ purchase_invoice_change_trigger (ON UPDATE OF status)';
  RAISE NOTICE '  ✅ purchase_payment_insert_trigger (AFTER INSERT)';
  RAISE NOTICE '  ✅ purchase_payment_delete_trigger (BEFORE DELETE)';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 SIMPLIFIED APPROACH:';
  RAISE NOTICE '   - NO transit account (1155)!';
  RAISE NOTICE '   - Both Standard and Prepayment models use SAME accounting';
  RAISE NOTICE '   - Only workflow timing differs';
  RAISE NOTICE '';
  RAISE NOTICE '📊 Accounts used:';
  RAISE NOTICE '   - 1150: Inventarios de Mercaderías (SHARED with sales)';
  RAISE NOTICE '   - 1140: IVA Crédito Fiscal';
  RAISE NOTICE '   - 2120: Cuentas por Pagar';
  RAISE NOTICE '   - 1101: Caja General (when payment method = cash)';
  RAISE NOTICE '   - 1110: Bancos (when payment method = transfer/card/check)';
  RAISE NOTICE '';
  RAISE NOTICE '⚠️  NEXT STEPS:';
  RAISE NOTICE '   1. Test purchase invoice creation → confirmation';
  RAISE NOTICE '   2. Verify journal entry uses account 1150 (not 1155)';
  RAISE NOTICE '   3. Test payment registration → journal entry';
  RAISE NOTICE '   4. Test "Deshacer pago" → journal entry deletion';
  RAISE NOTICE '';
END;
$$;
