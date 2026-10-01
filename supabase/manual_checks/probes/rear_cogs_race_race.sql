-- Connection B: finishes job B (the threaded freewheel) while A holds the
-- bike. The transition command waits for the bike at most 750 ms
-- (`lock_timeout`, 20260928060000): the freewheel is not written, the line
-- is reported as rejected with 55P03 in the response (the retry notice needs
-- the bike's row too, and is best effort). Job B still finishes.
select set_config('request.jwt.claims', '{"sub": "e2830000-0000-4000-8000-000000000099", "role": "authenticated"}', false);
select set_config('request.jwt.claim.sub', 'e2830000-0000-4000-8000-000000000099', false);
select public.transition_mechanic_job_status(
  'e2830000-0000-4000-8000-000000000052',
  (select id from public.job_statuses where tenant_id = 'e2830000-0000-4000-8000-000000000001' and code = 'FINALIZADO'),
  'probe-rear-cogs-b')->'installed_bike_facts' as finished_b;
