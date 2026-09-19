-- Falla si la lista de conciliaciones vuelve a contar los análisis de la IA
-- como decisiones del operador.
select 1 / (case when
  pg_get_functiondef('public.list_bank_reconciliation_sessions_v1(uuid)'::regprocedure)
    like '%draft_decisions%'
  and pg_get_functiondef('public.list_bank_reconciliation_sessions_v1(uuid)'::regprocedure)
    like '%draft_analyses%'
  and has_function_privilege('authenticated', 'public.list_bank_reconciliation_sessions_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.list_bank_reconciliation_sessions_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.list_bank_reconciliation_sessions_v1(uuid)', 'EXECUTE')
then 1 else 0 end) as afirma_conteos_del_borrador;
