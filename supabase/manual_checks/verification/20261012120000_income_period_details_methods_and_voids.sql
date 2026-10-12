-- Read-back de 20261012120000: el detalle de ingresos trae el método, deja
-- fuera los cobros anulados, usa el día del taller y exige autoridad
-- contable; las dos series de caja tampoco suman anulados.

select 1 / case
  when pg_get_function_result('public.get_income_period_details(timestamptz,timestamptz,boolean)'::regprocedure)
         like '%payment_method_code text, payment_instrument text, settlement_provider text, occurred_at timestamp with time zone%'
   and pg_get_functiondef('public.get_income_period_details(timestamptz,timestamptz,boolean)'::regprocedure)
         like '%sp.deleted_at is null%'
   and pg_get_functiondef('public.get_income_period_details(timestamptz,timestamptz,boolean)'::regprocedure)
         like '%can_manage_tenant_payroll(v_tenant_id)%'
   and pg_get_functiondef('public.get_income_period_details(timestamptz,timestamptz,boolean)'::regprocedure)
         like '%at time zone v_timezone%'
   and has_function_privilege('authenticated', 'public.get_income_period_details(timestamptz,timestamptz,boolean)', 'execute')
   and not has_function_privilege('anon', 'public.get_income_period_details(timestamptz,timestamptz,boolean)', 'execute')
   and pg_get_functiondef('public.get_income_expense_daily_timeseries_internal(timestamptz,timestamptz,boolean)'::regprocedure)
         like '%sp.deleted_at is null%'
   and pg_get_functiondef('public.get_income_expense_timeseries_internal(integer,boolean)'::regprocedure)
         like '%sp.deleted_at is null%'
  then 1 else 0
end as assert_income_detail_methods_voids_and_gate;
