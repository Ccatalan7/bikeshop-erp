-- Read-back of 20261106280000. Fails before the migration (no supplier-name
-- domain rule, no «since» in the summary) and passes after.

select 1 / (case when
  pg_get_functiondef('public.mail_resolve_sender_internal(uuid, text)'::regprocedure) like '%length(k.key) >= 6%'
  and pg_get_functiondef('public.mail_refresh_senders_internal(uuid)'::regprocedure) like '%veryfi.com%'
  and pg_get_functiondef('public.mail_morning_summary_v1()'::regprocedure) like '%follow_ups_since%'
  and has_function_privilege('authenticated', 'public.mail_morning_summary_v1()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mail_morning_summary_v1()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.mail_resolve_sender_internal(uuid, text)', 'EXECUTE')
then 1 else 0 end) as afinado_con_el_correo_real;
