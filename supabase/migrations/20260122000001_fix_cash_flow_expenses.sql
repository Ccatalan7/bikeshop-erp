-- Migration: Fix Cash Flow Expense Calculation
-- 
-- Issue: The get_income_expense_timeseries and get_income_expense_daily_timeseries
-- functions only counted purchase_payments for cash flow expenses, ignoring
-- paid operating expenses (salaries, rent, utilities, etc.) from the expenses table.
--
-- This fix adds paid expenses to the cash flow expense calculation.

-- Function 10.1: Get income/expense time series (Monthly) - FIXED
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

    -- EXPENSE CALCULATION (FIXED)
    coalesce(
      case when p_is_cash_flow then
        -- Cash Flow: Sum of ALL cash outflows in this period
        (
          -- 1. Purchase payments (payments to suppliers for inventory/purchases)
          coalesce((
            select sum(amount)
            from purchase_payments pp
            where pp.date >= mw.period_start
              and pp.date < mw.period_start + interval '1 month'
              and pp.tenant_id = user_tenant_id()
          ), 0)
          +
          -- 2. Paid operating expenses (salaries, rent, utilities, services, etc.)
          coalesce((
            select sum(el.total)
            from expenses e
            join expense_lines el on el.expense_id = e.id
            join accounts a on a.id = el.account_id
            where e.payment_status = 'paid'
              and e.paid_at >= mw.period_start
              and e.paid_at < mw.period_start + interval '1 month'
              and e.tenant_id = user_tenant_id()
              and a.type = 'expense'
          ), 0)
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


-- Function 10.1b: Get income/expense time series aggregated by day - FIXED
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

    -- EXPENSE CALCULATION (FIXED)
    coalesce(
      case when p_is_cash_flow then
        -- Cash Flow: Sum of ALL cash outflows on this day
        (
          -- 1. Purchase payments
          coalesce((
            select sum(amount)
            from purchase_payments pp
            where pp.date >= dw.period_start
              and pp.date < dw.period_start + interval '1 day'
              and pp.tenant_id = user_tenant_id()
          ), 0)
          +
          -- 2. Paid operating expenses
          coalesce((
            select sum(el.total)
            from expenses e
            join expense_lines el on el.expense_id = e.id
            join accounts a on a.id = el.account_id
            where e.payment_status = 'paid'
              and e.paid_at >= dw.period_start
              and e.paid_at < dw.period_start + interval '1 day'
              and e.tenant_id = user_tenant_id()
              and a.type = 'expense'
          ), 0)
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
