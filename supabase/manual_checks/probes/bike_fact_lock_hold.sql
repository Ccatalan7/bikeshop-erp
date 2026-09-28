-- Connection A: cancels the finished job holding its row the way
-- transition_mechanic_job_status does (`for update`), and waits 15 s before
-- committing. `query.sh` takes seconds to start, so a shorter hold lets B
-- arrive after the commit and proves nothing (first run, 2026-09-27).
begin;
select id from public.mechanic_jobs where id = 'e2790000-0000-4000-8000-000000000051' and tenant_id = 'e2790000-0000-4000-8000-000000000001' for update;
update public.mechanic_jobs set status = 'CANCELADO' where id = 'e2790000-0000-4000-8000-000000000051' and tenant_id = 'e2790000-0000-4000-8000-000000000001';
select to_char(clock_timestamp(), 'HH24:MI:SS.MS') as cancel_holds_lock;
select pg_sleep(15);
commit;
select to_char(clock_timestamp(), 'HH24:MI:SS.MS') as cancel_committed;
