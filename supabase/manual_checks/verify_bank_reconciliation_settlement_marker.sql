-- Falla si un vínculo manual puede decirse liquidación de tarjeta por su
-- proveedor, si el adaptador deja de marcar las suyas, o si el asiento de un
-- gasto heredado vuelve a poder vincularse aparte del gasto.
select 1 / (case when
  pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%coalesce(v_allocation->>''settlement'', ''false'') = ''true''%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%''payment_terminal_settlements'', ''expenses''%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_target_is_payment_journal%'
then 1 else 0 end) as afirma_marca_en_el_kernel;

select 1 / (case when
  pg_get_functiondef('public.apply_bank_reconciliation_actions_v2(uuid,bigint,text,jsonb)'::regprocedure)
    like '%jsonb_build_object(''settlement'', true)%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_v2(uuid,bigint,text,jsonb)'::regprocedure)
    like '%allocation.value - ''settlement''%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_v2(uuid,bigint,text,jsonb)'::regprocedure)
    like '%processor_settlement_profile_mismatch%'
then 1 else 0 end) as afirma_marca_en_el_adaptador;
