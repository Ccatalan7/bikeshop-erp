-- Deploy to Supabase: Fix expense journal entry creation (tenant_id missing)
-- Run this in Supabase SQL Editor
-- This fixes the issue where journal entries were not being created for expenses

-- Fix create_expense_journal_entry function
create or replace function public.create_expense_journal_entry(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_liability_account_id uuid;
  v_liability_account_code text := '2105';
  v_liability_account_name text := 'Cuentas por Pagar - Gastos';
  v_tax_account_id uuid;
  v_tax_account_code text := '2120';
  v_tax_account_name text := 'IVA Crédito Fiscal';
  v_cash_account record;
  v_total numeric(14,2);
  v_tax_total numeric(14,2);
  v_credit_account_id uuid;
  v_credit_account_code text;
  v_credit_account_name text;
  v_description text;
  v_supplier text;
  v_document text;
  v_line record;
  v_line_count integer := 0;
  v_default_account record;
begin
  select e.*
    into v_expense
    from public.expenses e
   where e.id = p_expense_id;

  if not found then
    return;
  end if;

  if lower(coalesce(v_expense.posting_status, 'draft')) <> 'posted' then
    return;
  end if;

  v_total := coalesce(v_expense.total_amount, 0);

  if v_total = 0 then
    return;
  end if;

  select exists (
           select 1
             from public.journal_entries
            where source_module = 'expenses'
              and source_reference = v_expense.id::text
         )
    into v_exists;

  if v_exists then
    perform public.delete_expense_journal_entry(p_expense_id);
  end if;

  -- Use tenant_id from expense record
  v_liability_account_id := coalesce(
    v_expense.liability_account_id,
    public.ensure_account(
      v_expense.tenant_id,
      v_liability_account_code,
      v_liability_account_name,
      'liability',
      'currentLiability',
      'Obligaciones por gastos pendientes de pago',
      null
    )
  );

  if v_expense.payment_account_id is not null then
    select a.id, a.code, a.name
      into v_cash_account
      from public.accounts a
     where a.id = v_expense.payment_account_id;
  elsif v_expense.payment_method_id is not null then
    select a.id, a.code, a.name
      into v_cash_account
      from public.payment_methods pm
      join public.accounts a on a.id = pm.account_id
     where pm.id = v_expense.payment_method_id;
  end if;

  v_tax_account_id := public.ensure_account(
    v_expense.tenant_id,
    v_tax_account_code,
    v_tax_account_name,
    'asset',
    'currentAsset',
    'Crédito fiscal IVA soportado en compras',
    null
  );

  v_supplier := coalesce(nullif(v_expense.supplier_name, ''), 'Proveedor');
  v_document := coalesce(nullif(v_expense.document_number, ''), v_expense.expense_number);
  v_description := format('Gasto %s - %s', v_document, v_supplier);

  -- Insert journal entry with tenant_id and proper sequence number
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
    v_expense.tenant_id,
    public.get_next_document_number(v_expense.tenant_id, 'journal_entry'),
    coalesce(v_expense.issue_date, now()),
    v_description,
    'purchase',
    'expenses',
    v_expense.expense_number,
    'posted',
    v_total,
    v_total,
    now(),
    now()
  );

  -- Insert expense line items as journal lines (with tenant_id)
  for v_line in
    select el.*
      from public.expense_lines el
     where el.expense_id = v_expense.id
     order by el.line_index, el.created_at
  loop
    v_line_count := v_line_count + 1;
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
      v_expense.tenant_id,
      v_entry_id,
      v_line.account_id,
      v_line.account_code,
      v_line.account_name,
      coalesce(nullif(v_line.description, ''), v_description),
      coalesce(v_line.subtotal, 0),
      0,
      now(),
      now()
    );
  end loop;

  -- If no lines, use default expense account
  if v_line_count = 0 then
    if v_expense.category_id is not null then
      select a.id, a.code, a.name
        into v_default_account
        from public.expense_categories ec
        join public.accounts a on a.id = ec.default_account_id
       where ec.id = v_expense.category_id;
    end if;

    if not found or v_default_account.id is null then
      select public.ensure_account(
               v_expense.tenant_id,
               '5200',
               'Gastos Generales',
               'expense',
               'operatingExpense',
               'Gastos generales y administrativos',
               null
             ) as id,
             '5200' as code,
             'Gastos Generales' as name
        into v_default_account;
    end if;

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
      v_expense.tenant_id,
      v_entry_id,
      v_default_account.id,
      v_default_account.code,
      v_default_account.name,
      v_description,
      coalesce(v_expense.subtotal, v_total - coalesce(v_expense.tax_amount, 0)),
      0,
      now(),
      now()
    );
  end if;

  -- Insert tax line if applicable
  v_tax_total := coalesce(v_expense.tax_amount, 0);
  if v_tax_total <> 0 then
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
      v_expense.tenant_id,
      v_entry_id,
      v_tax_account_id,
      v_tax_account_code,
      v_tax_account_name,
      format('IVA crédito gasto %s', v_document),
      v_tax_total,
      0,
      now(),
      now()
    );
  end if;

  -- Insert credit line (to cash or payables)
  if lower(coalesce(v_expense.payment_status, 'pending')) = 'paid'
     and coalesce(v_expense.balance, 0) <= 0.01
     and v_cash_account.id is not null then
    v_credit_account_id := v_cash_account.id;
    v_credit_account_code := v_cash_account.code;
    v_credit_account_name := v_cash_account.name;
  else
    v_credit_account_id := v_liability_account_id;
    select code, name
      into v_credit_account_code, v_credit_account_name
      from public.accounts
     where id = v_credit_account_id;
  end if;

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
    v_expense.tenant_id,
    v_entry_id,
    v_credit_account_id,
    v_credit_account_code,
    v_credit_account_name,
    v_description,
    0,
    v_total,
    now(),
    now()
  );
end;
$$;

-- Fix create_expense_payment_journal_entry function
create or replace function public.create_expense_payment_journal_entry(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment record;
  v_expense record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_liability_account_id uuid;
  v_liability_code text := '2105';
  v_liability_name text := 'Cuentas por Pagar - Gastos';
  v_cash_account record;
  v_description text;
begin
  select ep.*
    into v_payment
    from public.expense_payments ep
   where ep.id = p_payment_id;

  if not found then
    return;
  end if;

  select e.*
    into v_expense
    from public.expenses e
   where e.id = v_payment.expense_id;

  if not found then
    return;
  end if;

  if lower(coalesce(v_expense.posting_status, 'draft')) <> 'posted' then
    return;
  end if;

  if coalesce(v_payment.amount, 0) = 0 then
    return;
  end if;

  select exists (
           select 1
             from public.journal_entries
            where source_module = 'expense_payments'
              and source_reference = v_payment.id::text
         )
    into v_exists;

  if v_exists then
    return;
  end if;

  v_liability_account_id := coalesce(
    v_expense.liability_account_id,
    public.ensure_account(
      v_expense.tenant_id,
      v_liability_code,
      v_liability_name,
      'liability',
      'currentLiability',
      'Obligaciones por gastos pendientes de pago',
      null
    )
  );

  if v_payment.payment_account_id is not null then
    select a.id, a.code, a.name
      into v_cash_account
      from public.accounts a
     where a.id = v_payment.payment_account_id;
  elsif v_payment.payment_method_id is not null then
    select a.id, a.code, a.name
      into v_cash_account
      from public.payment_methods pm
      join public.accounts a on a.id = pm.account_id
     where pm.id = v_payment.payment_method_id;
  end if;

  if v_cash_account.id is null then
    select a.id, a.code, a.name
      into v_cash_account
      from public.accounts a
     where a.code = '1101'
     limit 1;
  end if;

  v_description := format('Pago gasto %s', coalesce(v_expense.expense_number, v_expense.id::text));

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
    v_expense.tenant_id,
    public.get_next_document_number(v_expense.tenant_id, 'journal_entry'),
    coalesce(v_payment.payment_date, now()),
    v_description,
    'payment',
    'expense_payments',
    v_expense.expense_number,
    'posted',
    v_payment.amount,
    v_payment.amount,
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
    v_expense.tenant_id,
    v_entry_id,
    v_liability_account_id,
    (select code from public.accounts where id = v_liability_account_id),
    (select name from public.accounts where id = v_liability_account_id),
    v_description,
    v_payment.amount,
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
    v_expense.tenant_id,
    v_entry_id,
    v_cash_account.id,
    v_cash_account.code,
    v_cash_account.name,
    v_description,
    0,
    v_payment.amount,
    now(),
    now()
  );
end;
$$;

-- Now manually create journal entry for the test expense
-- (since trigger didn't work before the fix)
select public.create_expense_journal_entry('7d831114-6b16-4db6-ad3f-b315df54b5c9');
