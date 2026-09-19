-- Falla si la conciliación no puede vincular operaciones y registrar lo que
-- dejan del movimiento, o si perdió las reglas de las rondas anteriores.
select 1 / (case when
  pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_remainder_invalid%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%''action'', ''associate_remainder''%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_row_not_fully_allocated%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_split_total_mismatch%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_row_already_decided%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_row_settled_elsewhere%'
then 1 else 0 end) as afirma_vinculo_con_resto;

select 1 / (case when
  not has_function_privilege('authenticated', 'public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)', 'EXECUTE')
then 1 else 0 end) as afirma_privilegios;
