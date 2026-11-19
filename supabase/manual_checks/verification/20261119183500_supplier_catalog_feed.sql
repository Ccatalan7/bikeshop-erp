-- Read-back for 20261119183500_supplier_catalog_feed. Plain SQL; it fails
-- with «division by zero» when an invariant is missing.

-- Diagnosis: the state the assertions below judge.
select
  to_regclass('public.supplier_catalog_feeds') is not null as feeds_exist,
  to_regclass('public.supplier_catalog_feed_items') is not null as items_exist,
  to_regclass('public.supplier_catalog_feed_runs') is not null as runs_exist,
  to_regclass('public.supplier_catalog_feed_stock_events') is not null as events_exist,
  to_regclass('public.supplier_catalog_feed_runtime') is not null as runtime_exists,
  to_regprocedure('public.dispatch_supplier_catalog_feed_syncs()') is not null
    as dispatch_exists,
  to_regprocedure('public.redeem_supplier_catalog_feed_sync(uuid,text)') is not null
    as redeem_exists,
  to_regprocedure('public.apply_supplier_catalog_feed_rows_v1(uuid,jsonb)') is not null
    as apply_rows_exists,
  to_regprocedure('public.apply_supplier_catalog_feed_content_v1(uuid,jsonb)') is not null
    as apply_content_exists,
  to_regprocedure('public.finish_supplier_catalog_feed_run_v1(uuid,text[],jsonb)') is not null
    as finish_exists,
  to_regprocedure('public.fail_supplier_catalog_feed_run_v1(uuid,text,integer)') is not null
    as fail_exists,
  (
    select count(*) from cron.job job
    where job.jobname = 'vinabike_supplier_catalog_feeds' and job.active
  ) as active_schedules;

-- The pieces exist, with the signatures the function calls.
select 1 / (
  case when
    to_regclass('public.supplier_catalog_feeds') is not null
    and to_regclass('public.supplier_catalog_feed_items') is not null
    and to_regclass('public.supplier_catalog_feed_runs') is not null
    and to_regclass('public.supplier_catalog_feed_stock_events') is not null
    and to_regclass('public.supplier_catalog_feed_runtime') is not null
    and to_regprocedure('public.dispatch_supplier_catalog_feed_syncs()') is not null
    and to_regprocedure('public.redeem_supplier_catalog_feed_sync(uuid,text)') is not null
    and to_regprocedure('public.apply_supplier_catalog_feed_rows_v1(uuid,jsonb)') is not null
    and to_regprocedure('public.apply_supplier_catalog_feed_content_v1(uuid,jsonb)')
      is not null
    and to_regprocedure('public.finish_supplier_catalog_feed_run_v1(uuid,text[],jsonb)')
      is not null
    and to_regprocedure('public.fail_supplier_catalog_feed_run_v1(uuid,text,integer)')
      is not null
  then 1 else 0 end
) as feed_pieces_exist;

-- The five tables have RLS and the API roles hold none of the seven
-- privileges on them.
select 1 / (
  case when
    (
      select count(*) = 5
      from pg_class relation
      where relation.oid in (
        to_regclass('public.supplier_catalog_feeds'),
        to_regclass('public.supplier_catalog_feed_items'),
        to_regclass('public.supplier_catalog_feed_runs'),
        to_regclass('public.supplier_catalog_feed_stock_events'),
        to_regclass('public.supplier_catalog_feed_runtime')
      )
        and relation.relrowsecurity
    )
    and (
      select count(*) = 0
      from pg_class relation
      cross join unnest(array['anon', 'authenticated']) as grantee(name)
      cross join unnest(array[
        'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
      ]) as privilege(name)
      where relation.oid in (
        to_regclass('public.supplier_catalog_feeds'),
        to_regclass('public.supplier_catalog_feed_items'),
        to_regclass('public.supplier_catalog_feed_runs'),
        to_regclass('public.supplier_catalog_feed_stock_events'),
        to_regclass('public.supplier_catalog_feed_runtime')
      )
        and has_table_privilege(grantee.name, relation.oid, privilege.name)
    )
  then 1 else 0 end
) as feed_tables_are_private;

-- Only the server runs the six functions.
select 1 / (
  case when (
    select count(*) = 6
    from pg_proc routine
    where routine.oid in (
      to_regprocedure('public.dispatch_supplier_catalog_feed_syncs()')::oid,
      to_regprocedure('public.redeem_supplier_catalog_feed_sync(uuid,text)')::oid,
      to_regprocedure('public.apply_supplier_catalog_feed_rows_v1(uuid,jsonb)')::oid,
      to_regprocedure('public.apply_supplier_catalog_feed_content_v1(uuid,jsonb)')::oid,
      to_regprocedure('public.finish_supplier_catalog_feed_run_v1(uuid,text[],jsonb)')::oid,
      to_regprocedure('public.fail_supplier_catalog_feed_run_v1(uuid,text,integer)')::oid
    )
      and routine.prosecdef
      and has_function_privilege('service_role', routine.oid, 'EXECUTE')
      and not has_function_privilege('anon', routine.oid, 'EXECUTE')
      and not has_function_privilege('authenticated', routine.oid, 'EXECUTE')
  ) then 1 else 0 end
) as feed_functions_are_service_only;

-- Diagnosis: MKR's feed as stored (never its token, which is not here).
select
  feed.format,
  feed.feed_key,
  feed.credential_key,
  feed.account_discount_percent,
  feed.enabled,
  feed.endpoint_template like 'https://mkr.cl/%{token}%' as address_is_mkr,
  feed.last_status,
  feed.listed_count
from public.supplier_catalog_feeds feed
where feed.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and feed.supplier_id = '3f6f71dc-99b8-4f0c-9f44-cd37276fc5ee';

-- MKR Imports has its feed, with the token as a placeholder and the 5 % its
-- portal gives this account.
select 1 / (
  case when (
    select count(*) = 1
    from public.supplier_catalog_feeds feed
    where feed.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and feed.supplier_id = '3f6f71dc-99b8-4f0c-9f44-cd37276fc5ee'
      and feed.feed_key = 'catalog'
      and feed.format = 'mkr_csv_v1'
      and feed.endpoint_template = 'https://mkr.cl/api/endpoint?token={token}'
      and feed.credential_key = 'catalog_feed'
      and feed.account_discount_percent = 5
      and feed.enabled
  ) then 1 else 0 end
) as mkr_feed_is_defined;

-- The schedule posts to the function of this project, every 30 minutes.
select 1 / (
  case when
    (
      select count(*) = 1
      from public.supplier_catalog_feed_runtime runtime
      where runtime.singleton
        and runtime.enabled
        and runtime.endpoint
          = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/supplier-feed-sync'
    )
    and (
      select count(*) = 1
      from cron.job job
      where job.jobname = 'vinabike_supplier_catalog_feeds'
        and job.active
        and job.schedule = '19,49 * * * *'
        and job.command = 'select public.dispatch_supplier_catalog_feed_syncs();'
    )
  then 1 else 0 end
) as feed_schedule_is_set;
