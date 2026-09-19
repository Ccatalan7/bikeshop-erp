-- Falla si la conciliación no quedó capaz de pagar sueldos de Nómina: v3
-- ausente o abierta a anon, sin delegar el pago en los comandos de Nómina, o
-- con el catálogo que perdía las semanas confirmadas sin pagar.
select
  to_regprocedure('public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)') is not null as v3_presente,
  has_function_privilege('authenticated', 'public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)', 'EXECUTE') as contador_la_llama,
  has_function_privilege('anon', 'public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)', 'EXECUTE') as anon_la_llama;

select 1 / (case when
  to_regprocedure('public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)') is not null
  and has_function_privilege('authenticated', 'public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.get_bank_reconciliation_candidates_v2(uuid,date,date)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_bank_reconciliation_candidates_v2(uuid,date,date)', 'EXECUTE')
then 1 else 0 end) as afirma_v3_y_privilegios;

-- El sueldo se paga con los comandos de Nómina, no con un insert propio.
select 1 / (case when
  pg_get_functiondef('public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)'::regprocedure)
    like '%public.pay_payroll_voucher_v2(%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)'::regprocedure)
    like '%public.confirm_payroll_voucher_v2(%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)'::regprocedure)
    like '%public.apply_bank_reconciliation_actions_v2(%'
then 1 else 0 end) as afirma_delega_en_nomina;

-- Lo adeudado es el saldo de la línea, no "una línea sin gasto".
select 1 / (case when
  pg_get_functiondef('public.get_bank_reconciliation_candidates_v2(uuid,date,date)'::regprocedure)
    like '%''reconciliation_version'', owed.reconciliation_version%'
  and pg_get_functiondef('public.get_bank_reconciliation_candidates_v2(uuid,date,date)'::regprocedure)
    not like '%line.expense_id is null%'
then 1 else 0 end) as afirma_catalogo_por_saldo;
