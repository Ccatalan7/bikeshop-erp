-- Falla si un vínculo elegido a mano puede volver a cargarle a una operación
-- más de $1.000 de lo que es, o si se perdieron las reglas anteriores.
select 1 / (case when
  pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%match_kind'' in (''direct'', ''manual'')%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_remainder_invalid%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%v_description, 0, v_row.amount%'
then 1 else 0 end) as afirma_vinculo_manual_acotado;

select 1 / (case when not exists (
  select 1 from public.bank_reconciliation_allocations allocation
   where allocation.match_kind = 'manual'
     and abs(allocation.bank_amount - allocation.target_amount) > 1000
) then 1 else 0 end) as afirma_ningun_vinculo_manual_inflado;
