-- Falla si el adaptador vuelve a mandarle al kernel una operación ya
-- aplicada —lo que rompe el reintento de las liquidaciones anteriores a la
-- marca— o si deja de tomar el mismo bloqueo antes de leerla.
select 1 / (case when
  pg_get_functiondef('public.apply_bank_reconciliation_actions_v2(uuid,bigint,text,jsonb)'::regprocedure)
    like '%'':bank-reconciliation''%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_v2(uuid,bigint,text,jsonb)'::regprocedure)
    like '%operation.receipt%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_v2(uuid,bigint,text,jsonb)'::regprocedure)
    like '%(v_existing_receipt - ''replayed'')%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_v2(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_idempotency_conflict%'
then 1 else 0 end) as afirma_reintento_en_el_adaptador;
