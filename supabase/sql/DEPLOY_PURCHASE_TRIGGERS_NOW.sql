-- =====================================================
-- 🚀 DEPLOY PURCHASE TRIGGERS - QUICK FIX
-- =====================================================
-- Run this in Supabase SQL Editor to fix the "method" error
-- This replaces the old trigger that uses p_payment.method
-- with the correct one that uses p_payment.payment_method
-- =====================================================

-- =====================================================
-- Function: Create Purchase Payment Journal Entry
-- =====================================================
-- FIXED: Uses p_payment.payment_method (not p_payment.method)

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

  -- ✅ FIXED: Uses payment_method (matches database column)
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
  -- ✅ FIXED: Uses payment_date and matches actual journal_entries schema
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
    COALESCE(p_payment.payment_date, NOW()),  -- ✅ FIXED: payment_date
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
    format('Pago a %s', COALESCE(v_invoice.supplier_name, 'Proveedor')),
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
-- SUCCESS MESSAGE
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ PURCHASE PAYMENT TRIGGER FIXED!';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE 'Fixed: p_payment.method → p_payment.payment_method';
  RAISE NOTICE 'Fixed: p_payment.date → p_payment.payment_date';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 Now try registering a payment again!';
END;
$$;
