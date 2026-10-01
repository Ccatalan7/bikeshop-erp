begin;
update public.customers set phone='222' where id='e2899100-0000-4000-8000-000000000010';
select 'HOLD_READY' as state;
select pg_sleep(10);
rollback;
select 'HOLD_RELEASED' as state;
