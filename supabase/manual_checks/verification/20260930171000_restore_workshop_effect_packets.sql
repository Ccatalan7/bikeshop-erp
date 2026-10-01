-- Exact source, ACL and hook readback for 20260930171000 (effect packets).
-- No writes. Division by zero when any check fails.
with expected(signature, body_md5, definer, every_writer) as (values
    ('public.workshop_restore_trigger_review_internal()', '081f675ffafce67439bc8475a779fe65', false, false),
    ('public.workshop_restore_effect_suppressed(regclass,name)', '1b20e6a8cbd5a3cf4844f976925902c9', false, true),
    ('public.workshop_restore_hook_when_internal(text,name)', '6e8f4a7858c3eedde336208f686cf79e', false, false),
    ('public.workshop_restore_open_internal(uuid)', '5bd188d8825b31038a1527102c8b007c', true, false),
    ('public.workshop_restore_suppress_internal(uuid,regclass)', '57bc9925c782889ea799450caf947bb3', true, false),
    ('public.workshop_restore_release_internal(uuid)', '761e6be5879919c7c26c3e326b556388', true, false),
    ('public.workshop_restore_close_internal(uuid)', '9dea5be545932b13ecb82689b6c985d0', true, false)
), actual as (
  select e.*, p.oid, p.prosrc, p.prosecdef, p.proowner, p.proconfig, p.proacl
    from expected e left join pg_proc p on p.oid = to_regprocedure(e.signature)
), hooks as (
  select review.table_name, review.trigger_name, t.oid, t.tgenabled,
    position(public.workshop_restore_hook_when_internal(review.table_name, review.trigger_name)
             in pg_get_triggerdef(t.oid)) > 0 as hooked
    from public.workshop_restore_trigger_review_internal() review
    left join pg_trigger t on t.tgrelid = to_regclass(format('public.%I', review.table_name))
      and t.tgname = review.trigger_name and not t.tgisinternal
   where review.review = 'hook'
), kept as (
  select review.table_name, review.trigger_name,
    t.tgqual is null and t.tgenabled = 'O'
      and md5(replace(pg_get_functiondef(t.tgfoid), E'\r\n', E'\n')) = review.function_md5 as reviewed
    from public.workshop_restore_trigger_review_internal() review
    left join pg_trigger t on t.tgrelid = to_regclass(format('public.%I', review.table_name))
      and t.tgname = review.trigger_name and not t.tgisinternal
   where review.review = 'keep'
), checks as (
  select
    count(*) = 7 and count(oid) = 7 as functions_exist,
    bool_and(md5(prosrc) = body_md5) as exact_function_bodies,
    bool_and(proowner = 'postgres'::regrole and prosecdef = definer) as owners_and_security,
    bool_and(proconfig @> array['search_path=pg_catalog, public, pg_temp']) as fixed_search_path,
    bool_and(every_writer or not exists (select 1 from aclexplode(coalesce(actual.proacl, acldefault('f', actual.proowner))) a
      where a.privilege_type = 'EXECUTE' and (a.grantee = 0 or a.grantee in
        ('anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole)))) as private_helpers,
    bool_and(not every_writer or (not prosecdef and has_function_privilege('anon', oid, 'EXECUTE')
      and has_function_privilege('authenticated', oid, 'EXECUTE'))) as hook_callable_by_every_writer,
    (select count(*) = 30 and bool_and(hooked and tgenabled = 'O') from hooks) as thirty_hooks_rendered,
    (select count(*) = 11 and bool_and(coalesce(reviewed, false)) from kept) as eleven_validators_reviewed,
    (select bool_and(c.relrowsecurity) from pg_class c
      where c.oid in ('public.workshop_restore_invocations'::regclass,
                      'public.workshop_restore_effect_packets'::regclass)) as packet_tables_rls,
    (select not exists (select 1 from pg_class c cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
      where c.oid in ('public.workshop_restore_invocations'::regclass,
                      'public.workshop_restore_effect_packets'::regclass)
        and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole))))
      as packet_tables_private,
    (select count(*) = 0 from public.workshop_restore_invocations)
      and (select count(*) = 0 from public.workshop_restore_effect_packets) as no_open_packets
  from actual
)
select checks.*,
  1 / case when functions_exist and exact_function_bodies and owners_and_security
    and fixed_search_path and private_helpers and hook_callable_by_every_writer
    and thirty_hooks_rendered and eleven_validators_reviewed and packet_tables_rls
    and packet_tables_private and no_open_packets then 1 else 0 end as verification_passed
from checks;
