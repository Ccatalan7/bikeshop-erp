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
      result.id,
      result.document_number,
      result.description,
      result.account_name,
      result.amount,
      result.transaction_date,
      result.source_type,
      result.account_id,
      result.account_code
    from (
    select
      payment.id as id,
      invoice.invoice_number as document_number,
      coalesce(supplier.name, 'Proveedor') as description,
      'Pago a Proveedor'::text as account_name,
      payment.amount::numeric(14,2) as amount,
      payment.date::date as transaction_date,
      'purchase_payment'::text as source_type,
      null::uuid as account_id,
      null::text as account_code
    from public.purchase_payments payment
    left join public.purchase_invoices invoice on invoice.id = payment.invoice_id
    left join public.suppliers supplier on supplier.id = invoice.supplier_id
    where payment.date >= p_start_date
      and payment.date < p_end_date
      and payment.tenant_id = public.user_tenant_id()

    union all

    select
      expense.id,
      expense.expense_number,
      coalesce(expense.supplier_name, 'Gasto'),
      account.name,
      line.total::numeric(14,2),
      expense.paid_at::date,
      'expense'::text,
      account.id,
      account.code
    from public.expenses expense
    join public.expense_lines line on line.expense_id = expense.id
    join public.accounts account on account.id = line.account_id
    where expense.payment_status = 'paid'
      and expense.paid_at >= p_start_date
      and expense.paid_at < p_end_date
      and expense.tenant_id = public.user_tenant_id()
      and account.type = 'expense'
    ) result
    order by result.transaction_date desc, result.amount desc;
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
) from public;

grant execute on function public.get_expense_period_details(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) to authenticated;
