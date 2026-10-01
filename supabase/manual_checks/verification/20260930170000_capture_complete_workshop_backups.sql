-- Exact source and ACL readback for 20260930170000 (workshop graph capture).
-- No writes. Division by zero when any check fails.
with expected(signature, body_md5, public_rpc) as (values
    ('public.workshop_backup_scope_internal()', 'e8762d2f05a3f0fa51485429f5652670', false),
    ('public.capture_workshop_backup_internal(uuid)', '8ef8245d928f7d5fe9311eec484c1449', false),
    ('public.create_backup_internal(uuid,text,text,text)', '349a0499c5d3f8df81665a3edeec603f', false)
), actual as (
  select e.*, p.oid, p.prosrc, p.prosecdef, p.proowner, p.proconfig, p.proacl
    from expected e left join pg_proc p on p.oid = to_regprocedure(e.signature)
), checks as (
  select
    count(*) = 3 and count(oid) = 3 as functions_exist,
    bool_and(md5(prosrc) = body_md5) as exact_function_bodies,
    bool_and(prosecdef and proowner = 'postgres'::regrole) as owners_and_security,
    bool_and(proconfig @> array['search_path=pg_catalog, public, pg_temp']
      or proconfig @> array['search_path=pg_catalog, public, extensions, pg_temp']) as fixed_search_path,
    bool_and(not exists (select 1 from aclexplode(coalesce(actual.proacl, acldefault('f', actual.proowner))) a
      where a.privilege_type = 'EXECUTE' and (a.grantee = 0 or a.grantee in
        ('anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole)))) as private_helpers,
    (select count(*) = 70
        and bool_or(table_name = 'supply_needs')
        and not bool_or(table_name = 'mechanic_job_line_gate_deferrals')
        and bool_and(to_regclass(format('public.%I', table_name)) is not null)
       from public.workshop_backup_scope_internal()) as closed_capture_scope,
    (select count(*) = 1 from pg_proc p
      where p.oid = 'public.create_backup(uuid,text,text,text)'::regprocedure
        and p.prosrc like '%can_manage_tenant_backups(p_tenant_id)%'
        and p.prosrc like '%public.create_backup_internal(%') as public_entry_rechecks_authority
  from actual
)
select checks.*,
  1 / case when functions_exist and exact_function_bodies and owners_and_security
    and fixed_search_path and private_helpers and closed_capture_scope
    and public_entry_rechecks_authority then 1 else 0 end as verification_passed
from checks;
