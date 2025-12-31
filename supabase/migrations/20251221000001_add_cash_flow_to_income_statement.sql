-- Cash Flow Statement (Efectivo) vs Income Statement (Devengado)
-- Updated Dec 31, 2025

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
    -- CASH FLOW STATEMENT (Estado de Flujo de Efectivo)
    -- Shows ACTUAL cash movements, not accrual accounting
    return query
    
    -- CASH IN: Payments received from customers
    select 
      'operatingIncome'::text as category,
      'Ingresos de Efectivo'::text as category_label,
      '4000'::text as account_code,
      'Cobros de Clientes'::text as account_name,
      coalesce(sum(sp.amount), 0)::numeric(14,2) as amount
    from sales_payments sp
    where sp.date >= p_start_date
      and sp.date <= p_end_date
      and sp.tenant_id = user_tenant_id()
      
    union all
    
    -- CASH OUT: Payments to suppliers (inventory purchases)
    select 
      'costOfGoodsSold'::text as category,
      'Egresos de Efectivo - Proveedores'::text as category_label,
      '5000'::text as account_code,
      'Pagos a Proveedores'::text as account_name,
      coalesce(sum(pp.amount), 0)::numeric(14,2) as amount
    from purchase_payments pp
    where pp.date >= p_start_date
      and pp.date <= p_end_date
      and pp.tenant_id = user_tenant_id()
      
    union all
    
    -- CASH OUT: Operating expenses paid (payroll, rent, utilities, etc.)
    select 
      a.category,
      'Egresos de Efectivo - Gastos'::text as category_label,
      a.code as account_code,
      a.name as account_name,
      coalesce(sum(el.total), 0)::numeric(14,2) as amount
    from expenses e
    join expense_lines el on el.expense_id = e.id
    join accounts a on a.id = el.account_id
    where e.payment_status = 'paid'
      and e.paid_at >= p_start_date
      and e.paid_at <= p_end_date
      and e.tenant_id = user_tenant_id()
      and a.type = 'expense'
    group by a.category, a.code, a.name;

  else
    -- INCOME STATEMENT (Estado de Resultados) - Accrual Basis
    -- Shows revenue when earned, expenses when incurred
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
