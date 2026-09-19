-- Falla si las reglas de la cartola por empresa no existen o si se pueden
-- escribir sin la función que valida la cuenta.
select 1 / (case when
  to_regclass('public.bank_reconciliation_rules') is not null
  and pg_get_functiondef('public.save_bank_reconciliation_rule_v1(text,text,text,uuid,text)'::regprocedure)
    like '%bank_reconciliation_rule_account_invalid%'
  and has_function_privilege('authenticated', 'public.save_bank_reconciliation_rule_v1(text,text,text,uuid,text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.delete_bank_reconciliation_rule_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.save_bank_reconciliation_rule_v1(text,text,text,uuid,text)', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.bank_reconciliation_rules', 'INSERT')
  and not has_table_privilege('authenticated', 'public.bank_reconciliation_rules', 'UPDATE')
  and has_table_privilege('authenticated', 'public.bank_reconciliation_rules', 'SELECT')
then 1 else 0 end) as afirma_reglas_de_cartola;
