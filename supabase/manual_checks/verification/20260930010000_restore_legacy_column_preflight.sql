-- Read-only structural readback. It must fail before the forward migration.
-- Local pgTAP proves the catalog/JSON behavior; no hosted restore is run.
select
  to_regprocedure('public.restore_backup_legacy_column_blocker(jsonb)')
    is not null as helper_exists,
  has_function_privilege('authenticated',
    to_regprocedure('public.restore_backup_legacy_column_blocker(jsonb)'),
    'EXECUTE')
    as authenticated_can_call_helper,
  (select count(*) from pg_catalog.pg_attribute a
     where a.attrelid = 'public.messages'::regclass
       and a.attname = 'message_sequence'
       and a.attidentity = 'a') as covered_always_identity_columns;

select 1 / (case when
  to_regprocedure('public.restore_backup_legacy_column_blocker(jsonb)')
    is not null
  and position('missing_default' in pg_get_functiondef(
      to_regprocedure('public.restore_backup_legacy_column_blocker(jsonb)'))) > 0
  and position('unknown_column' in pg_get_functiondef(
      to_regprocedure('public.restore_backup_legacy_column_blocker(jsonb)'))) > 0
  and position('identity_replay' in pg_get_functiondef(
      to_regprocedure('public.restore_backup_legacy_column_blocker(jsonb)'))) > 0
  and not has_function_privilege('anon',
      to_regprocedure('public.restore_backup_legacy_column_blocker(jsonb)'),
      'EXECUTE')
  and not has_function_privilege('authenticated',
      to_regprocedure('public.restore_backup_legacy_column_blocker(jsonb)'),
      'EXECUTE')
  and not has_function_privilege('service_role',
      to_regprocedure('public.restore_backup_legacy_column_blocker(jsonb)'),
      'EXECUTE')
  and position('v_schema_blocker := public.restore_backup_legacy_column_blocker(v_data)'
      in pg_get_functiondef('public.restore_backup_preflight(uuid,uuid)'::regprocedure)) > 0
  and position('and v_schema_blocker is null'
      in pg_get_functiondef('public.restore_backup_preflight(uuid,uuid)'::regprocedure)) > 0
  and position('v_schema_blocker := public.restore_backup_legacy_column_blocker(v_data)'
      in pg_get_functiondef('public.restore_backup(uuid,uuid)'::regprocedure)) > 0
  and position('v_schema_blocker := public.restore_backup_legacy_column_blocker(v_data)'
      in pg_get_functiondef('public.restore_backup(uuid,uuid)'::regprocedure))
    < position('v_result := public.restore_backup_internal(p_backup_id, p_tenant_id)'
      in pg_get_functiondef('public.restore_backup(uuid,uuid)'::regprocedure))
  and exists (
    select 1 from pg_catalog.pg_attribute a
     where a.attrelid = 'public.messages'::regclass
       and a.attname = 'message_sequence'
       and a.attidentity = 'a'
  )
then 1 else 0 end) as restore_legacy_column_guard_contract;
