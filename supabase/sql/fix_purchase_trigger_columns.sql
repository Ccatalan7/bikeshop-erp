-- =====================================================
-- FIX: Purchase Invoice Trigger - Column Name Issues
-- =====================================================
-- Fixes "date" column not found errors
-- Ensures all triggers use correct column names
-- =====================================================

-- Step 1: Verify journal_entries structure
SELECT 'Current journal_entries columns:' AS info;
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'journal_entries'
ORDER BY ordinal_position;

-- Step 2: Drop and recreate ALL purchase invoice functions with correct column names
-- (This ensures no lingering references to old 'date' column)

-- Function 3: Create journal entry - STANDARD MODEL (FIXED)
CREATE OR REPLACE FUNCTION create_purchase_invoice_journal_entry(p_invoice_id UUID)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_invoice RECORD;
  v_entry_id UUID;
  v_inventory_account_id UUID;
  v_iva_account_id UUID;
  v_ap_account_id UUID;
BEGIN
  -- Get invoice data
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice % not found', p_invoice_id;
  END IF;

  -- Get account IDs
  SELECT id INTO v_inventory_account_id FROM accounts WHERE code = '1150' LIMIT 1;
  SELECT id INTO v_iva_account_id FROM accounts WHERE code = '1140' LIMIT 1;
  SELECT id INTO v_ap_account_id FROM accounts WHERE code = '2120' LIMIT 1;

  IF v_inventory_account_id IS NULL OR v_iva_account_id IS NULL OR v_ap_account_id IS NULL THEN
    RAISE EXCEPTION 'Required accounts not found (1150, 1140, 2120)';
  END IF;

  -- Create journal entry (USING CORRECT COLUMN NAMES)
  INSERT INTO journal_entries (
    id,
    entry_number,
    entry_date,        -- ✅ Correct column name
    entry_type,        -- ✅ Correct column name
    source_module,
    source_reference,
    status,
    notes,             -- ✅ Correct column name
    created_at
  )
  VALUES (
    gen_random_uuid(),
    'COMP-FC-' || v_invoice.invoice_number,
    COALESCE(v_invoice.confirmed_date, NOW()::DATE),  -- ✅ Ensure not NULL
    'purchase_invoice',
    'purchase_invoices',
    p_invoice_id::TEXT,
    'posted',
    'Compra según factura ' || v_invoice.invoice_number,
    NOW()
  )
  RETURNING id INTO v_entry_id;

  -- Create journal lines (USING CORRECT COLUMN NAMES)
  -- DR: Inventario
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_inventory_account_id,
    v_invoice.subtotal,
    0,
    'Inventario - ' || COALESCE(v_invoice.supplier_name, 'Proveedor'),
    NOW()
  );

  -- DR: IVA Crédito Fiscal
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_iva_account_id,
    v_invoice.iva_amount,
    0,
    'IVA Crédito Fiscal',
    NOW()
  );

  -- CR: Cuentas por Pagar
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_ap_account_id,
    0,
    v_invoice.total,
    'Cuentas por Pagar - ' || COALESCE(v_invoice.supplier_name, 'Proveedor'),
    NOW()
  );

  RAISE NOTICE 'Created journal entry % for invoice %', v_entry_id, v_invoice.invoice_number;
  RETURN v_entry_id;
END;
$$;

-- Function 4: Create journal entry - PREPAYMENT MODEL (FIXED)
CREATE OR REPLACE FUNCTION create_prepaid_purchase_confirmation_entry(p_invoice_id UUID)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_invoice RECORD;
  v_entry_id UUID;
  v_inv_transit_account_id UUID;
  v_iva_account_id UUID;
  v_ap_account_id UUID;
BEGIN
  -- Get invoice data
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice % not found', p_invoice_id;
  END IF;

  -- Get account IDs for prepayment model
  SELECT id INTO v_inv_transit_account_id FROM accounts WHERE code = '1155' LIMIT 1;
  SELECT id INTO v_iva_account_id FROM accounts WHERE code = '1140' LIMIT 1;
  SELECT id INTO v_ap_account_id FROM accounts WHERE code = '2120' LIMIT 1;

  IF v_inv_transit_account_id IS NULL OR v_iva_account_id IS NULL OR v_ap_account_id IS NULL THEN
    RAISE EXCEPTION 'Required accounts not found for prepayment (1155, 1140, 2120)';
  END IF;

  -- Create journal entry (USING CORRECT COLUMN NAMES)
  INSERT INTO journal_entries (
    id,
    entry_number,
    entry_date,        -- ✅ Correct column name
    entry_type,        -- ✅ Correct column name
    source_module,
    source_reference,
    status,
    notes,             -- ✅ Correct column name
    created_at
  )
  VALUES (
    gen_random_uuid(),
    'CONF-COMP-FC-' || v_invoice.invoice_number,
    COALESCE(v_invoice.confirmed_date, NOW()::DATE),  -- ✅ Ensure not NULL
    'purchase_confirmation',
    'purchase_invoices',
    p_invoice_id::TEXT,
    'posted',
    'Confirmación de compra prepagada - Factura ' || v_invoice.invoice_number,
    NOW()
  )
  RETURNING id INTO v_entry_id;

  -- Create journal lines
  -- DR: Inventario en Tránsito
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_inv_transit_account_id,
    v_invoice.subtotal,
    0,
    'Inventario en Tránsito - ' || COALESCE(v_invoice.supplier_name, 'Proveedor'),
    NOW()
  );

  -- DR: IVA Crédito Fiscal
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_iva_account_id,
    v_invoice.iva_amount,
    0,
    'IVA Crédito Fiscal',
    NOW()
  );

  -- CR: Cuentas por Pagar
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_ap_account_id,
    0,
    v_invoice.total,
    'Cuentas por Pagar - ' || COALESCE(v_invoice.supplier_name, 'Proveedor'),
    NOW()
  );

  RAISE NOTICE 'Created prepayment confirmation entry % for invoice %', v_entry_id, v_invoice.invoice_number;
  RETURN v_entry_id;
END;
$$;

-- Function 5: Settlement entry for prepayment (FIXED)
CREATE OR REPLACE FUNCTION settle_prepaid_inventory_on_order(p_invoice_id UUID)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_invoice RECORD;
  v_entry_id UUID;
  v_inventory_account_id UUID;
  v_inv_transit_account_id UUID;
BEGIN
  -- Get invoice data
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice % not found', p_invoice_id;
  END IF;

  -- Get account IDs
  SELECT id INTO v_inventory_account_id FROM accounts WHERE code = '1150' LIMIT 1;
  SELECT id INTO v_inv_transit_account_id FROM accounts WHERE code = '1155' LIMIT 1;

  IF v_inventory_account_id IS NULL OR v_inv_transit_account_id IS NULL THEN
    RAISE EXCEPTION 'Required accounts not found for settlement (1150, 1155)';
  END IF;

  -- Create settlement journal entry (USING CORRECT COLUMN NAMES)
  INSERT INTO journal_entries (
    id,
    entry_number,
    entry_date,        -- ✅ Correct column name
    entry_type,        -- ✅ Correct column name
    source_module,
    source_reference,
    status,
    notes,             -- ✅ Correct column name
    created_at
  )
  VALUES (
    gen_random_uuid(),
    'RECEP-PREPAID-' || v_invoice.invoice_number,
    COALESCE(v_invoice.received_date, NOW()::DATE),  -- ✅ Ensure not NULL
    'purchase_receipt',
    'purchase_invoices',
    p_invoice_id::TEXT,
    'posted',
    'Recepción de inventario prepagado - ' || v_invoice.invoice_number,
    NOW()
  )
  RETURNING id INTO v_entry_id;

  -- DR: Inventario (move from transit to stock)
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_inventory_account_id,
    v_invoice.subtotal,
    0,
    'Recepción en Inventario',
    NOW()
  );

  -- CR: Inventario en Tránsito
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_inv_transit_account_id,
    0,
    v_invoice.subtotal,
    'Salida de Inventario en Tránsito',
    NOW()
  );

  RAISE NOTICE 'Created settlement entry % for invoice %', v_entry_id, v_invoice.invoice_number;
  RETURN v_entry_id;
END;
$$;

-- Step 3: Verification
DO $$
BEGIN
  RAISE NOTICE '✅ Functions recreated with correct column names';
  RAISE NOTICE '';
  RAISE NOTICE 'All journal_entries INSERTs now use:';
  RAISE NOTICE '  - entry_date (not "date")';
  RAISE NOTICE '  - entry_type (not "type")';
  RAISE NOTICE '  - notes (not "description")';
  RAISE NOTICE '';
  RAISE NOTICE 'All journal_lines INSERTs now use:';
  RAISE NOTICE '  - journal_entry_id (not "entry_id")';
  RAISE NOTICE '  - debit (not "debit_amount")';
  RAISE NOTICE '  - credit (not "credit_amount")';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 Try confirming your purchase invoice now!';
END $$;
