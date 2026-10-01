-- Jobs, «Trabajo creado» events and creation receipts of the probe job.
select (select count(*) from public.mechanic_jobs
         where id = 'e2870000-0000-4000-8000-000000000050'
           and tenant_id = 'e2870000-0000-4000-8000-000000000001') as jobs,
       (select count(*) from public.bike_events
         where job_id = 'e2870000-0000-4000-8000-000000000050'
           and tenant_id = 'e2870000-0000-4000-8000-000000000001'
           and event_type = 'job_created') as created_events,
       (select count(*) from public.mechanic_job_creations
         where operation_key = 'e2870000-0000-4000-8000-000000000050'
           and tenant_id = 'e2870000-0000-4000-8000-000000000001') as receipts;
