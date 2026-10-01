-- Exact synthetic namespace only. The harness checks vault/local before entry.
begin;
delete from public.tenants where id='e2899100-0000-4000-8000-000000000001';
delete from public.user_profiles where user_id='e2899100-0000-4000-8000-000000000091';
delete from auth.users where id='e2899100-0000-4000-8000-000000000091';
commit;
select 1/case when not exists(select 1 from public.tenants where id='e2899100-0000-4000-8000-000000000001')
 and not exists(select 1 from public.customers where tenant_id='e2899100-0000-4000-8000-000000000001')
 and not exists(select 1 from public.database_backups where tenant_id='e2899100-0000-4000-8000-000000000001')
 and not exists(select 1 from auth.users where id='e2899100-0000-4000-8000-000000000091') then 1 else 0 end as cleanup_verified;
