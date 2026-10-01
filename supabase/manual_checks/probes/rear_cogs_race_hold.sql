-- Connection A: finishes job A (the HG cassette) inside a transaction and
-- waits 15 s before committing, so the bike stays taken while B starts.
-- `query.sh` takes seconds to start; a shorter hold lets B arrive after the
-- commit and proves nothing.
select set_config('request.jwt.claims', '{"sub": "e2830000-0000-4000-8000-000000000099", "role": "authenticated"}', false);
select set_config('request.jwt.claim.sub', 'e2830000-0000-4000-8000-000000000099', false);
begin;
select public.transition_mechanic_job_status(
  'e2830000-0000-4000-8000-000000000051',
  (select id from public.job_statuses where tenant_id = 'e2830000-0000-4000-8000-000000000001' and code = 'FINALIZADO'),
  'probe-rear-cogs-a')->'installed_bike_facts' as finished_a;
select to_char(clock_timestamp(), 'HH24:MI:SS.MS') as a_holds_bike;
select pg_sleep(15);
commit;
select to_char(clock_timestamp(), 'HH24:MI:SS.MS') as a_committed;
