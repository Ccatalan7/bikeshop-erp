-- The retry after A committed (what saving job B does): the freewheel now
-- meets the Shimano HG that A declared and is reported as incompatible.
select set_config('request.jwt.claims', '{"sub": "e2830000-0000-4000-8000-000000000099", "role": "authenticated"}', false);
select set_config('request.jwt.claim.sub', 'e2830000-0000-4000-8000-000000000099', false);
select public.sync_job_installed_bike_facts_v1(
  'e2830000-0000-4000-8000-000000000052') as retried_b;
