begin;
select id from public.database_backups where id='e2899100-0000-4000-8000-000000000050' for update;
select 'HOLD_READY' as state;
select pg_sleep(10);
rollback;
select 'HOLD_RELEASED' as state;
