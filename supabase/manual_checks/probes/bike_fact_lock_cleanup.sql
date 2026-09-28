-- Removes the probe fixture; also run first, in case a failed run left it.
begin;
delete from public.bike_events where tenant_id = 'e2790000-0000-4000-8000-000000000001';
delete from public.bike_technical_fact_patches where tenant_id = 'e2790000-0000-4000-8000-000000000001';
delete from public.mechanic_job_items where tenant_id = 'e2790000-0000-4000-8000-000000000001';
delete from public.mechanic_jobs where tenant_id = 'e2790000-0000-4000-8000-000000000001';
delete from public.bike_profiles where tenant_id = 'e2790000-0000-4000-8000-000000000001';
delete from public.bikes where tenant_id = 'e2790000-0000-4000-8000-000000000001';
delete from public.customers where tenant_id = 'e2790000-0000-4000-8000-000000000001';
delete from public.user_profiles where tenant_id = 'e2790000-0000-4000-8000-000000000001';
delete from auth.users where id = 'e2790000-0000-4000-8000-000000000099';
delete from public.tenants where id = 'e2790000-0000-4000-8000-000000000001';
commit;
select count(*) as leftover from public.tenants where id = 'e2790000-0000-4000-8000-000000000001';
