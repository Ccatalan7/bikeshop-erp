-- =====================================================
-- Add Purchase Invoice Workflow Tracking Columns
-- =====================================================
-- Purpose: Add missing columns for tracking purchase invoice workflow states
-- Missing columns: sent_date, confirmed_date, received_date, paid_date,
--                  supplier_invoice_number, supplier_invoice_date
-- Root cause: Database schema was missing these columns that exist in Flutter model
-- =====================================================

-- Add workflow tracking columns
alter table public.purchase_invoices
  add column if not exists sent_date timestamp with time zone,
  add column if not exists confirmed_date timestamp with time zone,
  add column if not exists received_date timestamp with time zone,
  add column if not exists paid_date timestamp with time zone,
  add column if not exists supplier_invoice_number text,
  add column if not exists supplier_invoice_date timestamp with time zone;

-- Create indexes for common queries
create index if not exists idx_purchase_invoices_sent_date 
  on public.purchase_invoices(tenant_id, sent_date) 
  where sent_date is not null;

create index if not exists idx_purchase_invoices_confirmed_date 
  on public.purchase_invoices(tenant_id, confirmed_date) 
  where confirmed_date is not null;

create index if not exists idx_purchase_invoices_received_date 
  on public.purchase_invoices(tenant_id, received_date) 
  where received_date is not null;

create index if not exists idx_purchase_invoices_paid_date 
  on public.purchase_invoices(tenant_id, paid_date) 
  where paid_date is not null;

-- Add comment documenting the workflow
comment on column public.purchase_invoices.sent_date is 'Timestamp when invoice was sent to supplier (Draft → Sent)';
comment on column public.purchase_invoices.confirmed_date is 'Timestamp when supplier confirmed invoice (Sent → Confirmed)';
comment on column public.purchase_invoices.received_date is 'Timestamp when goods were received (Confirmed → Received)';
comment on column public.purchase_invoices.paid_date is 'Timestamp when invoice was paid (Received → Paid or Confirmed → Paid for prepayment model)';
comment on column public.purchase_invoices.supplier_invoice_number is 'Invoice number from supplier (provided at confirmation)';
comment on column public.purchase_invoices.supplier_invoice_date is 'Invoice date from supplier (provided at confirmation)';

-- =====================================================
-- Fix: Ensure accounts table has proper unique constraints
-- =====================================================
-- Problem: ensure_account() function uses ON CONFLICT with constraints that might not exist
-- Solution: Migrate accounts to multi-tenant and ensure proper constraints
-- =====================================================

-- STEP 1: Migrate existing accounts with null tenant_id to current user's tenant
do $$
declare
  v_user_tenant_id uuid;
  v_null_accounts_count integer;
begin
  -- Get current user's tenant_id
  v_user_tenant_id := public.user_tenant_id();
  
  if v_user_tenant_id is not null then
    -- Count accounts with null tenant_id
    select count(*) into v_null_accounts_count from public.accounts where tenant_id is null;
    
    if v_null_accounts_count > 0 then
      raise notice 'Found % accounts with null tenant_id, migrating to tenant %', v_null_accounts_count, v_user_tenant_id;
      
      -- Update all null tenant_id accounts to belong to current user's tenant
      update public.accounts 
      set tenant_id = v_user_tenant_id 
      where tenant_id is null;
      
      raise notice '✅ Migrated % accounts to tenant %', v_null_accounts_count, v_user_tenant_id;
    else
      raise notice 'ℹ️ No accounts with null tenant_id found';
    end if;
  else
    raise notice 'ℹ️ No authenticated user tenant_id - skipping account migration';
  end if;
end $$;

-- STEP 2: Drop single-tenant constraint if it exists (we're in multi-tenant mode now)
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conrelid = 'public.accounts'::regclass
    and contype = 'u'
    and conname = 'accounts_code_key'
  ) then
    -- Drop the single-tenant constraint as we're now multi-tenant
    alter table public.accounts drop constraint accounts_code_key;
    raise notice '✅ Dropped single-tenant unique constraint accounts_code_key (multi-tenant mode)';
  else
    raise notice 'ℹ️ Single-tenant constraint accounts_code_key does not exist';
  end if;
exception
  when others then
    raise notice '⚠️  Could not drop single-tenant constraint: %', sqlerrm;
end $$;

-- STEP 3: Ensure multi-tenant unique constraint exists
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.accounts'::regclass
    and contype = 'u'
    and conname = 'accounts_tenant_id_code_key'
  ) then
    alter table public.accounts add constraint accounts_tenant_id_code_key unique (tenant_id, code);
    raise notice '✅ Added multi-tenant unique constraint accounts_tenant_id_code_key';
  else
    raise notice '✅ Multi-tenant unique constraint accounts_tenant_id_code_key already exists';
  end if;
end $$;

-- Verify columns were added
do $$
begin
  if not exists (
    select 1 from information_schema.columns 
    where table_schema = 'public' 
    and table_name = 'purchase_invoices' 
    and column_name = 'sent_date'
  ) then
    raise exception 'Column sent_date was not added to purchase_invoices table';
  end if;
  
  raise notice '✅ All workflow tracking columns added successfully to purchase_invoices table';
end $$;

-- =====================================================
-- Fix: Update create_purchase_invoice_journal_entry function
-- =====================================================
-- Problem: Function was referencing p_invoice.iva_amount which doesn't exist
-- Solution: Change to p_invoice.tax (the correct column name)
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
    p_invoice.subtotal,
    0,
    now(),
    now()
  );

  -- DR: IVA Crédito (increase asset, recoverable tax)
  -- ✅ FIXED: Changed from p_invoice.iva_amount to p_invoice.tax
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
