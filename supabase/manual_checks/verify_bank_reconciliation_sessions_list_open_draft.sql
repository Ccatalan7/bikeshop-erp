-- Falla si la lista de conciliaciones vuelve a contar como «sin aplicar» lo
-- que una cartola ya aplicó.
select 1 / (case when
  pg_get_functiondef('public.list_bank_reconciliation_sessions_v1(uuid)'::regprocedure)
    like '%decided_import.file_sha256%'
  and pg_get_functiondef('public.list_bank_reconciliation_sessions_v1(uuid)'::regprocedure)
    like '%draft_decisions%'
  and pg_get_functiondef('public.list_bank_reconciliation_sessions_v1(uuid)'::regprocedure)
    like '%draft_analyses%'
  and has_function_privilege('authenticated', 'public.list_bank_reconciliation_sessions_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.list_bank_reconciliation_sessions_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.list_bank_reconciliation_sessions_v1(uuid)', 'EXECUTE')
then 1 else 0 end) as afirma_borrador_sin_lo_aplicado;
