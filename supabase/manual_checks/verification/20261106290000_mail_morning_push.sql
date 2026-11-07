-- Read-back of 20261106290000. Fails before the migration (no shared summary,
-- no dispatcher, no schedule) and passes after. The cron command is not
-- printed: only its name and schedule are checked.

select 1 / (case when
  to_regprocedure('public.mail_morning_summary_internal(uuid)') is not null
  and to_regprocedure('public.dispatch_mail_morning_summary_v1()') is not null
  and to_regclass('public.mail_morning_push_log') is not null
  and has_function_privilege('service_role', 'public.mail_morning_summary_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.mail_morning_summary_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.dispatch_mail_morning_summary_v1()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.mail_morning_summary_v1()', 'EXECUTE')
  and pg_get_functiondef('public.mail_morning_summary_v1()'::regprocedure) like '%mail_morning_summary_internal%'
  and exists (select 1 from cron.job where jobname = 'vinabike_mail_morning_summary' and schedule = '0 11,12 * * *')
then 1 else 0 end) as resumen_en_el_celular;
