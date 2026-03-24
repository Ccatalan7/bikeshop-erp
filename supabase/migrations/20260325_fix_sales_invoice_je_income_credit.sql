-- =============================================================================
-- Migration: Fix sales invoice journal entries — income credit wrong amount
--
-- ROOT CAUSE
-- ----------
-- create_sales_invoice_journal_entry() debited AR by p_invoice.total (correct)
-- but credited Income by v_subtotal (= net_amount). For invoices with mixed
-- tax/no-tax lines or discounts, net_amount + iva_amount < total, so the credit
-- sum was less than the AR debit → structurally imbalanced JE.
--   AS-00898 through AS-00966: 10 JEs with total excess DR = 593,499.90
--
-- FIX (function, core_schema.sql line 5955)
-- ------------------------------------------
-- Income credit = v_total - v_iva (the non-IVA remainder of the invoice total).
-- This ALWAYS balances: (v_total - v_iva) + v_iva = v_total = AR debit.
-- Guard condition updated accordingly: "if v_total - v_iva <> 0" (was "if v_subtotal <> 0").
--
-- DATA REPAIR
-- -----------
-- 10 existing JEs have stale (too-small) income credit amounts.
-- We UPDATE journal_lines.credit_amount to total - iva_amount for those lines,
-- and reset journal_entries.total_credit = total_debit for each JE header.
-- =============================================================================

-- -------------------------------------------------------------------------
-- STEP 1: Redeploy fixed function (core_schema.sql lines 5732-6029)
-- -------------------------------------------------------------------------
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

  -- Income credit = total - iva (NOT net_amount).
  -- This ensures DR(AR) = CR(Income) + CR(IVA) for all invoice types including
  -- mixed tax/no-tax and discounted invoices.
  if v_total - v_iva <> 0 then
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
      v_total - v_iva,
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
      format('Costo de ventas %s', v_invoice_number),
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


-- -------------------------------------------------------------------------
-- STEP 2: Repair the 10 imbalanced journal entries
-- Each: UPDATE income line credit to (invoice.total - invoice.iva_amount)
--       and reset JE header total_credit = total_debit (= invoice.total)
-- -------------------------------------------------------------------------

-- AS-00898 / FV-00323: income 226891 -> 376891 (+150000)
UPDATE journal_lines SET credit_amount = 376891    WHERE id = '923fe118-0ae0-4c4b-b569-bd6aaa7d0aec';
UPDATE journal_entries SET total_credit = 420000   WHERE id = 'a4021dc6-4250-4160-a9fc-ec070027ea99';

-- AS-00903 / FV-00292: income 36134 -> 79134 (+43000)
UPDATE journal_lines SET credit_amount = 79134     WHERE id = 'd6e09bcc-b429-434c-b64b-f588ab6ad043';
UPDATE journal_entries SET total_credit = 86000    WHERE id = '0ec22d43-c046-4cf1-bfcf-70fa3de0b4e7';

-- AS-00906 / FV-00354: income 12605 -> 42605 (+30000)
UPDATE journal_lines SET credit_amount = 42605     WHERE id = 'e3181491-b68e-4eff-abd3-0d9909ca203c';
UPDATE journal_entries SET total_credit = 45000    WHERE id = '48486d52-12a1-414b-9b63-ac8e125f49cc';

-- AS-00907 / FV-00072: income 84034 -> 202034 (+118000)
UPDATE journal_lines SET credit_amount = 202034    WHERE id = 'af71ef9e-8106-450a-b70a-1ea63a349605';
UPDATE journal_entries SET total_credit = 218000   WHERE id = '0891456f-4052-4470-91ec-88206401fbf0';

-- AS-00911 / FV-00424: income 46218 -> 101218 (+55000)
UPDATE journal_lines SET credit_amount = 101218    WHERE id = 'a524f101-9249-4629-b1da-ffaff366dc79';
UPDATE journal_entries SET total_credit = 110000   WHERE id = 'be4e04b2-5254-4fed-97a2-b84f6ce8282e';

-- AS-00913 / FV-00403: income 37815 -> 42315 (+4500)
UPDATE journal_lines SET credit_amount = 42315     WHERE id = '5c1805dc-8d23-42f9-ba51-46a9b0a72a9e';
UPDATE journal_entries SET total_credit = 49500    WHERE id = '4a2a8a08-b9d7-4e5c-b048-0446f2ccdf56';

-- AS-00935 / FV-00182: income 15126 -> 22125.90 (+6999.90)
UPDATE journal_lines SET credit_amount = 22125.90  WHERE id = '2869bbd1-fbb4-4ab0-b124-84d0eea5f681';
UPDATE journal_entries SET total_credit = 24999.90 WHERE id = '77cb3c75-e17c-44d8-9670-ca46b16847ec';

-- AS-00950 / FV-00364: income 21008 -> 103008 (+82000)
UPDATE journal_lines SET credit_amount = 103008    WHERE id = 'e660058f-c7cb-4688-b650-2fbb28affb2a';
UPDATE journal_entries SET total_credit = 107000   WHERE id = 'a8042b6c-7656-451a-9060-28a6340453a4';

-- AS-00958 / FV-00399: income 88235 -> 188235 (+100000)
UPDATE journal_lines SET credit_amount = 188235    WHERE id = 'dcf95577-2658-455e-b7af-2d51aade376d';
UPDATE journal_entries SET total_credit = 205000   WHERE id = '2486e079-e48d-46de-810b-73566774aad3';

-- AS-00966 / FV-00426: income 27731 -> 31731 (+4000)
UPDATE journal_lines SET credit_amount = 31731     WHERE id = '4897f929-533a-42f5-ac4a-18d4980124ff';
UPDATE journal_entries SET total_credit = 37000    WHERE id = '5be7a570-b894-48ab-b611-29bbc700b928';
