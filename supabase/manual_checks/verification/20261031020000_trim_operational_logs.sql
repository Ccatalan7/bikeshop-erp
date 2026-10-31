-- Read-back of 20261031020000_trim_operational_logs.sql (plain SQL, no
-- transaction control: it runs through the read-only hosted wrapper).

select
  pg_size_pretty(pg_total_relation_size('net._http_response'::regclass))
    as pg_net_answers,
  pg_size_pretty(pg_total_relation_size('cron.job_run_details'::regclass))
    as cron_history,
  (select min(start_time) from cron.job_run_details) as oldest_run,
  pg_size_pretty(pg_database_size(current_database())) as database;

-- pg_net's answers no longer fill a file of hundreds of MB.
select 1 / (
  case
    when pg_total_relation_size('net._http_response'::regclass)
         < 50 * 1024 * 1024 then 1
    else 0
  end
) as afirma_respuestas_pg_net_chicas;

-- The cron history keeps about a week, not every run since May.
select 1 / (
  case
    when pg_total_relation_size('cron.job_run_details'::regclass)
         < 40 * 1024 * 1024
     and not exists (
       select 1 from cron.job_run_details
        where start_time < now() - interval '8 days'
     ) then 1
    else 0
  end
) as afirma_historial_de_una_semana;

-- And a daily job keeps it that way.
select 1 / (
  case
    when exists (
      select 1 from cron.job
       where jobname = 'vinabike_cron_history_retention'
         and active
    ) then 1
    else 0
  end
) as afirma_retencion_diaria;
