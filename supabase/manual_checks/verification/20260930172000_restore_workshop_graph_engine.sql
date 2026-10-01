-- Exact source, ACL and contract readback for 20260930172000 (integrated
-- workshop recovery engine). No writes. Division by zero when any check fails.
with expected(signature, body_md5, public_rpc) as (values
    ('public.workshop_restore_tables_internal()', 'a12b25f074d381b626380d201869e15b', false),
    ('public.workshop_restore_soft_links_internal()', '93f11577a2b33bb3045f9a876667f1b0', false),
    ('public.workshop_restore_table_label(text)', '67eca8172f987d715f863c71f433bea0', false),
    ('public.workshop_restore_record_label(text,jsonb)', 'a8c260d301fd4adf0c95024117887bc4', false),
    ('public.workshop_restore_reject_internal(text,text,text)', '8e5c29a3aeb5c3e60825090a3954956a', false),
    ('public.workshop_restore_effects_review_internal(regclass)', 'a18dfbdae9e75132844a59229b260b23', false),
    ('public.workshop_restore_preserved_internal(text,jsonb)', '0c561469f2c2517d378b240d30bd2ca4', false),
    ('public.workshop_restore_task_graph_internal(text,uuid,jsonb)', '337f6ea060db761d11e3749eaaa06430', false),
    ('public.workshop_restore_table_internal(uuid,uuid,text,text,text,text,jsonb,jsonb)', '7a8e516f874ab44795e24d46acf4605f', false),
    ('public.workshop_restore_run_internal(jsonb,uuid)', '465609700ba49fc2aba104abe784a80f', false),
    ('public.workshop_restore_refusal_internal(text,text)', 'a63eb2b55cfec9d1c3825cdf09046ddb', false),
    ('public.restore_backup_merge_preflight(uuid,uuid)', '021523db73704f7a91b977a0c05bacaa', true),
    ('public.restore_backup_merge(uuid,uuid)', '44729ec7df7cf9e9c61dd04291f0635c', true)
), actual as (
  select e.*, p.oid, p.prosrc, p.prosecdef, p.proowner, p.proconfig, p.proacl, p.provolatile
    from expected e left join pg_proc p on p.oid = to_regprocedure(e.signature)
), checks as (
  select
    count(*) = 13 and count(oid) = 13 as functions_exist,
    bool_and(md5(prosrc) = body_md5) as exact_function_bodies,
    bool_and(proowner = 'postgres'::regrole) as owners,
    bool_and(proconfig @> array['search_path=pg_catalog, public, pg_temp']
      or (public_rpc and proconfig @> array['search_path=pg_catalog, public, extensions, pg_temp'])) as fixed_search_path,
    bool_and(not exists (select 1 from aclexplode(coalesce(actual.proacl, acldefault('f', actual.proowner))) a
      where a.privilege_type = 'EXECUTE' and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'service_role'::regrole)
        or (not public_rpc and a.grantee = 'authenticated'::regrole)))) as no_private_or_anonymous_bypass,
    bool_and(not public_rpc or (prosecdef and has_function_privilege('authenticated', oid, 'EXECUTE'))) as admin_rpc_grants,
    bool_and(signature <> 'public.restore_backup_merge(uuid,uuid)' or proconfig @> array['lock_timeout=3s']) as bounded_lock_wait,
    bool_and(signature <> 'public.restore_backup_merge_preflight(uuid,uuid)' or provolatile = 'v') as preflight_runs_engine,
    -- The writer decides the authority again after taking the table locks.
    bool_and(signature <> 'public.restore_backup_merge(uuid,uuid)'
      or ((length(prosrc) - length(replace(prosrc, 'can_manage_tenant_backups', '')))
            / length('can_manage_tenant_backups') = 2
          and strpos(substr(prosrc, strpos(prosrc, 'lock table')), 'can_manage_tenant_backups') > 0
          and strpos(substr(prosrc, strpos(prosrc, 'lock table')), 'can_manage_tenant_backups')
            < strpos(substr(prosrc, strpos(prosrc, 'lock table')), 'workshop_restore_run_internal')))
      as authority_rechecked_after_locks,
    -- The four hooked task guards are suppressed whole; their relations are
    -- verified by the engine for the three task tables.
    bool_and(signature <> 'public.workshop_restore_table_internal(uuid,uuid,text,text,text,text,jsonb,jsonb)'
      or strpos(prosrc, 'workshop_restore_task_graph_internal') > 0)
      and (select count(*) = 4 from public.workshop_restore_trigger_review_internal() r
            where r.review = 'hook' and (r.table_name, r.trigger_name::text) in (
              ('smart_tasks', 'trg_smart_tasks_guard_primary_context'),
              ('smart_tasks', 'trg_smart_tasks_guard_work_tray'),
              ('smart_task_job_items', 'trg_smart_task_job_items_guard'),
              ('smart_task_job_item_notes', 'trg_smart_task_job_item_notes_guard')))
      as task_relations_reverified,
    (select not exists (select 1 from public.workshop_backup_scope_internal() s
       where not exists (select 1 from public.workshop_restore_tables_internal() t where t.table_name = s.table_name)))
      as every_captured_table_has_a_policy,
    (select bool_and(public.workshop_restore_effects_review_internal(to_regclass(format('public.%I', t.table_name))) is null)
       from public.workshop_restore_tables_internal() t where t.policy in ('standalone', 'root', 'member'))
      as every_write_path_reviewed
  from actual
)
select checks.*,
  1 / case when functions_exist and exact_function_bodies and owners and fixed_search_path
    and no_private_or_anonymous_bypass and admin_rpc_grants and bounded_lock_wait
    and preflight_runs_engine and authority_rechecked_after_locks and task_relations_reverified
    and every_captured_table_has_a_policy
    and every_write_path_reviewed then 1 else 0 end as verification_passed
from checks;
