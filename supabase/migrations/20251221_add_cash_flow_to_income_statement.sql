-- Migration to add Cash Flow support to Income Statement
-- Replaces get_income_statement_data to accept p_is_cash_flow parameter

create or replace function public.get_income_statement_data(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone,
  p_is_cash_flow boolean default false
)
returns table (
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
  if p_is_cash_flow then
    -- CASH FLOW BASIS
    -- Returns simplified categories based on actual payments
    return query
    
    -- 1. Sales Income (Realized) from Sales Payments
    select 
      'operatingIncome'::text as category,
      'Ingresos Operacionales'::text as category_label,
      '4000'::text as account_code,
      'Ventas Cobradas (Efectivo)'::text as account_name,
      coalesce(sum(sp.amount), 0)::numeric(14,2) as amount
    from sales_payments sp
    where sp.date >= p_start_date
      and sp.date <= p_end_date
      and sp.tenant_id = user_tenant_id()
      
    union all
    
    -- 2. Cost of Sales / Expenses (Realized) from Purchase Payments
    select 
      'operatingExpense'::text as category,
      'Gastos Operacionales'::text as category_label,
      '5000'::text as account_code,
      'Compras Pagadas (Efectivo)'::text as account_name,
      coalesce(sum(pp.amount), 0)::numeric(14,2) as amount
    from purchase_payments pp
    where pp.date >= p_start_date
      and pp.date <= p_end_date
      and pp.tenant_id = user_tenant_id();

  else
    -- ACCRUAL BASIS (Standard Logic)
    -- Uses INNER JOIN to strictly respect date range
    return query
    select
      a.category,
      case a.category
        when 'operatingIncome' then 'Ingresos Operacionales'
        when 'nonOperatingIncome' then 'Ingresos No Operacionales'
        when 'costOfGoodsSold' then 'Costo de Ventas'
        when 'operatingExpense' then 'Gastos Operacionales'
        when 'financialExpense' then 'Gastos Financieros'
        when 'taxExpense' then 'Impuestos'
        else a.category
      end as category_label,
      a.code as account_code,
      a.name as account_name,
      case
        when a.type = 'income' then
          coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
        when a.type = 'expense' then
          coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
        else 0
      end::numeric(14,2) as amount
    from accounts a
    join journal_lines jl on jl.account_id = a.id AND jl.tenant_id = user_tenant_id()
    join journal_entries je on je.id = jl.entry_id
      and je.entry_date >= p_start_date
      and je.entry_date <= p_end_date
      and je.status = 'posted'
      and je.tenant_id = user_tenant_id()
    where a.type in ('income', 'expense')
      and a.is_active = true
      and a.tenant_id = user_tenant_id()
    group by a.id, a.code, a.name, a.type, a.category
    having (coalesce(sum(jl.debit_amount), 0) <> 0 
         or coalesce(sum(jl.credit_amount), 0) <> 0)
    order by a.code;
  end if;
end;
$$;
