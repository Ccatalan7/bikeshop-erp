-- =====================================================
-- COMPREHENSIVE FIX: SALES + PURCHASE ACCOUNTING
-- =====================================================
-- This script:
-- 1. Restores proper account names that sales expects
-- 2. Updates sales invoice functions to use new column names
-- 3. Aligns purchase invoice accounts with sales structure
-- =====================================================

-- =====================================================
-- PART 1: RESTORE CORRECT ACCOUNT NAMES
-- =====================================================
-- Account 1150 was renamed from "Inventarios de Mercaderías" to "Inventario"
-- This broke the sales flow. We restore the original name.

UPDATE accounts 
SET 
  name = 'Inventarios de Mercaderías',
  category = 'currentAsset',
  description = 'Inventario disponible para la venta',
  updated_at = NOW()
WHERE code = '1150';

-- Ensure account 1140 (IVA Credit) exists for purchases
INSERT INTO accounts (id, code, name, type, category, description, is_active, created_at, updated_at)
VALUES (gen_random_uuid(), '1140', 'IVA Crédito Fiscal', 'asset', 'currentAsset', 'IVA recuperable en compras', true, NOW(), NOW())
ON CONFLICT (code) DO UPDATE SET
  is_active = true,
  updated_at = NOW();

-- Ensure account 1155 (Inventory in Transit) exists for prepaid purchases
INSERT INTO accounts (id, code, name, type, category, description, is_active, created_at, updated_at)
VALUES (gen_random_uuid(), '1155', 'Inventario en Tránsito', 'asset', 'currentAsset', 'Inventario prepagado pendiente de recepción', true, NOW(), NOW())
ON CONFLICT (code) DO UPDATE SET
  is_active = true,
  updated_at = NOW();

-- Ensure account 2120 (Accounts Payable) exists
INSERT INTO accounts (id, code, name, type, category, description, is_active, created_at, updated_at)
VALUES (gen_random_uuid(), '2120', 'Cuentas por Pagar', 'liability', 'currentLiability', 'Cuentas por pagar a proveedores', true, NOW(), NOW())
ON CONFLICT (code) DO UPDATE SET
  is_active = true,
  updated_at = NOW();

-- =====================================================
-- PART 2: FIX SALES INVOICE JOURNAL ENTRY FUNCTION
-- =====================================================
-- The current function in core_schema.sql uses OLD column names
-- (date, entry_id, account_code, debit_amount, credit_amount)
-- which were DROPPED by MASTER_ACCOUNTING_FIX.sql
-- We update it to use NEW column names
-- (entry_date, journal_entry_id, account_id, debit, credit)

CREATE OR REPLACE FUNCTION public.create_sales_invoice_journal_entry(p_invoice public.sales_invoices)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists boolean;
  v_entry_id uuid := gen_random_uuid();
  v_receivable_account_code text := '1130';
  v_receivable_account_name text := 'Cuentas por Cobrar Comerciales';
  v_receivable_account_id uuid;
  v_revenue_account_code text := '4100';
  v_revenue_account_name text := 'Ingresos por Ventas';
  v_revenue_account_id uuid;
  v_iva_account_code text := '2150';
  v_iva_account_name text := 'IVA Débito Fiscal';
  v_iva_account_id uuid;
  v_inventory_account_code text := '1150';
  v_inventory_account_name text := 'Inventarios de Mercaderías';  -- RESTORED correct name
  v_inventory_account_id uuid;
  v_cogs_account_code text := '5100';
  v_cogs_account_name text := 'Costo de Ventas';
  v_cogs_account_id uuid;
  v_invoice_number text;
  v_customer_name text;
  v_description text;
  v_subtotal numeric(12,2);
  v_iva numeric(12,2);
  v_total numeric(12,2);
  v_total_cost numeric(12,2);
BEGIN
  IF p_invoice.id IS NULL THEN
    RETURN;
  END IF;

  IF COALESCE(p_invoice.status, 'draft') IN ('draft', 'cancelled') THEN
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.journal_entries
    WHERE source_module = 'sales_invoices'
      AND source_reference = p_invoice.id::text
  ) INTO v_exists;

  IF v_exists THEN
    RETURN;
  END IF;

  v_subtotal := COALESCE(p_invoice.subtotal, 0);
  v_iva := COALESCE(p_invoice.iva_amount, 0);
  v_total := COALESCE(p_invoice.total, v_subtotal + v_iva);

  IF v_total = 0 THEN
    RETURN;
  END IF;

  -- Get account IDs using ensure_account
  v_receivable_account_id := public.ensure_account(
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    null
  );

  v_revenue_account_id := public.ensure_account(
    v_revenue_account_code,
    v_revenue_account_name,
    'income',
    'operatingIncome',
    'Ingresos operacionales por ventas',
    null
  );

  v_iva_account_id := public.ensure_account(
    v_iva_account_code,
    v_iva_account_name,
    'tax',
    'taxPayable',
    'IVA generado en ventas',
    null
  );

  -- Calculate total cost for COGS entry
  SELECT COALESCE(SUM((item->>'cost')::numeric), 0)
  INTO v_total_cost
  FROM jsonb_array_elements(COALESCE(p_invoice.items, '[]'::jsonb)) item
  WHERE (item->>'cost') IS NOT NULL
    AND (item->>'cost') <> '';

  IF v_total_cost > 0 THEN
    v_inventory_account_id := public.ensure_account(
      v_inventory_account_code,
      v_inventory_account_name,
      'asset',
      'currentAsset',
      'Inventario disponible para la venta',
      null
    );

    v_cogs_account_id := public.ensure_account(
      v_cogs_account_code,
      v_cogs_account_name,
      'expense',
      'costOfGoodsSold',
      'Costo de ventas',
      null
    );
  END IF;

  v_invoice_number := COALESCE(NULLIF(p_invoice.invoice_number, ''), p_invoice.id::text);
  v_customer_name := COALESCE(NULLIF(p_invoice.customer_name, ''), 'Cliente');
  v_description := format('Factura %s - %s', v_invoice_number, v_customer_name);

  -- ✅ FIXED: Using NEW column names (entry_date, entry_type, notes)
  INSERT INTO public.journal_entries (
    id,
    entry_number,
    entry_date,     -- ✅ Changed from 'date'
    notes,          -- ✅ Changed from 'description'
    entry_type,     -- ✅ Changed from 'type'
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) VALUES (
    v_entry_id,
    CONCAT('INV-', TO_CHAR(NOW(), 'YYYYMMDDHH24MISS')),
    COALESCE(p_invoice.date, NOW()),
    v_description,
    'sale',        -- ✅ FIXED: Changed from 'sales' to 'sale' to match CHECK constraint
    'sales_invoices',
    p_invoice.id::text,
    'posted',
    v_total,
    v_total,
    NOW(),
    NOW()
  );

  -- ✅ FIXED: Using NEW column names (journal_entry_id, debit, credit)
  -- Line 1: Debit Accounts Receivable
  INSERT INTO public.journal_lines (
    id,
    journal_entry_id,  -- ✅ Changed from 'entry_id'
    account_id,
    debit,             -- ✅ Changed from 'debit_amount'
    credit,            -- ✅ Changed from 'credit_amount'
    description,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_receivable_account_id,
    v_total,
    0,
    v_description,
    NOW(),
    NOW()
  );

  -- Line 2: Credit Revenue (if subtotal > 0)
  IF v_subtotal <> 0 THEN
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
      v_revenue_account_id,
      0,
      v_subtotal,
      format('Ingreso por venta %s', v_invoice_number),
      NOW(),
      NOW()
    );
  END IF;

  -- Line 3: Credit IVA Payable (if iva > 0)
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
      0,
      v_iva,
      format('IVA débito factura %s', v_invoice_number),
      NOW(),
      NOW()
    );
  END IF;

  -- Lines 4-5: COGS and Inventory reduction (if cost > 0)
  IF v_total_cost > 0 THEN
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
      v_cogs_account_id,
      v_total_cost,
      0,
      format('Costo de ventas %s', v_invoice_number),
      NOW(),
      NOW()
    ), (
      gen_random_uuid(),
      v_entry_id,
      v_inventory_account_id,
      0,
      v_total_cost,
      format('Salida inventario factura %s', v_invoice_number),
      NOW(),
      NOW()
    );
  END IF;
END;
$$;

-- =====================================================
-- PART 3: FIX SALES PAYMENT JOURNAL ENTRY FUNCTION
-- =====================================================

CREATE OR REPLACE FUNCTION public.create_sales_payment_journal_entry(p_payment public.sales_payments)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_cash_account_code text;
  v_cash_account_name text;
  v_cash_account_id uuid;
  v_receivable_account_id uuid;
  v_receivable_account_code text := '1130';
  v_receivable_account_name text := 'Cuentas por Cobrar Comerciales';
  v_description text;
BEGIN
  IF p_payment.invoice_id IS NULL THEN
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.journal_entries
    WHERE source_module = 'sales_payments'
      AND source_reference = p_payment.id::text
  ) INTO v_exists;

  IF v_exists THEN
    RETURN;
  END IF;

  SELECT id, invoice_number, customer_name, total
  INTO v_invoice
  FROM public.sales_invoices
  WHERE id = p_payment.invoice_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Determine cash account based on payment method
  CASE COALESCE(p_payment.method, 'other')
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

  v_cash_account_id := public.ensure_account(
    v_cash_account_code,
    v_cash_account_name,
    'asset',
    'currentAsset',
    v_cash_account_name,
    null
  );

  v_receivable_account_id := public.ensure_account(
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    null
  );

  v_description := format('Pago factura %s', COALESCE(v_invoice.invoice_number, v_invoice.id::text));

  -- ✅ FIXED: Using NEW column names
  INSERT INTO public.journal_entries (
    id,
    entry_number,
    entry_date,     -- ✅ Changed from 'date'
    notes,          -- ✅ Changed from 'description'
    entry_type,     -- ✅ Changed from 'type'
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) VALUES (
    v_entry_id,
    CONCAT('PAY-', TO_CHAR(NOW(), 'YYYYMMDDHH24MISS')),
    COALESCE(p_payment.date, NOW()),
    v_description,
    'payment',
    'sales_payments',
    p_payment.id::text,
    'posted',
    p_payment.amount,
    p_payment.amount,
    NOW(),
    NOW()
  );

  -- ✅ FIXED: Using NEW column names
  INSERT INTO public.journal_lines (
    id,
    journal_entry_id,  -- ✅ Changed from 'entry_id'
    account_id,
    debit,             -- ✅ Changed from 'debit_amount'
    credit,            -- ✅ Changed from 'credit_amount'
    description,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_cash_account_id,
    p_payment.amount,
    0,
    format('Cobro a %s', COALESCE(v_invoice.customer_name, 'Cliente')),
    NOW(),
    NOW()
  ), (
    gen_random_uuid(),
    v_entry_id,
    v_receivable_account_id,
    0,
    p_payment.amount,
    format('Pago factura %s', COALESCE(v_invoice.invoice_number, v_invoice.id::text)),
    NOW(),
    NOW()
  );
END;
$$;

-- =====================================================
-- PART 4: FIX DELETE SALES PAYMENT JOURNAL ENTRY
-- =====================================================

CREATE OR REPLACE FUNCTION public.delete_sales_payment_journal_entry(p_payment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_payment_id IS NULL THEN
    RETURN;
  END IF;

  -- Delete journal entry using new structure
  DELETE FROM public.journal_entries
  WHERE source_module = 'sales_payments'
    AND source_reference = p_payment_id::text;
END;
$$;

-- =====================================================
-- PART 5: FIX DELETE SALES INVOICE JOURNAL ENTRY
-- =====================================================

CREATE OR REPLACE FUNCTION public.delete_sales_invoice_journal_entry(p_invoice_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_invoice_id IS NULL THEN
    RETURN;
  END IF;

  -- Delete journal entry using new structure
  DELETE FROM public.journal_entries
  WHERE source_module = 'sales_invoices'
    AND source_reference = p_invoice_id::text;
END;
$$;

-- =====================================================
-- PART 6: VERIFICATION
-- =====================================================

-- Check accounts
SELECT 
  code,
  name,
  type,
  category,
  is_active
FROM accounts
WHERE code IN ('1130', '1140', '1150', '1155', '2120', '2150', '4100', '5100')
ORDER BY code;

-- Confirmation message
DO $$
DECLARE
  v_1150_name text;
BEGIN
  SELECT name INTO v_1150_name FROM accounts WHERE code = '1150';
  
  IF v_1150_name = 'Inventarios de Mercaderías' THEN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ✅ ✅  FIX SUCCESSFUL!';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Account 1150 restored to: %', v_1150_name;
    RAISE NOTICE 'Sales invoice functions updated to use new column names';
    RAISE NOTICE 'Sales payment functions updated to use new column names';
    RAISE NOTICE 'Delete functions updated for sales invoices and payments';
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Sales invoices should now work correctly!';
    RAISE NOTICE '';
  ELSE
    RAISE WARNING '⚠️  Account 1150 name is: %', v_1150_name;
    RAISE WARNING 'Expected: Inventarios de Mercaderías';
  END IF;
END;
$$;
