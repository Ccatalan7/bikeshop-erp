select
  to_regprocedure(
    'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)'
  )::text as workshop_edit_function,
  has_function_privilege(
    'authenticated',
    'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)',
    'execute'
  ) as authenticated_can_execute,
  has_function_privilege(
    'anon',
    'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)',
    'execute'
  ) as anon_can_execute;

select 1 / (
  case
    when to_regprocedure(
      'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)'
    ) is not null
      and has_function_privilege(
        'authenticated',
        'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)',
        'execute'
      )
      and not has_function_privilege(
        'anon',
        'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)',
        'execute'
      )
    then 1 else 0
  end
) as asserts_guarded_workshop_writer_acl;

select
  position(
    'job_bike.job_id = v_need.mechanic_job_id'
    in pg_get_functiondef(
      'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)'
      ::regprocedure
    )
  ) > 0 as validates_same_job_bike,
  position(
    'v_need.version <> p_expected_version'
    in pg_get_functiondef(
      'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)'
      ::regprocedure
    )
  ) > 0 as validates_optimistic_version,
  position(
    'supply_need_events'
    in pg_get_functiondef(
      'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)'
      ::regprocedure
    )
  ) > 0 as appends_durable_receipt,
  position(
    'pg_advisory_xact_lock'
    in pg_get_functiondef(
      'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)'
      ::regprocedure
    )
  ) > 0 as serializes_replay_key;

select 1 / (
  case
    when position(
      'job_bike.job_id = v_need.mechanic_job_id'
      in pg_get_functiondef(
        'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)'
        ::regprocedure
      )
    ) > 0
      and position(
        'v_need.version <> p_expected_version'
        in pg_get_functiondef(
          'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)'
          ::regprocedure
        )
      ) > 0
      and position(
        'supply_need_events'
        in pg_get_functiondef(
          'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)'
          ::regprocedure
        )
      ) > 0
      and position(
        'pg_advisory_xact_lock'
        in pg_get_functiondef(
          'public.update_workshop_supply_need_v1(uuid,bigint,text,uuid,numeric,text,uuid,text)'
          ::regprocedure
        )
      ) > 0
    then 1 else 0
  end
) as asserts_workshop_traceability_definition;
