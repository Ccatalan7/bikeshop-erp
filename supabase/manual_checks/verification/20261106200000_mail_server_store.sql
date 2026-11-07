-- Read-back of 20261106200000 (Correo que trabaja, etapas 1 y 2). Fails before
-- the migration (the tables and functions do not exist) and passes after.
-- Never prints cron.job commands nor mail content: counts and booleans only.

select 1 / (case when
  to_regclass('public.mail_mailboxes') is not null
  and to_regclass('public.mail_messages') is not null
  and to_regclass('public.mail_message_links') is not null
  and to_regclass('public.mail_senders') is not null
  and to_regclass('public.mail_sync_runtime') is not null
  and to_regclass('public.mail_sync_runs') is not null
then 1 else 0 end) as existen_las_tablas;

-- RLS en las seis; el personal sólo lee las cuatro de correo; el despacho y
-- sus corridas son del servidor; las políticas piden personal, no tenant.
select 1 / (case when
  (select count(*)
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('mail_mailboxes', 'mail_messages', 'mail_message_links',
                        'mail_senders', 'mail_sync_runtime', 'mail_sync_runs')
      and c.relrowsecurity) = 6
  and has_table_privilege('authenticated', 'public.mail_messages', 'SELECT')
  and not has_table_privilege('authenticated', 'public.mail_messages', 'INSERT')
  and not has_table_privilege('authenticated', 'public.mail_messages', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.mail_message_links', 'INSERT')
  and not has_table_privilege('anon', 'public.mail_messages', 'SELECT')
  and not has_table_privilege('anon', 'public.mail_senders', 'SELECT')
  and not has_table_privilege('authenticated', 'public.mail_sync_runtime', 'SELECT')
  and not has_table_privilege('authenticated', 'public.mail_sync_runs', 'SELECT')
  and not has_table_privilege('anon', 'public.mail_sync_runs', 'SELECT')
  and (select count(*) from pg_policies
        where schemaname = 'public'
          and tablename in ('mail_mailboxes', 'mail_messages', 'mail_message_links', 'mail_senders')
          and qual like '%messaging_is_staff_in_tenant%') = 4
then 1 else 0 end) as solo_el_personal_lee;

select 1 / (case when
  has_function_privilege('authenticated', 'public.mail_inbox_v1(text, text, text, integer, timestamptz)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mail_inbox_v1(text, text, text, integer, timestamptz)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.mail_message_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.mail_counts_v1()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.mail_record_messages_v1(text, uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.mail_mark_v1(uuid[], text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.mail_link_v1(uuid, text, uuid, boolean)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.mail_set_kind_v1(uuid, text, boolean)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.mail_upsert_messages_v1(uuid, jsonb)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.mail_prepare_tenant_v1(uuid)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.claim_mail_sync_run_v1(uuid, text)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.finish_mail_sync_run_v1(uuid, jsonb, text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.mail_upsert_messages_v1(uuid, jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.mail_prepare_tenant_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.claim_mail_sync_run_v1(uuid, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.claim_mail_sync_run_v1(uuid, text)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.dispatch_mail_sync_v1(text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.dispatch_mail_sync_v1(text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.mail_message_state_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.mail_classify_message_internal(uuid)', 'EXECUTE')
then 1 else 0 end) as permisos_de_las_funciones;

-- Clasifica al llegar y al cambiar; lee los números de un aviso real de flete.
select 1 / (case when
  (select count(*) from pg_trigger
    where tgrelid = 'public.mail_messages'::regclass
      and tgname in ('trg_mail_messages_classify', 'trg_mail_messages_reclassify')
      and not tgisinternal) = 2
  and public.mail_extract_facts_internal(
        'Factura Electrónica 13712582',
        'Orden de flete 280283741. Monto: $45.990',
        'infodte@starken.cl'
      ) @> '{"folio": "13712582", "freight_order": "280283741", "amount": 45990}'::jsonb
then 1 else 0 end) as clasifica_al_llegar;

-- El despacho queda programado y apagado hasta que la función exista.
select 1 / (case when
  (select count(*) from cron.job where jobname = 'vinabike_mail_sync') = 1
  and not exists (select 1 from public.mail_sync_runtime where enabled)
then 1 else 0 end) as despacho_programado_y_apagado;
