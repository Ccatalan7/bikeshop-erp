-- Read-back of 20261106210000. Fails before the migration (the switch does not
-- exist and the directory still seeds a fixed domain) and passes after.

select 1 / (case when
  to_regprocedure('public.mail_set_mailbox_active_v1(uuid, boolean)') is not null
  and has_function_privilege('authenticated', 'public.mail_set_mailbox_active_v1(uuid, boolean)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mail_set_mailbox_active_v1(uuid, boolean)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.mail_refresh_senders_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.mail_refresh_senders_internal(uuid)', 'EXECUTE')
then 1 else 0 end) as solo_un_administrador_enciende;

select 1 / (case when
  (select column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'mail_mailboxes' and column_name = 'is_active') = 'false'
  and pg_get_functiondef('public.mail_refresh_senders_internal(uuid)'::regprocedure) not like '%vinabike.cl%'
  and pg_get_functiondef('public.mail_refresh_senders_internal(uuid)'::regprocedure) like '%mb.is_active%'
then 1 else 0 end) as nacen_apagadas_y_lo_nuestro_sale_de_ellas;
