begin;
set local statement_timeout='8s';
select set_config('request.jwt.claims','{"sub":"e2899100-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','e2899100-0000-4000-8000-000000000091',true);
set local role authenticated;
create temporary table result as select public.restore_backup_merge('e2899100-0000-4000-8000-000000000050','e2899100-0000-4000-8000-000000000001') as value;
select value from result;
select value->>'error_code' as error_code,
  1/case when value->>'error_code'='restore_merge_busy' and not(value->>'success')::boolean
    then 1 else 0 end as busy_refusal_verified from result;
reset role;
select 1/case when exists(select 1 from public.customers where id='e2899100-0000-4000-8000-000000000010' and phone='222')
  and exists(select 1 from public.database_backups where id='e2899100-0000-4000-8000-000000000050' and restored_at is null)
  then 1 else 0 end as no_write_verified;
rollback;
