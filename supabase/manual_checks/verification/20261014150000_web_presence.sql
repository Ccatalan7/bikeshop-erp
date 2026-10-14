-- Read-back de 20261014150000: presencia en internet, sólo lectura para la app
-- y la recolección programada sin el secreto en el texto del job.

select 1 / case
  when (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relrowsecurity
           and c.relname in ('web_presence_settings', 'web_presence_search_daily',
             'web_presence_search_terms', 'web_presence_urls', 'web_presence_index_daily',
             'web_presence_traffic_daily', 'web_presence_events_daily', 'web_presence_notes',
             'web_presence_runs')) = 9
   and not has_table_privilege('authenticated', 'public.web_presence_search_daily', 'insert')
   and not has_table_privilege('anon', 'public.web_presence_search_daily', 'select')
   and has_table_privilege('authenticated', 'public.web_presence_search_daily', 'select')
  then 1 else 0
end as assert_tables_read_only_with_rls;

select 1 / case
  when has_function_privilege('authenticated', 'public.web_presence_terms_v1(uuid,text,date,date,integer)', 'execute')
   and not has_function_privilege('anon', 'public.web_presence_terms_v1(uuid,text,date,date,integer)', 'execute')
   and has_function_privilege('authenticated', 'public.web_presence_save_settings_v1(uuid,text,boolean)', 'execute')
   and not has_function_privilege('authenticated', 'public.invoke_web_presence_collect(text)', 'execute')
   and not has_function_privilege('anon', 'public.invoke_web_presence_collect(text)', 'execute')
  then 1 else 0
end as assert_function_grants;

select 1 / case
  when (select count(*) from cron.job
         where jobname in ('web-presence-collect-daily', 'web-presence-inspect') and active) = 2
   and (select count(*) from cron.job
         where jobname in ('web-presence-collect-daily', 'web-presence-inspect')
           and position('invoke_web_presence_collect' in command) > 0
           and position('secret' in command) = 0) = 2
  then 1 else 0
end as assert_jobs_scheduled_without_secret;

select jobname, schedule, active
  from cron.job
 where jobname in ('web-presence-collect-daily', 'web-presence-inspect')
 order by jobname;
