-- Read-back of 20261030031500. Fails before the migration and passes after.

select
  to_regprocedure('public.delete_purchase_invoice_journal_entry(uuid,text)') as borrado_por_taller,
  (select count(*)
     from regexp_matches(
       pg_get_functiondef('public.handle_purchase_invoice_change()'::regprocedure),
       'delete_purchase_invoice_journal_entry\(OLD\.tenant_id, OLD\.invoice_number\)',
       'g')) as llamadas_con_taller;

select 1 / (case when
  to_regprocedure('public.delete_purchase_invoice_journal_entry(uuid,text)') is not null
then 1 else 0 end) as afirma_borrado_por_taller_existe;

select 1 / (case when
  (select count(*)
     from regexp_matches(
       pg_get_functiondef('public.handle_purchase_invoice_change()'::regprocedure),
       'delete_purchase_invoice_journal_entry\(OLD\.tenant_id, OLD\.invoice_number\)',
       'g')) = 3
  and pg_get_functiondef('public.handle_purchase_invoice_change()'::regprocedure)
    not like '%delete_purchase_invoice_journal_entry(OLD.invoice_number)%'
  and pg_get_functiondef('public.handle_purchase_invoice_change()'::regprocedure)
    like '%set entry_date = v_new_day%'
then 1 else 0 end) as afirma_trigger_usa_el_taller;

select 1 / (case when
  pg_get_functiondef(
    'public.create_purchase_invoice_journal_entry(public.purchase_invoices)'::regprocedure)
    like '%and tenant_id = p_invoice.tenant_id%'
then 1 else 0 end) as afirma_alta_mira_su_taller;

select 1 / (case when
  pg_get_functiondef('public.delete_purchase_invoice_journal_entry(text)'::regprocedure)
    like '%no distingue el taller%'
  and pg_get_functiondef('public.delete_purchase_invoice_journal_entry(text)'::regprocedure)
    not like '%delete from%'
then 1 else 0 end) as afirma_borrado_sin_taller_se_niega;

select 1 / (case when not exists (
  select 1
    from (values ('anon'), ('authenticated'), ('service_role')) as role_row(name)
   where has_function_privilege(role_row.name,
           'public.delete_purchase_invoice_journal_entry(uuid,text)', 'EXECUTE')
) then 1 else 0 end) as afirma_borrado_por_taller_privado;
