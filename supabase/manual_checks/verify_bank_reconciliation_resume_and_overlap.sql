-- Falla si una cartola aplicada sigue cerrada para lo pendiente, si un
-- movimiento ya conciliado en otra cartola puede conciliarse de nuevo, o si
-- el catálogo sigue ofreciendo lo que una fila ya explica.
select
  pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_row_already_decided%' as decididas_firmes,
  pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_row_settled_elsewhere%' as guardia_entre_cartolas,
  pg_get_functiondef('public.get_bank_reconciliation_candidates_v2(uuid,date,date)'::regprocedure)
    like '%''reconciled_rows''%' as catalogo_trae_conciliadas;

select 1 / (case when
  pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_row_already_decided%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_row_settled_elsewhere%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_settled_elsewhere_unproven%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    not like '%generated_review_immutable%'
then 1 else 0 end) as afirma_retomar_y_guardia;

select 1 / (case when
  pg_get_functiondef('public.get_bank_reconciliation_candidates_v2(uuid,date,date)'::regprocedure)
    like '%''reconciled_rows'', v_reconciled_rows%'
  and pg_get_functiondef('public.get_bank_reconciliation_candidates_v2(uuid,date,date)'::regprocedure)
    like '%from public.bank_reconciliation_allocations allocation%'
then 1 else 0 end) as afirma_catalogo;

-- El núcleo sigue privado; el catálogo, sólo para usuarios autenticados.
select 1 / (case when
  not has_function_privilege('authenticated', 'public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.get_bank_reconciliation_candidates_v2(uuid,date,date)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_bank_reconciliation_candidates_v2(uuid,date,date)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)', 'EXECUTE')
then 1 else 0 end) as afirma_privilegios;
