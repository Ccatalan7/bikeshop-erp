-- CPU pressure profile for a hosted Supabase project.
--
-- Run read-only through the guarded wrapper:
--   just db-cpu production
--   bash scripts/db/query.sh production --file supabase/manual_checks/diagnostics/cpu_pressure_profile.sql
--
-- Answers "where does the CPU go" with measured data instead of code reading.
-- Every section is a separate statement so a permission error in a trailing
-- section (cron, net, realtime schemas) does not hide the earlier answers.
-- Nothing here mutates state; the wrapper still wraps it in BEGIN READ ONLY.
--
-- Interpretation (2026-09-15):
--   §1  avg_active_backends ≈ CPU cores busy on average since stats_reset. A
--       Micro/Nano instance shares 2 vCPU; sustained ≥ 1.6 is the 80% alert.
--   §2  Which role burns the time: authenticator = PostgREST/app traffic,
--       postgres = pg_cron jobs and dashboard, supabase_realtime_admin =
--       Realtime WAL polling and RLS checks per subscriber, supabase_auth_admin
--       = GoTrue, supabase_storage_admin = Storage.
--   §3  The individual statements. total_pct is the share of all execution
--       time; a single statement above ~20% is the leak.
--   §4  Chatty statements: cheap but called thousands of times per hour.
--   §6  A realtime slot with lag in the hundreds of MB means WAL decoding is
--       falling behind and burning CPU continuously.
--   §7  seq_scan with n_live_tup in the tens of thousands is a missing index.
--   §12 pg_cron: three workers fire every minute; job_run_details grows
--       unbounded unless purged.

-- §1 Database-wide activity since the last statistics reset.
select
  '1_database_activity' as section,
  datname,
  stats_reset,
  round((extract(epoch from (now() - stats_reset)) / 3600.0)::numeric, 1) as hours_since_reset,
  round(((active_time / 1000.0) / greatest(extract(epoch from (now() - stats_reset)), 1))::numeric, 2)
    as avg_active_backends,
  round((active_time / 1000.0 / 3600.0)::numeric, 1) as active_hours,
  xact_commit,
  xact_rollback,
  round((100.0 * blks_hit / greatest(blks_hit + blks_read, 1))::numeric, 2) as cache_hit_pct,
  temp_files,
  pg_size_pretty(temp_bytes) as temp_bytes,
  deadlocks,
  sessions_abandoned,
  sessions_killed
from pg_stat_database
where datname = current_database();

-- §2 Execution time share by role (pg_stat_statements).
select
  '2_time_by_role' as section,
  coalesce(r.rolname, s.userid::text) as role_name,
  count(*) as distinct_statements,
  sum(s.calls) as calls,
  round((sum(s.total_exec_time) / 1000.0)::numeric, 1) as total_exec_s,
  round((100.0 * sum(s.total_exec_time) / greatest(sum(sum(s.total_exec_time)) over (), 1))::numeric, 1) as pct_of_all,
  round((sum(s.total_exec_time) / greatest(sum(s.calls), 1))::numeric, 3) as mean_ms
from pg_stat_statements s
left join pg_roles r on r.oid = s.userid
where s.dbid = (select oid from pg_database where datname = current_database())
group by coalesce(r.rolname, s.userid::text)
order by total_exec_s desc;

-- §3 Top statements by total execution time.
select
  '3_top_by_total_time' as section,
  coalesce(r.rolname, s.userid::text) as role_name,
  s.calls,
  round((s.total_exec_time / 1000.0)::numeric, 1) as total_exec_s,
  round((100.0 * s.total_exec_time / greatest(sum(s.total_exec_time) over (), 1))::numeric, 1) as total_pct,
  round(s.mean_exec_time::numeric, 2) as mean_ms,
  round(s.max_exec_time::numeric, 1) as max_ms,
  s.rows,
  s.shared_blks_hit,
  s.shared_blks_read,
  s.temp_blks_written,
  left(regexp_replace(s.query, '\s+', ' ', 'g'), 220) as query
from pg_stat_statements s
left join pg_roles r on r.oid = s.userid
where s.dbid = (select oid from pg_database where datname = current_database())
order by s.total_exec_time desc
limit 25;

-- §4 Chattiest statements (calls per hour since reset).
select
  '4_top_by_calls' as section,
  coalesce(r.rolname, s.userid::text) as role_name,
  s.calls,
  round(
    (s.calls / greatest(extract(epoch from (now() - i.stats_reset)) / 3600.0, 0.01))::numeric,
    0
  ) as calls_per_hour,
  round((s.total_exec_time / 1000.0)::numeric, 1) as total_exec_s,
  round(s.mean_exec_time::numeric, 3) as mean_ms,
  left(regexp_replace(s.query, '\s+', ' ', 'g'), 220) as query
from pg_stat_statements s
cross join pg_stat_statements_info i
left join pg_roles r on r.oid = s.userid
where s.dbid = (select oid from pg_database where datname = current_database())
order by s.calls desc
limit 20;

-- §5 What is running right now.
select
  '5_activity_now' as section,
  usename,
  left(coalesce(application_name, ''), 40) as application_name,
  state,
  wait_event_type,
  backend_type,
  count(*) as backends,
  max(now() - query_start) as oldest_query_age
from pg_stat_activity
where datname = current_database()
group by usename, left(coalesce(application_name, ''), 40), state, wait_event_type, backend_type
order by backends desc, oldest_query_age desc nulls last;

select
  '5b_long_running_now' as section,
  pid,
  usename,
  left(coalesce(application_name, ''), 40) as application_name,
  state,
  wait_event_type,
  now() - query_start as query_age,
  now() - xact_start as xact_age,
  left(regexp_replace(query, '\s+', ' ', 'g'), 120) as query
from pg_stat_activity
where datname = current_database()
  and state <> 'idle'
  and query_start < now() - interval '5 seconds'
order by query_start
limit 20;

-- §6 Logical replication slots (Realtime, replication) and their WAL lag.
select
  '6_replication_slots' as section,
  slot_name,
  slot_type,
  plugin,
  active,
  active_pid,
  wal_status,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) as confirmed_flush_lag,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as restart_lag
from pg_replication_slots
order by pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) desc nulls last;

-- §7 Sequential-scan pressure and vacuum health on user tables.
select
  '7_seq_scan_pressure' as section,
  schemaname || '.' || relname as relation,
  seq_scan,
  seq_tup_read,
  idx_scan,
  n_live_tup,
  n_dead_tup,
  round(100.0 * n_dead_tup / greatest(n_live_tup + n_dead_tup, 1), 1) as dead_pct,
  n_tup_ins + n_tup_upd + n_tup_del as writes_since_reset,
  last_autovacuum,
  last_autoanalyze
from pg_stat_user_tables
where schemaname not in ('pg_catalog', 'information_schema')
order by seq_tup_read desc
limit 25;

-- §8 Largest relations across every schema (heap + indexes + toast).
select
  '8_largest_relations' as section,
  n.nspname || '.' || c.relname as relation,
  c.relkind,
  pg_size_pretty(pg_total_relation_size(c.oid)) as total_size,
  pg_size_pretty(pg_relation_size(c.oid)) as heap_size,
  c.reltuples::bigint as est_rows
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('r', 'm')
  and n.nspname not in ('pg_catalog', 'information_schema', 'pg_toast')
order by pg_total_relation_size(c.oid) desc
limit 20;

-- §9 Dead-tuple bloat candidates and vacuums in progress.
select
  '9_bloat_candidates' as section,
  schemaname || '.' || relname as relation,
  n_live_tup,
  n_dead_tup,
  round(100.0 * n_dead_tup / greatest(n_live_tup + n_dead_tup, 1), 1) as dead_pct,
  autovacuum_count,
  autoanalyze_count,
  last_autovacuum
from pg_stat_user_tables
where n_dead_tup > 5000
   or (n_dead_tup > 500 and n_dead_tup > n_live_tup / 5)
order by n_dead_tup desc
limit 20;

select
  '9b_vacuum_in_progress' as section,
  p.pid,
  p.relid::regclass as relation,
  p.phase,
  p.heap_blks_total,
  p.heap_blks_scanned,
  p.heap_blks_vacuumed,
  now() - a.xact_start as running_for
from pg_stat_progress_vacuum p
left join pg_stat_activity a on a.pid = p.pid;

-- §10 Scheduled in-database backups (full tenant snapshot into one JSONB row).
select
  '10_backup_schedules' as section,
  tenant_id,
  enabled,
  frequency,
  time_of_day,
  day_of_week,
  day_of_month,
  keep_last_n_backups,
  auto_delete_old,
  last_run_at,
  next_run_at
from public.backup_schedules
order by enabled desc, next_run_at nulls last;

select
  '10b_recent_backups' as section,
  id,
  tenant_id,
  backup_type,
  status,
  created_at,
  pg_size_pretty(coalesce(backup_size_bytes, 0)) as backup_size,
  left(coalesce(error_message, ''), 120) as error_message
from public.database_backups
order by created_at desc
limit 15;

select
  '10c_backup_table_footprint' as section,
  count(*) as backups_stored,
  pg_size_pretty(coalesce(sum(backup_size_bytes), 0)) as declared_payload,
  pg_size_pretty(pg_total_relation_size('public.database_backups')) as relation_total_size
from public.database_backups;

-- §11 Every-minute Edge workers driven from pg_cron: enabled state and errors.
select
  '11_transactional_email_worker' as section,
  enabled,
  tenant_id,
  delivery_mode,
  batch_size,
  last_request_id,
  last_requested_at,
  left(coalesce(last_error, ''), 160) as last_error
from public.transactional_email_worker_runtime
where singleton;

select
  '11b_mercadopago_preference_worker' as section,
  enabled,
  batch_size,
  last_request_id,
  last_requested_at,
  updated_at,
  left(coalesce(last_error, ''), 160) as last_error
from public.mercadopago_preference_worker_runtime
where singleton;

select
  '11c_storefront_publication_dispatcher' as section,
  to_regclass('public.storefront_publication_targets') is not null as targets_table_exists,
  exists (select 1 from cron.job where jobname = 'vinabike_storefront_publication_dispatcher') as cron_job_installed;

-- §12 pg_cron: installed jobs and the last 24 hours of runs.
select
  '12_cron_jobs' as section,
  jobid,
  jobname,
  schedule,
  active,
  username,
  left(command, 120) as command
from cron.job
order by jobid;

select
  '12b_cron_runs_24h' as section,
  j.jobname,
  count(*) as runs,
  count(*) filter (where d.status <> 'succeeded') as not_succeeded,
  round(avg(extract(epoch from (d.end_time - d.start_time)))::numeric, 3) as avg_s,
  round(max(extract(epoch from (d.end_time - d.start_time)))::numeric, 3) as max_s,
  round(sum(extract(epoch from (d.end_time - d.start_time)))::numeric, 1) as total_s,
  max(d.start_time) as last_start,
  left(max(d.return_message) filter (where d.status <> 'succeeded'), 160) as last_failure_message
from cron.job_run_details d
join cron.job j on j.jobid = d.jobid
where d.start_time >= now() - interval '24 hours'
group by j.jobname
order by total_s desc;

select
  '12c_cron_run_log_footprint' as section,
  count(*) as job_run_details_rows,
  min(start_time) as oldest_row,
  pg_size_pretty(pg_total_relation_size('cron.job_run_details')) as relation_total_size
from cron.job_run_details;

-- §12d Aborted transactions and error rate. A request storm that FAILS never
-- shows up in pg_stat_statements (only successfully completed statements are
-- recorded), so a runaway client retrying a rejected RPC is invisible in §2-§4
-- and only appears here and in postgres_logs (ERROR lines per hour). This is
-- what burned the instance on 2026-09-15: 1.14 billion rollbacks in 16 days.
select
  '12d_rollbacks' as section,
  xact_commit,
  xact_rollback,
  round((100.0 * xact_rollback / greatest(xact_commit + xact_rollback, 1))::numeric, 1) as rollback_pct,
  stats_reset
from pg_stat_database
where datname = current_database();

-- §13 pg_net responses still retained (default TTL is 6 hours).
select
  '13_pg_net_responses' as section,
  status_code,
  (error_msg is not null) as errored,
  count(*) as responses,
  min(created) as oldest,
  max(created) as newest,
  left(max(error_msg), 120) as sample_error
from net._http_response
group by status_code, (error_msg is not null)
order by responses desc;

-- §14 Realtime: live postgres_changes subscriptions and the publication.
select
  '14_realtime_subscriptions' as section,
  entity::regclass as relation,
  count(*) as subscriptions,
  count(distinct subscription_id) as distinct_subscribers,
  count(*) filter (where filters <> '{}') as with_filters,
  min(created_at) as oldest,
  max(created_at) as newest
from realtime.subscription
group by entity
order by subscriptions desc;

select
  '14b_realtime_publication' as section,
  pubname,
  schemaname || '.' || tablename as relation
from pg_publication_tables
where pubname = 'supabase_realtime'
order by relation;
