-- Read-back of 20261102063700. Fails before the migration and passes after.

select
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'customer_quote_messages' and c.relrowsecurity) as tabla,
  (select count(*) from pg_trigger
    where tgrelid = 'public.customer_quote_events'::regclass
      and tgname = 'trg_customer_quote_events_enqueue_messages' and not tgisinternal) as disparador;

select 1 / (case when exists (
  select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'customer_quote_messages' and c.relrowsecurity
) then 1 else 0 end) as afirma_tabla_con_rls;

select 1 / (case when exists (
  select 1 from pg_trigger
   where tgrelid = 'public.customer_quote_events'::regclass
     and tgname = 'trg_customer_quote_events_enqueue_messages'
     and not tgisinternal and tgenabled = 'O'
) then 1 else 0 end) as afirma_disparador;

select 1 / (case when
  has_function_privilege('service_role', 'public.claim_customer_quote_messages_v1(uuid,text,integer)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.complete_customer_quote_message_v1(uuid,text,text,text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.claim_customer_quote_messages_v1(uuid,text,integer)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.claim_customer_quote_messages_v1(uuid,text,integer)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.customer_quote_issue_link_v1(uuid,uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.customer_quote_mark_message_sent_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_issue_link_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.customer_quote_email_payload_internal(uuid)', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.customer_quote_messages', 'INSERT')
then 1 else 0 end) as afirma_permisos;

-- The detail the ERP reads carries the messages.
select 1 / (case when
  pg_get_functiondef('public.customer_quote_detail_v1(uuid,uuid)'::regprocedure) like '%''messages''%'
then 1 else 0 end) as afirma_detalle_con_mensajes;

-- Only the job's name and schedule are read.
select 1 / (case when exists (
  select 1 from cron.job
   where jobname = 'vinabike_remind_customer_quote_offers' and schedule = '13 * * * *'
) then 1 else 0 end) as afirma_recordatorio_programado;
