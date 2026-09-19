-- Falla si pagar un sueldo desde la conciliación vuelve a leer lo que debe la
-- semana antes de tomar el candado de Nómina.
select 1 / (case when
  position(':payroll-settlement' in pg_get_functiondef('public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)'::regprocedure)) > 0
  and position(':payroll-settlement' in pg_get_functiondef('public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)'::regprocedure))
    < position('bank_reconciliation_payroll_not_accessible' in pg_get_functiondef('public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)'::regprocedure))
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_payroll_advance_invalid%'
  and has_function_privilege('authenticated', 'public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)', 'EXECUTE')
then 1 else 0 end) as afirma_candado_de_nomina;
