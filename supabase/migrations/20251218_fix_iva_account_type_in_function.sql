-- =====================================================
-- HOTFIX: Fix IVA account type in create_purchase_invoice_journal_entry
-- =====================================================
-- Problem: Deployed function was passing type='tax', category='taxReceivable'
-- but the check constraint only allows type IN ('asset','liability','equity','income','expense')
-- Solution: Redeploy the function with correct account types
-- =====================================================

-- STEP 1: Clean up any failed account creation attempts with wrong type
DELETE FROM accounts WHERE code = '2120' AND type = 'tax';

-- STEP 2: Fix ensure_account to handle empty strings as NULL
create or replace function public.ensure_account(
  p_tenant_id uuid,
  p_code text,
  p_name text,
  p_type text,
  p_category text,
  p_description text default null,
  p_parent_code text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_id uuid;
  v_parent_id uuid;
begin
  perform public.migrate_accounts_to_uuid();

  -- Handle empty string or null code
  if p_code is null or p_code = '' then
    return null;
  end if;

  -- Lookup parent account (must be in same tenant)
  if p_parent_code is not null and p_parent_code != '' and p_tenant_id is not null then
    select id
      into v_parent_id
      from public.accounts
     where tenant_id = p_tenant_id
       and code = p_parent_code
     limit 1;
  end if;

  if p_tenant_id is null then
    raise exception 'Cannot create account without tenant_id. Tenant ID is required for multi-tenant system.';
  end if;

  -- Multi-tenant structure: use (tenant_id, code) unique constraint
  insert into public.accounts (tenant_id, code, name, type, category, description, parent_id)
  values (p_tenant_id, p_code, p_name, p_type, p_category, nullif(p_description, ''), v_parent_id)
  on conflict (tenant_id, code) do update
    set name = excluded.name,
        type = excluded.type,
        category = excluded.category,
        description = coalesce(excluded.description, accounts.description),
        parent_id = coalesce(excluded.parent_id, accounts.parent_id),
        is_active = true,
        updated_at = now()
  returning id into v_account_id;

  return v_account_id;
end;
$$;

-- STEP 3: Redeploy the fixed function
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
begin
  raise notice '🔵 START create_purchase_invoice_journal_entry for invoice %', p_invoice.id;
  
  if p_invoice.id is null then
    raise notice '❌ Invoice ID is null, returning';
    return;
  end if;
  
  raise notice '✅ Invoice ID: %, tenant_id: %', p_invoice.id, p_invoice.tenant_id;

  -- Check if journal entry already exists
  select exists (
    select 1
    from public.journal_entries
    where source_module = 'purchase_invoices'
      and source_reference = p_invoice.id::text
  ) into v_exists;

  if v_exists then
    raise notice '⚠️ Entry already exists for invoice %, skipping', p_invoice.id;
    return;
  end if;
  
  raise notice '✅ No existing entry found, proceeding...';

  -- Ensure accounts exist
  raise notice '🔵 Ensuring accounts exist...';
  
  v_inventory_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '1105',
    'Inventarios',
    'asset',
    'currentAsset',
    'Valor del inventario de productos',
    null
  );
  raise notice '✅ Inventory account: %', v_inventory_account_id;

  -- FIX: Use 'asset' type and 'currentAsset' category (NOT 'tax'/'taxReceivable')
  v_iva_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '2120',
    'IVA Crédito Fiscal',
    'asset',           -- FIXED: was 'tax'
    'currentAsset',    -- FIXED: was 'taxReceivable'
    'IVA pagado en compras, recuperable',
    null
  );
  raise notice '✅ IVA account: %', v_iva_account_id;

  v_payable_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '2101',
    'Cuentas por Pagar Proveedores',
    'liability',
    'currentLiability',
    'Obligaciones con proveedores',
    null
  );
  raise notice '✅ Payable account: %', v_payable_account_id;

  v_description := format('Factura compra %s - %s', 
    p_invoice.invoice_number, 
    coalesce(p_invoice.supplier_name, 'Proveedor')
  );
  
  raise notice '🔵 Creating journal entry header...';

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
    id,
    entry_id,
    account_id,
    tenant_id,
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
    p_invoice.tenant_id,
    '1105',
    'Inventarios',
    v_description,
    p_invoice.subtotal,
    0,
    now(),
    now()
  );

  -- DR: IVA Crédito (increase asset, recoverable tax)
  insert into public.journal_lines (
    id,
    entry_id,
    account_id,
    tenant_id,
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
    p_invoice.tenant_id,
    '2120',
    'IVA Crédito Fiscal',
    v_description,
    p_invoice.tax,
    0,
    now(),
    now()
  );

  -- CR: Accounts Payable (increase liability)
  insert into public.journal_lines (
    id,
    entry_id,
    account_id,
    tenant_id,
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
    p_invoice.tenant_id,
    '2101',
    'Cuentas por Pagar Proveedores',
    v_description,
    0,
    p_invoice.total,
    now(),
    now()
  );
  
  raise notice '✅ Journal entry created successfully for invoice %', p_invoice.id;
  raise notice '🎉 DONE - Entry ID: %, Total: %', v_entry_id, p_invoice.total;
end;
$$;

-- Verify fix
DO $$
BEGIN
  RAISE NOTICE '✅ HOTFIX APPLIED: create_purchase_invoice_journal_entry now uses asset/currentAsset for IVA account';
END $$;
