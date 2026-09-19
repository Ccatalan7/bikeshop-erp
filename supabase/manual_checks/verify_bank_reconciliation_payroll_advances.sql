-- Falla si la conciliación no conoce los anticipos abiertos de Nómina o no
-- los puede aplicar al pagar un sueldo.
select 1 / (case when
  pg_get_functiondef('public.get_bank_reconciliation_candidates_v2(uuid,date,date)'::regprocedure)
    like '%''open_advances'', v_open_advances%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_payroll_advance_invalid%'
  and has_function_privilege('authenticated', 'public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_bank_reconciliation_candidates_v2(uuid,date,date)', 'EXECUTE')
then 1 else 0 end) as afirma_anticipos;
