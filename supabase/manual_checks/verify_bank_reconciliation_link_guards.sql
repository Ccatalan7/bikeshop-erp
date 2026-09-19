-- Falla si la conciliación vuelve a rechazar una liquidación de tarjeta por
-- su comisión, si puede vincular el asiento de un pago aparte del pago, o si
-- perdió las reglas de hoy.
select 1 / (case when
  pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_target_is_payment_journal%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%v_allocation->>''provider'' <> ''none''%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_remainder_invalid%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%v_description, 0, v_row.amount%'
then 1 else 0 end) as afirma_guardias_del_vinculo;

select 1 / (case when not exists (
  select 1 from public.bank_reconciliation_allocations allocation
   where (allocation.match_kind = 'manual' and allocation.provider = 'none'
          and abs(allocation.bank_amount - allocation.target_amount) > 1000)
      or (allocation.provider <> 'none'
          and allocation.match_kind in ('manual', 'transbank_estimate', 'processor_estimate')
          and allocation.bank_amount > allocation.target_amount)
) and not exists (
  select 1 from public.bank_reconciliation_allocations allocation
    join public.journal_entries entry
      on entry.id = allocation.target_id and entry.tenant_id = allocation.tenant_id
   where allocation.target_kind = 'journal_entry'
     and coalesce(entry.source_module, '') in (
       'sales_payments', 'purchase_payments', 'expense_payments',
       'payment_terminal_settlements'
     )
) then 1 else 0 end) as afirma_vinculos_existentes_validos;
