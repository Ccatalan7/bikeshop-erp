-- Falla si el catálogo no trae desde qué día Nómina acepta un sueldo, o si lo
-- calcula con otra regla que la del kernel de pago.
select 1 / (case when
  pg_get_functiondef('public.get_bank_reconciliation_candidates_v2(uuid,date,date)'::regprocedure)
    like '%''payable_from'', public.payroll_period_operational_close_date(%'
  and has_function_privilege('authenticated', 'public.get_bank_reconciliation_candidates_v2(uuid,date,date)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_bank_reconciliation_candidates_v2(uuid,date,date)', 'EXECUTE')
then 1 else 0 end) as afirma_payable_from;
