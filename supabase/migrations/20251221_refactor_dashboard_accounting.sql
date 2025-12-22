-- Migration to refactor Accounting Dashboard logic
-- 1. Updates get_income_expense_timeseries to support Cash Flow mode
-- 2. Updates get_income_expense_daily_timeseries to support Cash Flow mode

-- Function 10.1: Get income/expense time series (Monthly)
create or replace function public.get_income_expense_timeseries(
  p_months integer default 12,
  p_is_cash_flow boolean default false
)
returns table (
  period_start date,
  period_end date,
  income numeric(14,2),
  expense numeric(14,2)
)
language sql
security definer
set search_path = public
as $$
  with month_windows as (
    select
      date_trunc('month', current_timestamp) - make_interval(months => m.month_index) as period_start
    from generate_series(0, greatest(p_months, 1) - 1) as m(month_index)
  )
  select
    mw.period_start::date,
    (mw.period_start + interval '1 month' - interval '1 day')::date as period_end,
    
    -- INCOME CALCULATION
    coalesce(
      case when p_is_cash_flow then
        -- Cash Flow: Sum of Sales Payments received in this period
        (
          select sum(amount)
          from sales_payments sp
          where sp.date >= mw.period_start
            and sp.date < mw.period_start + interval '1 month'
            and sp.tenant_id = user_tenant_id()
        )
      else
        -- Accrual: Sum of Income Journal Entries (posted)
        (
          select
            sum(coalesce(jl.credit_amount, 0) - coalesce(jl.debit_amount, 0))
          from journal_lines jl
          join journal_entries je on je.id = jl.entry_id
          join accounts a on a.id = jl.account_id
          where je.status = 'posted'
            and a.type = 'income'
            and je.entry_date >= mw.period_start
            and je.entry_date < mw.period_start + interval '1 month'
            and je.tenant_id = user_tenant_id()
            and jl.tenant_id = user_tenant_id()
            and a.tenant_id = user_tenant_id()
        )
      end,
      0
    )::numeric(14,2) as income,

    -- EXPENSE CALCULATION
    coalesce(
      case when p_is_cash_flow then
        -- Cash Flow: Sum of Purchase Payments made in this period
        (
          select sum(amount)
          from purchase_payments pp
          where pp.date >= mw.period_start
            and pp.date < mw.period_start + interval '1 month'
            and pp.tenant_id = user_tenant_id()
        )
      else
        -- Accrual: Sum of Expense Journal Entries (posted)
        (
          select
            sum(coalesce(jl.debit_amount, 0) - coalesce(jl.credit_amount, 0))
          from journal_lines jl
          join journal_entries je on je.id = jl.entry_id
          join accounts a on a.id = jl.account_id
          where je.status = 'posted'
            and a.type = 'expense'
            and je.entry_date >= mw.period_start
            and je.entry_date < mw.period_start + interval '1 month'
            and je.tenant_id = user_tenant_id()
            and jl.tenant_id = user_tenant_id()
            and a.tenant_id = user_tenant_id()
        )
      end,
      0
    )::numeric(14,2) as expense

  from month_windows mw
  order by mw.period_start;
$$;

-- Grant execute permissions to authenticated users
grant execute on function public.get_income_expense_timeseries(integer, boolean) to authenticated;


-- Function 10.1b: Get income/expense time series aggregated by day
create or replace function public.get_income_expense_daily_timeseries(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone,
  p_is_cash_flow boolean default false
)
returns table (
  period_start date,
  period_end date,
  income numeric(14,2),
  expense numeric(14,2)
)
language sql
security definer
set search_path = public
as $$
  with day_windows as (
    select
      (date_trunc('day', p_start_date) + make_interval(days => d.day_index))::date as period_start
    from generate_series(0, extract(days from (p_end_date - p_start_date))::integer) as d(day_index)
  )
  select
    dw.period_start::date,
    dw.period_start::date as period_end,

    -- INCOME CALCULATION
    coalesce(
      case when p_is_cash_flow then
        -- Cash Flow: Sales Payments
        (
          select sum(amount)
          from sales_payments sp
          where sp.date >= dw.period_start
            and sp.date < dw.period_start + interval '1 day'
            and sp.tenant_id = user_tenant_id()
        )
      else
        -- Accrual: Income Journal Entries
        (
          select
            sum(coalesce(jl.credit_amount, 0) - coalesce(jl.debit_amount, 0))
          from journal_lines jl
          join journal_entries je on je.id = jl.entry_id
          join accounts a on a.id = jl.account_id
          where je.status = 'posted'
            and a.type = 'income'
            and je.entry_date >= dw.period_start
            and je.entry_date < dw.period_start + interval '1 day'
            and je.tenant_id = user_tenant_id()
            and jl.tenant_id = user_tenant_id()
            and a.tenant_id = user_tenant_id()
        )
      end,
      0
    )::numeric(14,2) as income,

    -- EXPENSE CALCULATION
    coalesce(
      case when p_is_cash_flow then
        -- Cash Flow: Purchase Payments
        (
          select sum(amount)
          from purchase_payments pp
          where pp.date >= dw.period_start
            and pp.date < dw.period_start + interval '1 day'
            and pp.tenant_id = user_tenant_id()
        )
      else
        -- Accrual: Expense Journal Entries
        (
          select
            sum(coalesce(jl.debit_amount, 0) - coalesce(jl.credit_amount, 0))
          from journal_lines jl
          join journal_entries je on je.id = jl.entry_id
          join accounts a on a.id = jl.account_id
          where je.status = 'posted'
            and a.type = 'expense'
            and je.entry_date >= dw.period_start
            and je.entry_date < dw.period_start + interval '1 day'
            and je.tenant_id = user_tenant_id()
            and jl.tenant_id = user_tenant_id()
            and a.tenant_id = user_tenant_id()
        )
      end,
      0
    )::numeric(14,2) as expense

  from day_windows dw
  order by dw.period_start;
$$;

-- Grant execute permissions to authenticated users
grant execute on function public.get_income_expense_daily_timeseries(timestamp with time zone, timestamp with time zone, boolean) to authenticated;
