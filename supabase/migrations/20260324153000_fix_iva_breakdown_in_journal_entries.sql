-- Migration: Fix IVA breakdown in journal entries
-- Created: 2026-03-24
-- This migration updates both sales invoice and sales payment JE creation functions 
-- to ensure taxes are correctly broken down and calculated if missing.

-- 1. Update create_sales_invoice_journal_entry
create or replace function public.create_sales_invoice_journal_entry(p_invoice public.sales_invoices)
returns void 
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
  v_entry_id uuid := gen_random_uuid();
  v_receivable_account_code text := '1130';
  v_receivable_account_name text := 'Cuentas por Cobrar Comerciales';
  v_receivable_account_id uuid;
  v_revenue_account_code text := '4100';
  v_revenue_account_name text := 'Ingresos Operacionales';
  v_revenue_account_id uuid;
  v_iva_account_code text := '2150';
  v_iva_account_name text := 'IVA Débito Fiscal';
  v_iva_account_id uuid;
  v_inventory_account_code text := '1105';
  v_inventory_account_name text := 'Inventarios';
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
  v_tenant_id uuid;
begin
  if p_invoice.id is null then
    return;
  end if;

  if coalesce(p_invoice.status, 'draft') in ('draft', 'cancelled') then
    return;
  end if;

  v_tenant_id := p_invoice.tenant_id;

  -- CRITICAL: Validate tenant_id for service role context (webhooks)
  if v_tenant_id is null then
    raise warning 'create_sales_invoice_journal_entry: No tenant_id on invoice %, skipping', p_invoice.id;
    return;
  end if;

  -- Check for existing journal entry using invoice_number (consistent with INSERT)
  select exists (
           select 1
             from public.journal_entries
            where source_module = 'sales_invoices'
              and source_reference = p_invoice.invoice_number
              and tenant_id = v_tenant_id
       )
    into v_exists;

  if v_exists then
    raise notice 'create_sales_invoice_journal_entry: Entry already exists for invoice %, skipping', p_invoice.invoice_number;
    return;
  end if;
  
  raise notice 'create_sales_invoice_journal_entry: Creating entry for invoice % (status: %)', p_invoice.invoice_number, p_invoice.status;

  -- ✅ CRITICAL: Use net_amount (tax-adjusted) if available, fallback to subtotal
  -- [FIX: IVA BREAKDOWN] Ensure net_amount and iva_amount are correctly handled
  -- If tax_included, we MUST have a breakdown. Fallback to calculation if fields are 0.
  v_subtotal := coalesce(nullif(p_invoice.net_amount, 0), p_invoice.subtotal, 0);
  v_iva := coalesce(nullif(p_invoice.iva_amount, 0), 0);

  if p_invoice.tax_treatment = 'tax_included' and (v_iva = 0 or v_subtotal = p_invoice.total) then
    v_subtotal := round(p_invoice.total / 1.19, 2);
    v_iva := p_invoice.total - v_subtotal;
  end if;

  v_total := coalesce(p_invoice.total, v_subtotal + v_iva);

  if v_total = 0 then
    return;
  end if;

  v_receivable_account_id := public.ensure_account(
    v_tenant_id,
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    null
  );

  v_revenue_account_id := public.ensure_account(
    v_tenant_id,
    v_revenue_account_code,
    v_revenue_account_name,
    'income',
    'operatingIncome',
    'Ingresos operacionales por ventas',
    null
  );

  v_iva_account_id := public.ensure_account(
    v_tenant_id,
    v_iva_account_code,
    v_iva_account_name,
    'liability',
    'currentLiability',
    'IVA generado en ventas',
    null
  );

  select coalesce(sum((item->>'cost')::numeric), 0)
    into v_total_cost
    from jsonb_array_elements(coalesce(p_invoice.items, '[]'::jsonb)) item
   where (item->>'cost') is not null
     and (item->>'cost') <> '';

  if v_total_cost > 0 then
    v_inventory_account_id := public.ensure_account(
      v_tenant_id,
      v_inventory_account_code,
      v_inventory_account_name,
      'asset',
      'currentAsset',
      'Inventario disponible para la venta',
      null
    );

    v_cogs_account_id := public.ensure_account(
      v_tenant_id,
      v_cogs_account_code,
      v_cogs_account_name,
      'expense',
      'costOfGoodsSold',
      'Costo de ventas',
      null
    );
  end if;

  v_invoice_number := coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text);
  v_customer_name := coalesce(nullif(p_invoice.customer_name, ''), 'Cliente');
  v_description := format('Factura %s - %s', v_invoice_number, v_customer_name);

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
    v_tenant_id,
    public.get_next_document_number(v_tenant_id, 'journal_entry'),
    coalesce(p_invoice.date, now()),
    v_description,
    'sales',
    'sales_invoices',
    p_invoice.invoice_number,
    'posted',
    v_total,
    v_total,
    now(),
    now()
  );

  insert into public.journal_lines (
    id,
    tenant_id,
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
    v_tenant_id,
    v_entry_id,
    v_receivable_account_id,
    v_receivable_account_code,
    v_receivable_account_name,
    v_description,
    v_total,
    0,
    now(),
    now()
  );

  if v_subtotal <> 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
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
      v_tenant_id,
      v_entry_id,
      v_revenue_account_id,
      v_revenue_account_code,
      v_revenue_account_name,
      format('Ingreso por venta %s', v_invoice_number),
      0,
      v_subtotal,
      now(),
      now()
    );
  end if;

  if v_iva <> 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
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
      v_tenant_id,
      v_entry_id,
      v_iva_account_id,
      v_iva_account_code,
      v_iva_account_name,
      format('IVA débito factura %s', v_invoice_number),
      0,
      v_iva,
      now(),
      now()
    );
  end if;

  if v_total_cost > 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
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
      v_tenant_id,
      v_entry_id,
      v_cogs_account_id,
      v_cogs_account_code,
      v_cogs_account_name,
      format('Costo de ventas factura %s', v_invoice_number),
      v_total_cost,
      0,
      now(),
      now()
    ), (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_inventory_account_id,
      v_inventory_account_code,
      v_inventory_account_name,
      format('Salida inventario factura %s', v_invoice_number),
      0,
      v_total_cost,
      now(),
      now()
    );
  end if;
end;
$$;

-- 2. Update create_sales_payment_journal_entry
create or replace function public.create_sales_payment_journal_entry(p_payment public.sales_payments)
returns void 
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_payment_method record;
  v_cash_account_id uuid;
  v_cash_account_code text;
  v_cash_account_name text;
  v_receivable_account_id uuid;
  v_receivable_account_code text := '1130';
  v_receivable_account_name text := 'Cuentas por Cobrar Comerciales';
  v_description text;
  v_tenant_id uuid;
  v_subtotal numeric(12,2);
  v_iva numeric(12,2);
begin
  if p_payment.invoice_id is null then
    return;
  end if;

  -- Skip if payment is soft deleted
  if p_payment.deleted_at is not null then
    raise notice 'create_sales_payment_journal_entry: Payment % is deleted, skipping', p_payment.id;
    return;
  end if;

  v_tenant_id := p_payment.tenant_id;

  -- CRITICAL: Validate tenant_id for service role context (webhooks)
  if v_tenant_id is null then
    raise warning 'create_sales_payment_journal_entry: No tenant_id on payment %, skipping', p_payment.id;
    return;
  end if;

  select exists (
           select 1
             from public.journal_entries
            where source_module = 'sales_payments'
              and source_reference = p_payment.id::text
              and tenant_id = v_tenant_id
        )
    into v_exists;

  if v_exists then
    return;
  end if;

  select id,
         invoice_number,
         customer_name,
         total
    into v_invoice
    from public.sales_invoices
   where id = p_payment.invoice_id;

  if not found then
    return;
  end if;

  -- Get payment method and its associated account
  select pm.id, pm.code, pm.name, a.id as account_id, a.code as account_code, a.name as account_name
    into v_payment_method
    from public.payment_methods pm
    join public.accounts a on a.id = pm.account_id
   where pm.id = p_payment.payment_method_id;

  if not found then
    raise exception 'Payment method not found for payment %', p_payment.id;
  end if;

  v_cash_account_id := v_payment_method.account_id;
  v_cash_account_code := v_payment_method.account_code;
  v_cash_account_name := v_payment_method.account_name;

  v_receivable_account_id := public.ensure_account(
    v_tenant_id,
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    null
  );

  v_description := format('Pago factura %s - %s', 
    coalesce(v_invoice.invoice_number, v_invoice.id::text),
    v_payment_method.name
  );

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
    v_tenant_id,
    public.get_next_document_number(v_tenant_id, 'journal_entry'),
    coalesce(p_payment.date, now()),
    v_description,
    'payment',
    'sales_payments',
    p_payment.id::text,
    'posted',
    p_payment.amount,
    p_payment.amount,
    now(),
    now()
  );

  v_subtotal := coalesce(nullif(p_payment.net_amount, 0), p_payment.amount);
  v_iva := coalesce(p_payment.iva_amount, 0);

  insert into public.journal_lines (
    id,
    tenant_id,
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
    v_tenant_id,
    v_entry_id,
    v_cash_account_id,
    v_cash_account_code,
    v_cash_account_name,
    format('Cobro a %s', coalesce(v_invoice.customer_name, 'Cliente')),
    p_payment.amount,
    0,
    now(),
    now()
  );

  insert into public.journal_lines (
    id,
    tenant_id,
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
    v_tenant_id,
    v_entry_id,
    v_receivable_account_id,
    v_receivable_account_code,
    v_receivable_account_name,
    format('Pago factura %s', coalesce(v_invoice.invoice_number, v_invoice.id::text)),
    0,
    p_payment.amount,
    now(),
    now()
  );
end;
$$;
