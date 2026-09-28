-- Connection B: the finished job's wheel line writes its 28H while A is
-- cancelling the job.
select set_config('request.jwt.claims', '{"sub": "e2790000-0000-4000-8000-000000000099", "role": "authenticated"}', false);
select set_config('request.jwt.claim.sub', 'e2790000-0000-4000-8000-000000000099', false);
select to_char(clock_timestamp(), 'HH24:MI:SS.MS') as install_starts;
select public.patch_bike_technical_facts_v1(
  'job_completion:e2790000-0000-4000-8000-000000000061:1:frontSpokeHoles=28',
  'e2790000-0000-4000-8000-000000000031', 'e2790000-0000-4000-8000-000000000051', 'job_completion',
  '[{"key": "frontSpokeHoles", "op": "set", "value": 28, "expected": 32, "expected_confirmed": false}]'::jsonb) is not null as installed;
select to_char(clock_timestamp(), 'HH24:MI:SS.MS') as install_ends;
