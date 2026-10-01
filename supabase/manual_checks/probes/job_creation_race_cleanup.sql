-- Removes the probe fixture; also runs first. Ends reading that nothing of
-- the probe tenant is left (jobs, bikes, customers, users).
begin;
delete from public.mechanic_job_creations
 where tenant_id = 'e2870000-0000-4000-8000-000000000001';
delete from public.bike_events
 where tenant_id = 'e2870000-0000-4000-8000-000000000001';
delete from public.tenants
 where id = 'e2870000-0000-4000-8000-000000000001';
delete from public.user_profiles
 where user_id = 'e2870000-0000-4000-8000-000000000091';
delete from auth.users
 where id = 'e2870000-0000-4000-8000-000000000091';
commit;
select (select count(*) from public.mechanic_jobs
         where tenant_id = 'e2870000-0000-4000-8000-000000000001')
     + (select count(*) from public.bikes
         where tenant_id = 'e2870000-0000-4000-8000-000000000001')
     + (select count(*) from public.customers
         where tenant_id = 'e2870000-0000-4000-8000-000000000001')
     + (select count(*) from auth.users
         where id = 'e2870000-0000-4000-8000-000000000091') as left_over;
