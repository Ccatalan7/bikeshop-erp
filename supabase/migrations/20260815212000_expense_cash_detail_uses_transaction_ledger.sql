-- Cash-basis expense drill-down must describe the actual money movements.
--
-- expenses.paid_at is a settlement summary on the expense header. It can be
-- the date of the latest partial payment or the date when an older employee
-- advance was applied, so it is not the cash transaction date. The monthly
-- and daily cash projections already use the transaction ledgers below; keep
-- their drill-down on the same owners.
-- Deployment target: production xzdvtzdqjeyqxnkqprtf

set lock_timeout = '5s';
set statement_timeout = '30s';

create or replace function public.get_expense_period_details(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone,
  p_is_cash_flow boolean
)
returns table (
  id uuid,
  document_number text,
  description text,
  account_name text,
  amount numeric,
  transaction_date date,
  source_type text,
  account_id uuid,
  account_code text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_is_cash_flow then
    return query
    select
      movement.id,
      movement.document_number,
      movement.description,
      movement.account_name,
      movement.amount,
      movement.transaction_date,
      movement.source_type,
      movement.account_id,
      movement.account_code
    from (
      -- Supplier payments already own their real cash date.
      select
        payment.id,
        invoice.invoice_number as document_number,
        coalesce(nullif(btrim(supplier.name), ''), 'Proveedor') as description,
        'Pago a Proveedor'::text as account_name,
        payment.amount::numeric(14,2) as amount,
        public.tenant_business_date(
          payment.tenant_id,
          payment.date
        ) as transaction_date,
        'purchase_payment'::text as source_type,
        null::uuid as account_id,
        null::text as account_code
      from public.purchase_payments payment
      left join public.purchase_invoices invoice
        on invoice.id = payment.invoice_id
       and invoice.tenant_id = payment.tenant_id
      left join public.suppliers supplier
        on supplier.id = invoice.supplier_id
       and supplier.tenant_id = payment.tenant_id
      where payment.date >= p_start_date
        and payment.date < p_end_date
        and payment.tenant_id = public.user_tenant_id()

      union all

      -- One row per actual operating-expense payment. A split payment remains
      -- two dated movements instead of being collapsed into expenses.paid_at.
      select
        payment.id,
        expense.expense_number,
        coalesce(
          nullif(btrim(expense.supplier_name), ''),
          'Gasto'
        ) as description,
        case
          when line_summary.line_count = 1 then line_summary.account_name
          else 'Varias cuentas'
        end as account_name,
        payment.amount::numeric(14,2) as amount,
        public.tenant_business_date(
          payment.tenant_id,
          payment.payment_date
        ) as transaction_date,
        'expense'::text as source_type,
        case
          when line_summary.line_count = 1 then line_summary.account_id
          else null::uuid
        end as account_id,
        case
          when line_summary.line_count = 1 then line_summary.account_code
          else null::text
        end as account_code
      from public.expense_payments payment
      join public.expenses expense
        on expense.id = payment.expense_id
       and expense.tenant_id = payment.tenant_id
      left join lateral (
        select
          count(*)::integer as line_count,
          (array_agg(account.id order by line.line_index, line.id))[1]
            as account_id,
          (array_agg(account.code order by line.line_index, line.id))[1]
            as account_code,
          (array_agg(account.name order by line.line_index, line.id))[1]
            as account_name
        from public.expense_lines line
        join public.accounts account
          on account.id = line.account_id
         and account.tenant_id = line.tenant_id
         and account.type = 'expense'
        where line.expense_id = expense.id
          and line.tenant_id = expense.tenant_id
      ) line_summary on true
      where payment.payment_date >= p_start_date
        and payment.payment_date < p_end_date
        and payment.tenant_id = public.user_tenant_id()
        and expense.posting_status <> 'void'

      union all

      -- An employee advance is cash when it is paid, not when a later payroll
      -- allocation consumes it.
      select
        advance.id,
        coalesce(nullif(btrim(advance.reference), ''), 'Anticipo')
          as document_number,
        concat_ws(
          ' ',
          'Anticipo a',
          nullif(btrim(employee.first_name), ''),
          nullif(btrim(employee.last_name), '')
        ) as description,
        coalesce(advance_account.name, 'Anticipos al Personal')
          as account_name,
        advance.amount::numeric(14,2) as amount,
        public.tenant_business_date(
          advance.tenant_id,
          advance.paid_at
        ) as transaction_date,
        'employee_advance'::text as source_type,
        advance_account.id as account_id,
        coalesce(advance_account.code, '1135') as account_code
      from public.employee_advances advance
      join public.employees employee
        on employee.id = advance.employee_id
       and employee.tenant_id = advance.tenant_id
      left join lateral (
        select account.id, account.code, account.name
        from public.accounts account
        where account.tenant_id = advance.tenant_id
          and account.code = '1135'
        order by account.id
        limit 1
      ) advance_account on true
      where advance.paid_at >= p_start_date
        and advance.paid_at < p_end_date
        and advance.tenant_id = public.user_tenant_id()
        and advance.status <> 'voided'

      union all

      -- Preserve genuinely legacy paid expenses that predate both transaction
      -- ledgers. They remain a fallback only and cannot duplicate a payment or
      -- an employee advance allocation.
      select
        expense.id,
        expense.expense_number,
        coalesce(
          nullif(btrim(expense.supplier_name), ''),
          'Gasto'
        ) as description,
        case
          when line_summary.line_count = 1 then line_summary.account_name
          else 'Varias cuentas'
        end as account_name,
        expense.total_amount::numeric(14,2) as amount,
        public.tenant_business_date(
          expense.tenant_id,
          expense.paid_at
        ) as transaction_date,
        'expense'::text as source_type,
        case
          when line_summary.line_count = 1 then line_summary.account_id
          else null::uuid
        end as account_id,
        case
          when line_summary.line_count = 1 then line_summary.account_code
          else null::text
        end as account_code
      from public.expenses expense
      left join lateral (
        select
          count(*)::integer as line_count,
          (array_agg(account.id order by line.line_index, line.id))[1]
            as account_id,
          (array_agg(account.code order by line.line_index, line.id))[1]
            as account_code,
          (array_agg(account.name order by line.line_index, line.id))[1]
            as account_name
        from public.expense_lines line
        join public.accounts account
          on account.id = line.account_id
         and account.tenant_id = line.tenant_id
         and account.type = 'expense'
        where line.expense_id = expense.id
          and line.tenant_id = expense.tenant_id
      ) line_summary on true
      where expense.payment_status = 'paid'
        and expense.paid_at >= p_start_date
        and expense.paid_at < p_end_date
        and expense.tenant_id = public.user_tenant_id()
        and expense.posting_status <> 'void'
        and not exists (
          select 1
          from public.expense_payments payment
          where payment.expense_id = expense.id
            and payment.tenant_id = expense.tenant_id
        )
        and not exists (
          select 1
          from public.employee_advance_allocations allocation
          join public.payroll_voucher_lines voucher_line
            on voucher_line.id = allocation.voucher_line_id
           and voucher_line.tenant_id = allocation.tenant_id
          where voucher_line.expense_id = expense.id
            and allocation.tenant_id = expense.tenant_id
        )
    ) movement
    order by
      movement.transaction_date desc,
      movement.amount desc,
      movement.id;
  else
    return query
    select
      entry.id,
      coalesce(entry.source_reference, ''),
      entry.description,
      account.name,
      (
        coalesce(sum(line.debit_amount), 0)
        - coalesce(sum(line.credit_amount), 0)
      )::numeric(14,2),
      entry.entry_date::date,
      'journal_entry'::text,
      account.id,
      account.code
    from public.journal_lines line
    join public.journal_entries entry on entry.id = line.entry_id
    join public.accounts account on account.id = line.account_id
    where entry.status = 'posted'
      and account.type = 'expense'
      and entry.entry_date >= p_start_date
      and entry.entry_date < p_end_date
      and entry.tenant_id = public.user_tenant_id()
      and line.tenant_id = public.user_tenant_id()
      and account.tenant_id = public.user_tenant_id()
    group by
      entry.id,
      entry.source_reference,
      entry.description,
      account.name,
      entry.entry_date,
      account.id,
      account.code
    having (
      coalesce(sum(line.debit_amount), 0)
      - coalesce(sum(line.credit_amount), 0)
    ) <> 0
    order by entry.entry_date desc, amount desc;
  end if;
end;
$$;

revoke all on function public.get_expense_period_details(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) from public, anon, service_role;

grant execute on function public.get_expense_period_details(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) to authenticated;

comment on function public.get_expense_period_details(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) is
  'Expense drill-down by accounting entry in accrual mode and by the authoritative purchase-payment, expense-payment, employee-advance, or explicit legacy fallback transaction date in cash mode.';
