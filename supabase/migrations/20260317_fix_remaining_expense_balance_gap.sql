-- Fix the remaining 6,961.34 balance-sheet gap.
-- This rebuilds posted expense journal entries using the correct expense-number reference.
-- It removes four stale expense JEs that still debit 2120 without a matching extra credit:
-- GTO-00004, GTO-00014, GTO-00046, GTO-00047

create or replace function public.delete_expense_journal_entry(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_expense_id is null then
    return;
  end if;

  delete from public.journal_entries
   where source_module = 'expenses'
     and source_reference = (
       select e.expense_number
         from public.expenses e
        where e.id = p_expense_id
     );

  delete from public.journal_entries
   where source_module = 'expenses'
     and source_reference = p_expense_id::text;
end;
$$;

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
              and source_reference = v_expense.expense_number
         )
    into v_exists;

  if v_exists then
    perform public.delete_expense_journal_entry(p_expense_id);
  end if;

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

  select null::uuid as id, null::text as code, null::text as name
    into v_cash_account;

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

delete from public.journal_entries
 where source_module = 'expenses';

do $$
declare
  v_expense_id uuid;
begin
  for v_expense_id in
    select e.id
      from public.expenses e
     where lower(coalesce(e.posting_status, 'draft')) = 'posted'
     order by e.issue_date nulls last, e.created_at, e.id
  loop
    perform public.create_expense_journal_entry(v_expense_id);
  end loop;
end $$;
