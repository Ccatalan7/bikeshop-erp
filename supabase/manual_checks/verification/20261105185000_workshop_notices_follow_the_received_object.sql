-- Read-back of 20261105185000. Fails before the migration (the notices still
-- filter on `workflow_kind = service` and a decided quote still reads as ready)
-- and passes after: they follow the received object, a quote decided in
-- `quotation_status` is no longer announced, and both helpers stay closed to
-- every caller role.

select 1 / (case when
  pg_get_functiondef(
    'public.workshop_notice_enqueue_internal(uuid, uuid, text, uuid, timestamptz, uuid, boolean, boolean)'::regprocedure)
    like '%v_job.intake_kind not in (''bike'', ''component'')%'
  and pg_get_functiondef(
    'public.workshop_notice_enqueue_internal(uuid, uuid, text, uuid, timestamptz, uuid, boolean, boolean)'::regprocedure)
    not like '%<> ''service''%'
  and pg_get_functiondef(
    'public.workshop_notice_stale_reason_internal(text, public.mechanic_jobs)'::regprocedure)
    like '%quotation_status, '''') in (''approved'', ''rejected'', ''expired'')%'
  and not has_function_privilege('authenticated',
    'public.workshop_notice_enqueue_internal(uuid, uuid, text, uuid, timestamptz, uuid, boolean, boolean)',
    'EXECUTE')
  and not has_function_privilege('service_role',
    'public.workshop_notice_enqueue_internal(uuid, uuid, text, uuid, timestamptz, uuid, boolean, boolean)',
    'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.workshop_notice_stale_reason_internal(text, public.mechanic_jobs)', 'EXECUTE')
then 1 else 0 end) as avisos_siguen_lo_recibido;
