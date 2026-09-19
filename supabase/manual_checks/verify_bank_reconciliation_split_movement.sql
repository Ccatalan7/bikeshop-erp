-- Falla si la conciliación no puede dividir un movimiento en varias cuentas,
-- si perdió las reglas de la ronda anterior o si el catálogo no aprende las
-- divisiones.
select
  pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_split_total_mismatch%' as divide_movimientos,
  pg_get_constraintdef((
    select oid from pg_constraint
     where conname = 'bank_reconciliation_row_decisions_action_kind_check'
  )) like '%split%' as decision_admite_division;

select 1 / (case when
  pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_split_total_mismatch%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_split_expense_needs_debit%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_row_already_decided%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_row_settled_elsewhere%'
  and pg_get_constraintdef((
    select oid from pg_constraint
     where conname = 'bank_reconciliation_row_decisions_action_kind_check'
  )) like '%split%'
then 1 else 0 end) as afirma_division;

select 1 / (case when
  pg_get_functiondef('public.get_bank_reconciliation_candidates_v2(uuid,date,date)'::regprocedure)
    like '%''parts'', decision.action_snapshot->''parts''%'
  and pg_get_functiondef('public.get_bank_reconciliation_candidates_v2(uuid,date,date)'::regprocedure)
    like '%''reconciled_rows'', v_reconciled_rows%'
then 1 else 0 end) as afirma_catalogo_aprende;

select 1 / (case when
  not has_function_privilege('authenticated', 'public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.get_bank_reconciliation_candidates_v2(uuid,date,date)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_bank_reconciliation_candidates_v2(uuid,date,date)', 'EXECUTE')
then 1 else 0 end) as afirma_privilegios;
