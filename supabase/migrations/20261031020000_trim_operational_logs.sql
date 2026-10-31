-- Two operational logs were 300 MB of the 554 MB database (2026-10-31).
--
-- NOT APPLIED YET: it empties two log tables, and the agent's safety
-- classifier stopped it as a mass delete on 2026-10-31 while the owner was
-- away. Tested on local. It is applied with
-- `scripts/db/deploy_migration.sh` and its verification file once the owner
-- says yes.
--
-- `net._http_response` (pg_net's answers to the cron calls of edge
-- functions) held 724 rows of 34 kB in a 205 MB file: pg_net deletes each
-- answer after six hours, but nothing hands the emptied pages back, and the
-- role that owns the table is not ours, so VACUUM FULL is not available.
-- Nothing in the app reads those answers. TRUNCATE gives the file back.
--
-- `cron.job_run_details` kept every run since May: 464,810 rows, 96 MB, for
-- jobs that run every minute. Postgres' own log keeps the same starts and
-- ends for a week. The last seven days are kept, the file is rebuilt, and a
-- daily job keeps the history at a week from now on.
--
-- Without the two files the database is ~250 MB, under the 500 MB of the
-- free plan; with them it was over it.

begin;

truncate net._http_response;

create temporary table recent_cron_runs on commit drop as
  select *
    from cron.job_run_details
   where start_time > now() - interval '7 days';

truncate cron.job_run_details;

insert into cron.job_run_details
select * from recent_cron_runs;

do $$
declare
  v_job record;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    raise notice 'pg_cron unavailable; cron history retention was not installed';
    return;
  end if;
  for v_job in
    select jobid from cron.job where jobname = 'vinabike_cron_history_retention'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
  perform cron.schedule(
    'vinabike_cron_history_retention',
    '41 4 * * *',
    $job$delete from cron.job_run_details where end_time < now() - interval '7 days'$job$
  );
end
$$;

commit;
