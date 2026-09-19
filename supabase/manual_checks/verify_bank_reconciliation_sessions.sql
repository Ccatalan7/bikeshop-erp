-- Falla si la conciliación no queda registrada con su borrador, si el
-- borrador puede pisarse sin revisión o si los privilegios se abrieron.
select
  to_regclass('public.bank_reconciliation_sessions') is not null as tabla_conciliaciones,
  exists (select 1 from pg_constraint where conname = 'bank_statement_imports_session_fk')
    as cartola_ligada;

select 1 / (case when
  to_regclass('public.bank_reconciliation_sessions') is not null
  and exists (select 1 from pg_constraint where conname = 'bank_statement_imports_session_fk')
  and pg_get_functiondef('public.save_bank_reconciliation_session_draft_v1(uuid,bigint,jsonb)'::regprocedure)
    like '%bank_reconciliation_draft_conflict%'
  and pg_get_functiondef('public.open_bank_reconciliation_session_v1(uuid,uuid[])'::regprocedure)
    like '%bank_statement_import_not_accessible%'
  and pg_get_functiondef('public.list_bank_reconciliation_sessions_v1(uuid)'::regprocedure)
    like '%decided_count%'
then 1 else 0 end) as afirma_conciliaciones;

select 1 / (case when
  has_function_privilege('authenticated', 'public.open_bank_reconciliation_session_v1(uuid,uuid[])', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.save_bank_reconciliation_session_draft_v1(uuid,bigint,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.list_bank_reconciliation_sessions_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.open_bank_reconciliation_session_v1(uuid,uuid[])', 'EXECUTE')
  and not has_function_privilege('anon', 'public.save_bank_reconciliation_session_draft_v1(uuid,bigint,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.list_bank_reconciliation_sessions_v1(uuid)', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.bank_reconciliation_sessions', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.bank_reconciliation_sessions', 'INSERT')
then 1 else 0 end) as afirma_privilegios;
