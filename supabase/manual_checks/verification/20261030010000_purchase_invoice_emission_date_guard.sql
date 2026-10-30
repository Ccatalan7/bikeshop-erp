-- Read-back of 20261030010000. Fails before the migration and passes after.
-- Runs the rule with the shop's tenant: 22-08-2014 (the SII resolution date
-- the reader took on 2026-10-29) is refused and today is accepted.

select
  to_regprocedure('public.purchase_document_date_problem(uuid,timestamptz)') as regla,
  (select count(*) from pg_trigger
    where tgrelid = 'public.purchase_invoices'::regclass
      and tgname = 'trg_guard_purchase_invoice_emission_date'
      and not tgisinternal) as guardia;

select 1 / (case when
  to_regprocedure('public.purchase_document_date_problem(uuid,timestamptz)') is not null
then 1 else 0 end) as afirma_regla_existe;

select 1 / (case when exists (
  select 1
    from pg_trigger trigger_row
   where trigger_row.tgrelid = 'public.purchase_invoices'::regclass
     and trigger_row.tgname = 'trg_guard_purchase_invoice_emission_date'
     and not trigger_row.tgisinternal
     and trigger_row.tgenabled = 'O'
     and pg_get_triggerdef(trigger_row.oid) like
       '%BEFORE INSERT OR UPDATE OF date, supplier_invoice_date ON public.purchase_invoices%'
     and pg_get_triggerdef(trigger_row.oid) like
       '%supplier_foundation_invoice_rehydrate_is_active%'
) then 1 else 0 end) as afirma_guardia_activa;

select 1 / (case when
  public.purchase_document_date_problem(
    '5443b130-cc28-45af-a420-cd500b288890',
    timestamptz '2014-08-22 04:00:00+00'
  ) like '%resolución del SII%'
  and public.purchase_document_date_problem(
    '5443b130-cc28-45af-a420-cd500b288890',
    statement_timestamp()
  ) is null
  and public.purchase_document_date_problem(
    '5443b130-cc28-45af-a420-cd500b288890',
    statement_timestamp() + interval '3 days'
  ) like '%posterior a hoy%'
then 1 else 0 end) as afirma_regla_responde;

select 1 / (case when
  pg_get_functiondef('public.handle_purchase_invoice_change'::regproc)
    like '%elsif OLD.date IS DISTINCT FROM NEW.date then%'
  and pg_get_functiondef('public.handle_purchase_invoice_change'::regproc)
    like '%set entry_date = v_new_day%'
then 1 else 0 end) as afirma_asiento_sigue_la_fecha;

select 1 / (case when not exists (
  select 1
    from (values ('anon'), ('authenticated'), ('service_role')) as role_row(name)
   where has_function_privilege(role_row.name,
           'public.purchase_document_date_problem(uuid,timestamptz)', 'EXECUTE')
      or has_function_privilege(role_row.name,
           'public.guard_purchase_invoice_emission_date()', 'EXECUTE')
) then 1 else 0 end) as afirma_sin_ejecucion_directa;

select 1 / (case when (
  select count(*)
    from public.purchase_invoices invoice
    join public.journal_entries entry
      on entry.tenant_id = invoice.tenant_id
     and entry.source_module = 'purchase_invoices'
     and entry.source_document_id = invoice.id
   where invoice.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
     and invoice.invoice_number in ('142770', '143739')
     and entry.entry_date = (invoice.date at time zone 'America/Santiago')::date
     and entry.entry_date >= date '2026-07-01'
) = 2 then 1 else 0 end) as afirma_teknobike_en_su_fecha;
