-- Read only. Exact source, effective access and dedicated bucket fences.
with expected(signature, body_md5, return_type, client_exec) as (values
  ('public.workshop_legacy_asset_copy_guard_v1()',
   '74ae232199dac96bd97beb433a9052e7', 'trigger', false),
  ('public.workshop_legacy_asset_job_can_read_v1(uuid)',
   'e64b12e86da4168b2593a9ef9dd3ed47', 'boolean', false),
  ('public.workshop_legacy_asset_storage_can_read_v1(text)',
   'e4660368366f28fb5842ceeceda6bf03', 'boolean', true),
  ('public.workshop_legacy_asset_read_v1(text)',
   '66e96aa95504dad61ec514342291da88', 'jsonb', true)
), actual as (
  select e.*, p.oid, p.prosrc, p.prosecdef, p.proowner, p.proconfig,
    p.proacl, p.prorettype
  from expected e left join pg_proc p on p.oid = to_regprocedure(e.signature)
), policy_expected(policy_name, command, permissive, roles) as (values
  ('workshop_legacy_private_select', 'r', true, array['authenticated']),
  ('workshop_legacy_private_authenticated_guard', 'r', false, array['authenticated']),
  ('workshop_legacy_private_anon_guard', 'r', false, array['anon']),
  ('workshop_legacy_private_insert_guard', 'a', false, array['anon','authenticated']),
  ('workshop_legacy_private_update_guard', 'w', false, array['anon','authenticated']),
  ('workshop_legacy_private_delete_guard', 'd', false, array['anon','authenticated'])
), policy_actual as (
  select e.*, p.oid, p.polcmd, p.polpermissive,
    pg_get_expr(p.polqual, p.polrelid) as qualifier,
    pg_get_expr(p.polwithcheck, p.polrelid) as check_qualifier,
    (select array_agg(role.rolname::text order by role.rolname)
      from pg_roles role where role.oid = any(p.polroles)) as actual_roles
  from policy_expected e left join pg_policy p
    on p.polrelid = 'storage.objects'::regclass and p.polname = e.policy_name
), checks as (
  select
    count(*) = 4 and count(oid) = 4 as functions_exist,
    bool_and(md5(prosrc) = body_md5) as exact_function_bodies,
    bool_and(prosecdef and proowner = 'postgres'::regrole
      and prorettype = return_type::regtype
      and proconfig @> array['search_path=pg_catalog, public, auth, pg_temp']
      or (signature like '%copy_guard%' and prosecdef
        and proowner = 'postgres'::regrole and prorettype = 'trigger'::regtype
        and proconfig @> array['search_path=pg_catalog, public, storage, pg_temp'])
      or (signature = 'public.workshop_legacy_asset_read_v1(text)' and prosecdef
        and proowner = 'postgres'::regrole and prorettype = 'jsonb'::regtype
        and proconfig @> array['search_path=pg_catalog, public, auth, storage, pg_temp']))
      as owners_security_and_search_path,
    bool_and(not exists (
      select 1 from aclexplode(coalesce(actual.proacl, acldefault('f',actual.proowner))) acl
      where acl.privilege_type = 'EXECUTE'
        and (acl.grantee = 0 or acl.grantee in ('anon'::regrole,'service_role'::regrole)
          or (not actual.client_exec and acl.grantee = 'authenticated'::regrole))
    ) and (not client_exec or has_function_privilege('authenticated', oid, 'EXECUTE')))
      as effective_function_acl,
    (select public is false and file_size_limit = 20971520
      from storage.buckets where id = 'workshop-legacy-private') as bucket_private,
    (select relrowsecurity from pg_class
      where oid = to_regclass('public.workshop_legacy_asset_copies')) as receipts_rls,
    not has_table_privilege('anon','public.workshop_legacy_asset_copies','SELECT,INSERT,UPDATE,DELETE')
      and not has_table_privilege('authenticated','public.workshop_legacy_asset_copies','SELECT,INSERT,UPDATE,DELETE')
      and not has_table_privilege('service_role','public.workshop_legacy_asset_copies','SELECT,INSERT,UPDATE,DELETE')
      as receipts_private,
    (select count(*) = 1 and bool_and(tgenabled = 'O' and tgtype = 23
       and tgfoid = to_regprocedure('public.workshop_legacy_asset_copy_guard_v1()'))
      from pg_trigger where tgrelid = to_regclass('public.workshop_legacy_asset_copies')
        and tgname = 'workshop_legacy_asset_copy_guard') as live_copy_guard,
    (select count(*) = 6 and count(oid) = 6
      and bool_and(polcmd::text = command and polpermissive = permissive
        and actual_roles = roles
        and coalesce(qualifier, check_qualifier) like '%workshop-legacy-private%'
        and (command <> 'w' or check_qualifier like '%workshop-legacy-private%')
        and (policy_name not in ('workshop_legacy_private_select',
          'workshop_legacy_private_authenticated_guard')
          or qualifier like '%workshop_legacy_asset_storage_can_read_v1(name)%'))
      from policy_actual) as exact_bucket_fences
  from actual
)
select checks.*, 1 / case when functions_exist and exact_function_bodies
  and owners_security_and_search_path and effective_function_acl
  and bucket_private and receipts_rls and receipts_private
  and live_copy_guard and exact_bucket_fences then 1 else 0 end as verification_passed
from checks;
