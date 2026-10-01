-- Exact source and effective ACL readback for the reviewed forward. No writes.
with expected(signature,body_md5,public_rpc) as (values
    ('public.backup_merge_payload_internal(jsonb)', '45229a9ca524dc1bdf998a86bbcd61a9', false),
    ('public.backup_merge_expression_safe_internal(pg_node_tree,boolean)', '45e8b521876f9f107bdb70eed61d69ec', false),
    ('public.backup_merge_relation_plan_internal(regclass,jsonb,uuid)', 'cfe5d96923ace4be70cba788fb304d0e', false),
    ('public.backup_merge_effective_rows_internal(regclass,jsonb,uuid)', '6596814c8edb087dc4b79212450975d9', false),
    ('public.backup_merge_fk_plan_internal(regclass,jsonb,uuid)', '6439bc023cbc33e10430f8959d5d87c5', false),
    ('public.backup_merge_live_fk_plan_internal(regclass,jsonb,uuid)', '66e3ecf9fa828f63982cfff16b889726', false),
    ('public.backup_merge_changes_internal(regclass,jsonb,uuid)', 'bbccffb7694334037d5e988543f4747d', false),
    ('public.backup_merge_integrity_internal(regclass,jsonb,uuid)', '6fff0389c2ee54bad165001cf1f74d43', false),
    ('public.backup_merge_effects_safe_internal(regclass,jsonb,uuid)', '2003f50d7f4cf9aee077181fb72c98e8', false),
    ('public.backup_merge_plan_internal(jsonb,uuid)', 'faa703227ebd124190160392a5dae5e9', false),
    ('public.backup_merge_apply_internal(jsonb,uuid)', '535c82476e1f7ec97e4383d5c73d120d', false),
    ('public.restore_backup_merge_preflight(uuid,uuid)', 'd74740e99cfeb59828b8b627abc2bf9c', true),
    ('public.restore_backup_merge(uuid,uuid)', '03bcaefee90e924c594f050832b9ac32', true)
), actual as (
  select e.*, p.oid, p.prosrc, p.prosecdef, p.proowner,
    p.proconfig, p.proacl, p.prorettype
    from expected e left join pg_proc p on p.oid=to_regprocedure(e.signature)
), checks as (
select
  count(*)=13 and count(oid)=13 as functions_exist,
  bool_and(md5(prosrc)=body_md5) as exact_function_bodies,
  bool_and(prosecdef and proowner='postgres'::regrole and prorettype =
    case when signature like '%expression_safe%' or signature like '%integrity%'
      or signature like '%effects_safe%' then 'boolean'::regtype
    when signature like '%effective_rows%' or signature like '%changes_internal%'
      then 'record'::regtype else 'jsonb'::regtype end) as owners_security_and_returns,
  bool_and(proconfig @> array['search_path=pg_catalog, public, pg_temp']
    or (public_rpc and proconfig @> array['search_path=pg_catalog, public, extensions, pg_temp'])) as fixed_search_path,
  bool_and(not exists(select 1 from aclexplode(coalesce(actual.proacl,acldefault('f',actual.proowner))) a
    where a.privilege_type='EXECUTE' and (a.grantee=0 or a.grantee in ('anon'::regrole,'service_role'::regrole)
      or (not actual.public_rpc and a.grantee='authenticated'::regrole)))) as no_private_or_anonymous_bypass,
  bool_and(not public_rpc or has_function_privilege('authenticated',oid,'EXECUTE')) as public_admin_rpc_grants
  , (select count(*)=2 and bool_and(md5(replace(pg_get_functiondef(to_regprocedure(signature)), E'\r\n', E'\n'))=digest)
       from (values ('public.set_updated_at()', '5d26afc0bd9e881933204e17151f1f50'),
         ('public.guard_customer_identity_update()', '29073d53212e18fedf797228025e5dde')) approved(signature,digest))
    as reviewed_trigger_definitions
  , bool_and(signature <> 'public.restore_backup_merge(uuid,uuid)'
      or proconfig @> array['lock_timeout=3s']) as bounded_lock_wait
from actual
)
select checks.*,
  1 / case when functions_exist and exact_function_bodies
    and owners_security_and_returns and fixed_search_path
    and no_private_or_anonymous_bypass and public_admin_rpc_grants
    and reviewed_trigger_definitions and bounded_lock_wait
    then 1 else 0 end as verification_passed
from checks;
