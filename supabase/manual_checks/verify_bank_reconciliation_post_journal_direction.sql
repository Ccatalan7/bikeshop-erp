-- Falla si una clasificación de un cargo vuelve a registrar el banco al revés,
-- o si queda algún asiento de conciliación con el banco al Debe para plata que
-- salió.
select 1 / (case when
  pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%v_description, v_row.amount, 0%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%v_description, 0, v_row.amount%'
  and pg_get_functiondef('public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)'::regprocedure)
    like '%bank_reconciliation_remainder_invalid%'
then 1 else 0 end) as afirma_sentido_del_asiento;

select 1 / (case when not exists (
  select 1
    from public.bank_reconciliation_row_decisions decision
    join public.bank_statement_rows statement_row
      on statement_row.id = decision.row_id
     and statement_row.tenant_id = decision.tenant_id
    join public.bank_statement_imports statement_import
      on statement_import.id = decision.import_id
     and statement_import.tenant_id = decision.tenant_id
    join public.journal_lines bank_line
      on bank_line.entry_id = decision.generated_target_id
     and bank_line.tenant_id = decision.tenant_id
     and bank_line.account_id = statement_import.erp_account_id
   where decision.action_kind in ('post_journal', 'split', 'associate_existing')
     and decision.generated_target_kind = 'journal_entry'
     and (
       (statement_row.direction = 'debit' and bank_line.debit_amount > 0)
       or (statement_row.direction = 'credit' and bank_line.credit_amount > 0)
     )
) then 1 else 0 end) as afirma_ningun_banco_al_reves;
