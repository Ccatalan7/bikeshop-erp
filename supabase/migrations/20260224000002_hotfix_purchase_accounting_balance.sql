-- =====================================================
-- Hotfix: Purchase Invoice Accounting Balance
-- =====================================================
-- Problem: `create_purchase_invoice_journal_entry` used `p_invoice.subtotal` for the Inventory debit.
-- If `taxTreatment` is `taxIncluded`, `subtotal` represents the GROSS amount, and `tax` represents the IVA.
-- This caused the accounting entry to be unbalanced because Total Debits (Gross Subtotal + IVA) > Total Credits (Gross Total).
-- Solution: Align with the sales module by using `coalesce(p_invoice.net_amount, p_invoice.subtotal, 0)` for the Inventory/Expense line, ensuring only the true net value is debited.
-- =====================================================

create or replace function public.create_purchase_invoice_journal_entry(p_invoice public.purchase_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
  v_entry_id uuid := gen_random_uuid();
  v_inventory_account_id uuid;
  v_iva_account_id uuid;
  v_payable_account_id uuid;
  v_description text;
  v_real_net_amount numeric(12,2);
begin
  if p_invoice.id is null then
    raise notice 'create_purchase_invoice_journal_entry: invoice ID is null, returning';
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
    raise notice 'create_purchase_invoice_journal_entry: entry already exists for invoice %', p_invoice.id;
    return;
  end if;

  -- Ensure accounts exist
  v_inventory_account_id := public.ensure_account(
    '1105',
    'Inventarios',
    'asset',
    'currentAsset',
    'Valor del inventario de productos',
    null
  );

  v_iva_account_id := public.ensure_account(
    '1107',
    'IVA Crédito Fiscal',
    'asset',
    'currentAsset',
    'IVA pagado en compras, recuperable',
    null
  );

  v_payable_account_id := public.ensure_account(
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

  -- ✅ CRITICAL FIX: Use net_amount if available, fallback to subtotal
  -- For taxIncluded, net_amount cleanly separates out the IVA.
  v_real_net_amount := coalesce(p_invoice.net_amount, p_invoice.subtotal, 0);

  -- Create journal entry header
  insert into public.journal_entries (
    id,
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
    concat('PINV-', to_char(now(), 'YYYYMMDDHH24MISS')),
    coalesce(p_invoice.date, now()),
    v_description,
    'purchase',
    'purchase_invoices',
    p_invoice.id::text,
    'posted',
    p_invoice.total,
    p_invoice.total,
    now(),
    now()
  );

  -- DR: Inventory (increase asset)
  -- Uses the true net amount (excluding tax)
  insert into public.journal_lines (
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
  ) values (
    gen_random_uuid(),
    v_entry_id,
    v_inventory_account_id,
    '1105',
    'Inventarios',
    v_description,
    v_real_net_amount,
    0,
    now(),
    now()
  );

  -- DR: IVA Crédito (increase asset, recoverable tax)
  insert into public.journal_lines (
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
  ) values (
    gen_random_uuid(),
    v_entry_id,
    v_iva_account_id,
    '1107',
    'IVA Crédito Fiscal',
    v_description,
    coalesce(p_invoice.tax, 0),
    0,
    now(),
    now()
  );

  -- CR: Accounts Payable (increase liability)
  insert into public.journal_lines (
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
  ) values (
    gen_random_uuid(),
    v_entry_id,
    v_payable_account_id,
    '2101',
    'Cuentas por Pagar Proveedores',
    v_description,
    0,
    p_invoice.total,
    now(),
    now()
  );

  raise notice 'create_purchase_invoice_journal_entry: created entry for invoice %', p_invoice.id;
end;
$$;
