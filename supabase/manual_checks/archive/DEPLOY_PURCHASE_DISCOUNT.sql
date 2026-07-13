-- ============================================================
-- Purchase Invoice Discount Columns
-- Adds global invoice-level discount support
-- ============================================================

DO $$
BEGIN
    -- Add discount_type if not exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='purchase_invoices' AND column_name='discount_type') THEN
        ALTER TABLE purchase_invoices ADD COLUMN discount_type text DEFAULT 'percentage';
        COMMENT ON COLUMN purchase_invoices.discount_type IS 'percentage or amount';
    END IF;

    -- Add discount_value if not exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='purchase_invoices' AND column_name='discount_value') THEN
        ALTER TABLE purchase_invoices ADD COLUMN discount_value numeric DEFAULT 0;
        COMMENT ON COLUMN purchase_invoices.discount_value IS 'Raw input: e.g. 10 for 10%, or 5000 for $5000';
    END IF;

    -- Add discount_amount if not exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='purchase_invoices' AND column_name='discount_amount') THEN
        ALTER TABLE purchase_invoices ADD COLUMN discount_amount numeric DEFAULT 0;
        COMMENT ON COLUMN purchase_invoices.discount_amount IS 'Computed discount in CLP';
    END IF;

    -- Add is_discount_before_tax if not exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='purchase_invoices' AND column_name='is_discount_before_tax') THEN
        ALTER TABLE purchase_invoices ADD COLUMN is_discount_before_tax boolean DEFAULT true;
        COMMENT ON COLUMN purchase_invoices.is_discount_before_tax IS 'true = applied to Net (reduces tax base), false = applied to Total (no tax reduction)';
    END IF;
END $$;

-- ============================================================
-- Accounting Trigger Update
-- Corrects inventory debit calculation to handle discounts
-- Inventory Cost = Total Amount - Recoverable Tax
-- This ensures Dr Inventory + Dr IVA = Cr Payable is balanced
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_purchase_invoice_journal_entry(p_invoice public.purchase_invoices)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists boolean;
  v_entry_id uuid := gen_random_uuid();
  v_inventory_account_id uuid;
  v_iva_account_id uuid;
  v_payable_account_id uuid;
  v_description text;
  v_inventory_amount numeric;
BEGIN
  -- Basic Validation
  if p_invoice.id is null then
    return;
  end if;

  -- Check if journal entry already exists
  select exists (
    select 1
    from public.journal_entries
    where source_module = 'purchase_invoices'
      and source_reference = p_invoice.id::text
  ) into v_exists;

  if v_exists then
    return;
  end if;

  -- Ensure accounts exist (using helper function)
  v_inventory_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '1105',
    'Inventarios',
    'asset',
    'currentAsset',
    'Valor del inventario de productos',
    null
  );

  v_iva_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '2120',
    'IVA Crédito Fiscal',
    'asset',
    'currentAsset',
    'IVA pagado en compras, recuperable',
    null
  );

  v_payable_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '2101',
    'Cuentas por Pagar Proveedores',
    'liability',
    'currentLiability',
    'Obligaciones con proveedores',
    null
  );

  v_description := format('Factura compra %s - %s', 
    p_invoice.invoice_number, 
    coalesce(p_invoice.supplier_name, 'Proveedor')
  );

  -- Calculate Inventory Amount (Net Cost) = Total - Tax
  -- This balances the entry: Inventory + IVA = Payable
  v_inventory_amount := coalesce(p_invoice.total, 0) - coalesce(p_invoice.tax, 0);
  
  -- Create journal entry header
  insert into public.journal_entries (
    id,
    tenant_id,
    entry_number,
    entry_date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    p_invoice.tenant_id,
    public.get_next_document_number(p_invoice.tenant_id, 'journal_entry'),
    coalesce(p_invoice.date, now()),
    v_description,
    'purchase',
    'purchase_invoices',
    p_invoice.invoice_number,
    'posted',
    p_invoice.total,
    p_invoice.total,
    now(),
    now()
  );

  -- DR: Inventory (increase asset)
  insert into public.journal_lines (
    id, entry_id, account_id, tenant_id, account_code, account_name, description, debit_amount, credit_amount
  ) values (
    gen_random_uuid(), v_entry_id, v_inventory_account_id, p_invoice.tenant_id, '1105', 'Inventarios', v_description,
    v_inventory_amount, 0
  );

  -- DR: IVA Crédito (increase asset)
  insert into public.journal_lines (
    id, entry_id, account_id, tenant_id, account_code, account_name, description, debit_amount, credit_amount
  ) values (
    gen_random_uuid(), v_entry_id, v_iva_account_id, p_invoice.tenant_id, '2120', 'IVA Crédito Fiscal', v_description,
    coalesce(p_invoice.tax, 0), 0
  );

  -- CR: Accounts Payable (increase liability)
  insert into public.journal_lines (
    id, entry_id, account_id, tenant_id, account_code, account_name, description, debit_amount, credit_amount
  ) values (
    gen_random_uuid(), v_entry_id, v_payable_account_id, p_invoice.tenant_id, '2101', 'Cuentas por Pagar Proveedores', v_description,
    0, p_invoice.total
  );

END;
$$;
