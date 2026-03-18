-- Fix balance sheet aggregation and rebuild polluted sales payment journal entries.
-- Root causes fixed here:
-- 1. Balance sheet was summing journal lines before filtering posted entries by date.
-- 2. Sales payment journal entries were historically written inconsistently and, in one deployed variant,
--    split IVA into account 2105, polluting both Accounts Receivable and IVA liabilities.

create or replace function public.create_sales_payment_journal_entry(p_payment public.sales_payments)
returns void as $$
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
begin
  if p_payment.invoice_id is null then
    return;
  end if;

  if p_payment.deleted_at is not null then
    return;
  end if;

  v_tenant_id := p_payment.tenant_id;

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
  ), (
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
$$ language plpgsql security definer set search_path = public;

create or replace function public.get_balance_sheet_data(
  p_as_of_date timestamp with time zone
)
returns table (
  account_type text,
  type_label text,
  category text,
  category_label text,
  account_code text,
  account_name text,
  amount numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.type as account_type,
    case a.type
      when 'asset' then 'ACTIVOS'
      when 'liability' then 'PASIVOS'
      when 'equity' then 'PATRIMONIO'
      else a.type
    end as type_label,
    a.category,
    case a.category
      when 'currentAsset' then 'Activos Circulantes'
      when 'fixedAsset' then 'Activos Fijos'
      when 'otherAsset' then 'Otros Activos'
      when 'currentLiability' then 'Pasivos Circulantes'
      when 'longTermLiability' then 'Pasivos Largo Plazo'
      when 'capital' then 'Capital'
      when 'retainedEarnings' then 'Utilidades Retenidas'
      else a.category
    end as category_label,
    a.code as account_code,
    a.name as account_name,
    case
      when a.type = 'asset' then
        coalesce(b.total_debit, 0) - coalesce(b.total_credit, 0)
      when a.type in ('liability', 'equity') then
        coalesce(b.total_credit, 0) - coalesce(b.total_debit, 0)
      else 0
    end::numeric(14,2) as amount
  from accounts a
  left join (
    select
      jl.tenant_id,
      jl.account_id,
      coalesce(sum(jl.debit_amount), 0) as total_debit,
      coalesce(sum(jl.credit_amount), 0) as total_credit
    from journal_lines jl
    join journal_entries je
      on je.id = jl.entry_id
     and je.tenant_id = jl.tenant_id
   where jl.tenant_id = user_tenant_id()
     and je.tenant_id = user_tenant_id()
     and je.status = 'posted'
     and je.entry_date <= p_as_of_date
   group by jl.tenant_id, jl.account_id
  ) b on b.account_id = a.id and b.tenant_id = a.tenant_id
  where a.type in ('asset', 'liability', 'equity')
    and a.is_active = true
    and a.tenant_id = user_tenant_id()
  group by a.id, a.code, a.name, a.type, a.category, b.total_debit, b.total_credit
  having (coalesce(b.total_debit, 0) <> 0 
       or coalesce(b.total_credit, 0) <> 0)
  order by 
    case a.type 
      when 'asset' then 1 
      when 'liability' then 2 
      when 'equity' then 3 
      else 4 
    end,
    a.category,
    a.code;
end;
$$;

-- Normalize chart accounts that were polluted by an earlier payment-level IVA deployment.
update public.accounts
   set name = 'Cuentas por Pagar - Gastos',
       type = 'liability',
       category = 'currentLiability',
       description = 'Obligaciones por gastos operacionales',
       is_active = true,
       updated_at = now()
 where code = '2105';

update public.accounts
   set name = 'IVA Débito Fiscal',
       type = 'liability',
       category = 'currentLiability',
       description = 'IVA generado en ventas',
       is_active = true,
       updated_at = now()
 where code = '2150';

-- Rebuild all sales payment journal entries from source payments using the corrected function.
delete from public.journal_entries
 where source_module = 'sales_payments';

do $$
declare
  v_payment public.sales_payments%rowtype;
begin
  for v_payment in
    select *
      from public.sales_payments
     where deleted_at is null
     order by date nulls last, created_at, id
  loop
    perform public.create_sales_payment_journal_entry(v_payment);
  end loop;
end $$;


-- Fix inconsistent expense journal entry references and rebuild posted expense JEs.
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