-- Deployment status: PENDING.
--
-- Purpose:
--   Recover the authenticated registrant for the eleven workshop jobs created
--   during the reviewed seven-day production window
--   [2026-08-07 21:29:13.800012+00, 2026-08-14 21:29:13.800012+00).
--
-- Evidence:
--   Each row below is bound to the exact production job id/number/timestamp,
--   its durable notification id, and the unique Supabase edge-log id for the
--   successful authenticated POST /rest/v1/mechanic_jobs response (HTTP 201).
--   The edge request followed the database insert by less than one second.
--
-- Safety:
--   This is an identity-bound, idempotent data repair. It refuses partial or
--   conflicting source state, validates an active same-tenant user profile,
--   changes only mechanic_jobs.created_by plus five notification data keys,
--   and preserves mechanic_jobs.updated_at. A clean/local database without
--   the production tenant is an intentional no-op. The generic job updated_at
--   trigger is disabled only while the bounded job update holds an exclusive
--   table lock; PostgreSQL transaction rollback restores it on any failure.
--
-- Recovery:
--   Do not erase the recovered actor or its evidence metadata. Any correction
--   requires a separately reviewed forward migration with stronger evidence.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create temporary table recent_mechanic_job_actor_evidence (
  job_id uuid primary key,
  job_number text not null unique,
  job_created_at timestamp with time zone not null unique,
  notification_id uuid not null unique,
  actor_id uuid not null,
  actor_name text not null,
  edge_log_id uuid not null unique,
  edge_log_at timestamp with time zone not null unique,
  source_method text not null default 'POST'
    check (source_method = 'POST'),
  source_path text not null default '/rest/v1/mechanic_jobs'
    check (source_path = '/rest/v1/mechanic_jobs'),
  source_search text not null default '?select=*'
    check (source_search = '?select=*'),
  source_status smallint not null default 201
    check (source_status = 201),
  check (
    edge_log_at >= job_created_at
    and edge_log_at - job_created_at < interval '1 second'
  )
) on commit drop;

insert into recent_mechanic_job_actor_evidence (
  job_id,
  job_number,
  job_created_at,
  notification_id,
  actor_id,
  actor_name,
  edge_log_id,
  edge_log_at
) values
  (
    '09ea490e-f731-4eb0-8004-d1321d60ecbd',
    'PG-00499',
    '2026-08-07 22:36:17.863967+00',
    '486896a8-a6a9-49db-8c2f-2f0e012ea948',
    '7bb76d88-5455-462e-a838-5f78af922914',
    'Claudio Catalán',
    '0f53a39d-2951-44a1-bebf-12857aea87f4',
    '2026-08-07 22:36:18.083000+00'
  ),
  (
    '833681d5-cc44-4361-ab5b-208d69776577',
    'PG-00500',
    '2026-08-08 15:18:17.654924+00',
    '6e25be21-32b4-43a3-a32e-d10610b103fa',
    '7bb76d88-5455-462e-a838-5f78af922914',
    'Claudio Catalán',
    '3f99fb84-a2e2-49f2-a603-589a4896a9d6',
    '2026-08-08 15:18:17.793000+00'
  ),
  (
    '322cfb22-64ca-4658-beb5-6bafad8f41d7',
    'PG-00501',
    '2026-08-10 18:10:17.033106+00',
    '7d22117d-0407-4399-82dc-24c02a942224',
    '7bb76d88-5455-462e-a838-5f78af922914',
    'Claudio Catalán',
    '8f9f0fcc-784a-412b-8f22-3ee2668fbabf',
    '2026-08-10 18:10:17.284000+00'
  ),
  (
    '0b5d1ff3-1d63-4715-aca2-a4e3d1b8721a',
    'PG-00502',
    '2026-08-11 18:27:23.520858+00',
    '3b825efa-ae85-4f84-95c5-4b7b914d031c',
    '7bb76d88-5455-462e-a838-5f78af922914',
    'Claudio Catalán',
    '96ebe7f7-4da7-45e3-b485-4eaee014b6f3',
    '2026-08-11 18:27:23.687000+00'
  ),
  (
    '9cc199d1-926c-4855-9f3c-a88c669f2072',
    'PG-00503',
    '2026-08-11 18:28:53.895228+00',
    '31a69532-9c3f-4195-8807-1b8bf6b16071',
    '7bb76d88-5455-462e-a838-5f78af922914',
    'Claudio Catalán',
    '1d26e9a4-62ae-4f56-a5f8-7b63283d4803',
    '2026-08-11 18:28:54.071000+00'
  ),
  (
    '39d35997-828a-42c1-89c9-ea6d7b641fc4',
    'PG-00504',
    '2026-08-12 17:11:59.200001+00',
    '1b3d2a1b-058c-48ae-82c1-4150951d8285',
    '7bb76d88-5455-462e-a838-5f78af922914',
    'Claudio Catalán',
    'aa1f7211-e32e-42a7-99ab-a01aeaa99bf3',
    '2026-08-12 17:11:59.374000+00'
  ),
  (
    '7383552d-00ac-445a-bcf8-fdf4abc180c4',
    'PG-00505',
    '2026-08-12 18:16:23.128097+00',
    'b43999c5-0632-4bff-aef0-fdae28ef2caf',
    '7bb76d88-5455-462e-a838-5f78af922914',
    'Claudio Catalán',
    '1bc3da7b-c005-4d12-9313-2b054f86132d',
    '2026-08-12 18:16:23.284000+00'
  ),
  (
    '838ca870-d246-4d6f-a1bf-e274a54ee1b8',
    'PG-00506',
    '2026-08-12 21:49:19.403634+00',
    'b841be62-e36b-485d-a60d-0ea25ef514d2',
    '7bb76d88-5455-462e-a838-5f78af922914',
    'Claudio Catalán',
    '8def1c99-8582-4cb6-aaeb-b97aa373a8c6',
    '2026-08-12 21:49:19.667000+00'
  ),
  (
    'c07122ec-bea4-44db-8af0-6073b42460df',
    'PG-00507',
    '2026-08-13 18:36:13.768176+00',
    '17df141b-d379-4d7b-bf4c-63478cc2a301',
    '7bb76d88-5455-462e-a838-5f78af922914',
    'Claudio Catalán',
    '557c39e6-faeb-4788-9b7b-2d73653cec11',
    '2026-08-13 18:36:13.852000+00'
  ),
  (
    '47172047-10c5-42b0-8089-9cac1f28077f',
    'PG-00508',
    '2026-08-13 21:46:13.756578+00',
    'ee0c0827-43bd-4398-8a47-a3c9e6dfee88',
    '7bb76d88-5455-462e-a838-5f78af922914',
    'Claudio Catalán',
    '52589017-e491-4276-a03b-4e122b3c9acb',
    '2026-08-13 21:46:13.913000+00'
  ),
  (
    '5ce8b362-6961-478a-981a-dfdb8954cf1d',
    'PG-00509',
    '2026-08-14 15:44:18.074188+00',
    'f5f5bec4-826a-4e35-a305-4e6535f23d6a',
    '5bf343db-32f4-4aea-9c69-ada809f966e2',
    'Vicente Díaz',
    '5224960b-8a1f-4a6b-ab9c-71c333297262',
    '2026-08-14 15:44:18.202000+00'
  );

create temporary table recent_mechanic_job_actor_before (
  job_id uuid primary key,
  job_preserved jsonb not null,
  notification_preserved jsonb not null,
  notification_data_preserved jsonb not null,
  notification_updated_at timestamp with time zone not null,
  notification_was_pending boolean not null
) on commit drop;

do $backfill$
declare
  v_tenant_id constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_window_start constant timestamp with time zone :=
    '2026-08-07 21:29:13.800012+00';
  v_window_end constant timestamp with time zone :=
    '2026-08-14 21:29:13.800012+00';
  v_migration constant text :=
    '20260814213000_backfill_recent_mechanic_job_registration_actor';
  v_expected_count constant integer := 11;
  v_expected_actor_count constant integer := 2;
  v_pending_jobs integer;
  v_pending_notifications integer;
  v_rows integer;
begin
  if (select count(*) from pg_temp.recent_mechanic_job_actor_evidence)
       <> v_expected_count then
    raise exception 'Recent job actor evidence does not contain exactly % rows.',
      v_expected_count using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.tenants tenant
    where tenant.id = v_tenant_id
  ) then
    if exists (
      select 1
      from public.mechanic_jobs job
      join pg_temp.recent_mechanic_job_actor_evidence evidence
        on evidence.job_id = job.id
    ) or exists (
      select 1
      from public.erp_notifications notification
      join pg_temp.recent_mechanic_job_actor_evidence evidence
        on evidence.notification_id = notification.id
    ) then
      raise exception 'Recent job actor evidence IDs exist without the reviewed production tenant.'
        using errcode = '23514';
    end if;

    raise notice 'Reviewed production tenant is absent; recent job actor backfill is a no-op.';
    return;
  end if;

  -- The fixed capture window contained exactly these eleven jobs. This rejects
  -- an incomplete evidence set before any production row can change.
  if (
    select count(*)
    from public.mechanic_jobs job
    where job.tenant_id = v_tenant_id
      and job.created_at >= v_window_start
      and job.created_at < v_window_end
  ) <> v_expected_count then
    raise exception 'Reviewed seven-day mechanic job window no longer contains exactly % rows.',
      v_expected_count using errcode = '23514';
  end if;

  if (
    select count(*)
    from public.mechanic_jobs job
    join pg_temp.recent_mechanic_job_actor_evidence evidence
      on evidence.job_id = job.id
     and evidence.job_number = job.job_number
     and evidence.job_created_at = job.created_at
    where job.tenant_id = v_tenant_id
      and job.created_at >= v_window_start
      and job.created_at < v_window_end
      and (
        job.created_by is null
        or job.created_by = evidence.actor_id
      )
  ) <> v_expected_count then
    raise exception 'Recent job identities, timestamps, or existing actors conflict with reviewed evidence.'
      using errcode = '23514';
  end if;

  if (
    select count(*)
    from public.erp_notifications notification
    join pg_temp.recent_mechanic_job_actor_evidence evidence
      on evidence.notification_id = notification.id
     and evidence.job_id = notification.entity_id
    where notification.tenant_id = v_tenant_id
      and notification.type = 'mechanic_job_created'
      and notification.entity_type = 'mechanic_job'
      and notification.created_at >= evidence.job_created_at
      and notification.created_at - evidence.job_created_at < interval '1 second'
  ) <> v_expected_count then
    raise exception 'Recent job notification identities or timestamps conflict with reviewed evidence.'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.erp_notifications notification
    join pg_temp.recent_mechanic_job_actor_evidence evidence
      on evidence.notification_id = notification.id
    where (
      nullif(notification.data->>'recorded_by_name', '') is not null
      and notification.data->>'recorded_by_name' <> evidence.actor_name
    ) or (
      nullif(notification.data->>'recorded_by_evidence_source', '') is not null
      and notification.data->>'recorded_by_evidence_source' <> 'supabase_edge_log'
    ) or (
      nullif(notification.data->>'recorded_by_evidence_log_id', '') is not null
      and notification.data->>'recorded_by_evidence_log_id' <> evidence.edge_log_id::text
    ) or (
      nullif(notification.data->>'recorded_by_evidence_at', '') is not null
      and notification.data->>'recorded_by_evidence_at' <>
        to_char(
          evidence.edge_log_at at time zone 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
        )
    ) or (
      nullif(notification.data->>'recorded_by_backfill', '') is not null
      and notification.data->>'recorded_by_backfill' <> v_migration
    )
  ) then
    raise exception 'A recent job notification already contains conflicting actor evidence.'
      using errcode = '23514';
  end if;

  select count(*)::integer
  into v_pending_jobs
  from public.mechanic_jobs job
  join pg_temp.recent_mechanic_job_actor_evidence evidence
    on evidence.job_id = job.id
  where job.created_by is distinct from evidence.actor_id;

  select count(*)::integer
  into v_pending_notifications
  from public.erp_notifications notification
  join pg_temp.recent_mechanic_job_actor_evidence evidence
    on evidence.notification_id = notification.id
  where notification.data is distinct from
    coalesce(notification.data, '{}'::jsonb) || jsonb_build_object(
      'recorded_by_name', evidence.actor_name,
      'recorded_by_evidence_source', 'supabase_edge_log',
      'recorded_by_evidence_log_id', evidence.edge_log_id::text,
      'recorded_by_evidence_at', to_char(
        evidence.edge_log_at at time zone 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
      ),
      'recorded_by_backfill', v_migration
    );

  if v_pending_jobs = 0 and v_pending_notifications = 0 then
    raise notice 'Recent job actor backfill is already complete.';
    return;
  end if;

  -- Only an active ERP identity in the same tenant can be recovered. The name
  -- must be the same one resolved by the canonical notification helper now.
  if (
    select count(*)
    from (
      select distinct evidence.actor_id, evidence.actor_name
      from pg_temp.recent_mechanic_job_actor_evidence evidence
    ) evidence
    join auth.users auth_user
      on auth_user.id = evidence.actor_id
    join public.user_profiles profile
      on profile.user_id = evidence.actor_id
     and profile.tenant_id = v_tenant_id
     and profile.is_active is true
    where public.erp_actor_display_name(
      evidence.actor_id,
      v_tenant_id
    ) = evidence.actor_name
  ) <> v_expected_actor_count then
    raise exception 'Recovered actors are not active same-tenant ERP users with the reviewed names.'
      using errcode = '23514';
  end if;

  -- Fail fast rather than waiting behind a busy workshop write. Once acquired,
  -- this lock makes the source re-check and bounded update atomic.
  lock table public.mechanic_jobs in access exclusive mode;

  perform 1
  from public.erp_notifications notification
  join pg_temp.recent_mechanic_job_actor_evidence evidence
    on evidence.notification_id = notification.id
  order by notification.id
  for update of notification;

  perform 1
  from public.user_profiles profile
  where profile.tenant_id = v_tenant_id
    and profile.user_id in (
      select distinct evidence.actor_id
      from pg_temp.recent_mechanic_job_actor_evidence evidence
    )
  order by profile.user_id
  for share of profile;

  -- Re-check the mutable identity/profile fields after all relevant locks.
  if exists (
    select 1
    from public.mechanic_jobs job
    join pg_temp.recent_mechanic_job_actor_evidence evidence
      on evidence.job_id = job.id
    where job.tenant_id <> v_tenant_id
       or job.job_number <> evidence.job_number
       or job.created_at <> evidence.job_created_at
       or (
         job.created_by is not null
         and job.created_by <> evidence.actor_id
       )
  ) or exists (
    select 1
    from (
      select distinct evidence.actor_id, evidence.actor_name
      from pg_temp.recent_mechanic_job_actor_evidence evidence
    ) evidence
    left join public.user_profiles profile
      on profile.user_id = evidence.actor_id
     and profile.tenant_id = v_tenant_id
    where profile.user_id is null
       or profile.is_active is not true
       or public.erp_actor_display_name(
         evidence.actor_id,
         v_tenant_id
       ) <> evidence.actor_name
  ) then
    raise exception 'Recent job actor source state changed while acquiring locks.'
      using errcode = '40001';
  end if;

  insert into pg_temp.recent_mechanic_job_actor_before (
    job_id,
    job_preserved,
    notification_preserved,
    notification_data_preserved,
    notification_updated_at,
    notification_was_pending
  )
  select
    job.id,
    to_jsonb(job) - 'created_by',
    to_jsonb(notification) - array['data', 'updated_at']::text[],
    coalesce(notification.data, '{}'::jsonb) - array[
      'recorded_by_name',
      'recorded_by_evidence_source',
      'recorded_by_evidence_log_id',
      'recorded_by_evidence_at',
      'recorded_by_backfill'
    ]::text[],
    notification.updated_at,
    notification.data is distinct from
      coalesce(notification.data, '{}'::jsonb) || jsonb_build_object(
        'recorded_by_name', evidence.actor_name,
        'recorded_by_evidence_source', 'supabase_edge_log',
        'recorded_by_evidence_log_id', evidence.edge_log_id::text,
        'recorded_by_evidence_at', to_char(
          evidence.edge_log_at at time zone 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
        ),
        'recorded_by_backfill', v_migration
      )
  from public.mechanic_jobs job
  join pg_temp.recent_mechanic_job_actor_evidence evidence
    on evidence.job_id = job.id
  join public.erp_notifications notification
    on notification.id = evidence.notification_id;

  select count(*)::integer
  into v_pending_jobs
  from public.mechanic_jobs job
  join pg_temp.recent_mechanic_job_actor_evidence evidence
    on evidence.job_id = job.id
  where job.created_by is distinct from evidence.actor_id;

  if v_pending_jobs > 0 then
    if not exists (
      select 1
      from pg_trigger trigger
      where trigger.tgrelid = 'public.mechanic_jobs'::regclass
        and trigger.tgname = 'trg_mechanic_jobs_updated_at'
        and not trigger.tgisinternal
        and trigger.tgenabled = 'O'
    ) then
      raise exception 'Canonical mechanic_jobs updated_at trigger is not enabled as expected.'
        using errcode = '23514';
    end if;

    execute 'alter table public.mechanic_jobs disable trigger trg_mechanic_jobs_updated_at';

    update public.mechanic_jobs job
    set created_by = evidence.actor_id
    from pg_temp.recent_mechanic_job_actor_evidence evidence
    where job.id = evidence.job_id
      and job.tenant_id = v_tenant_id
      and job.created_by is distinct from evidence.actor_id;

    get diagnostics v_rows = row_count;

    execute 'alter table public.mechanic_jobs enable trigger trg_mechanic_jobs_updated_at';

    if v_rows <> v_pending_jobs then
      raise exception 'Recent job actor backfill updated % jobs instead of %.',
        v_rows, v_pending_jobs using errcode = '23514';
    end if;
  end if;

  select count(*)::integer
  into v_pending_notifications
  from public.erp_notifications notification
  join pg_temp.recent_mechanic_job_actor_evidence evidence
    on evidence.notification_id = notification.id
  where notification.data is distinct from
    coalesce(notification.data, '{}'::jsonb) || jsonb_build_object(
      'recorded_by_name', evidence.actor_name,
      'recorded_by_evidence_source', 'supabase_edge_log',
      'recorded_by_evidence_log_id', evidence.edge_log_id::text,
      'recorded_by_evidence_at', to_char(
        evidence.edge_log_at at time zone 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
      ),
      'recorded_by_backfill', v_migration
    );

  update public.erp_notifications notification
  set data = coalesce(notification.data, '{}'::jsonb) || jsonb_build_object(
    'recorded_by_name', evidence.actor_name,
    'recorded_by_evidence_source', 'supabase_edge_log',
    'recorded_by_evidence_log_id', evidence.edge_log_id::text,
    'recorded_by_evidence_at', to_char(
      evidence.edge_log_at at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    ),
    'recorded_by_backfill', v_migration
  )
  from pg_temp.recent_mechanic_job_actor_evidence evidence
  where notification.id = evidence.notification_id
    and notification.tenant_id = v_tenant_id
    and notification.data is distinct from
      coalesce(notification.data, '{}'::jsonb) || jsonb_build_object(
        'recorded_by_name', evidence.actor_name,
        'recorded_by_evidence_source', 'supabase_edge_log',
        'recorded_by_evidence_log_id', evidence.edge_log_id::text,
        'recorded_by_evidence_at', to_char(
          evidence.edge_log_at at time zone 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
        ),
        'recorded_by_backfill', v_migration
      );

  get diagnostics v_rows = row_count;
  if v_rows <> v_pending_notifications then
    raise exception 'Recent job actor backfill updated % notifications instead of %.',
      v_rows, v_pending_notifications using errcode = '23514';
  end if;

  -- Compare the complete protected job row and notification envelope/data
  -- after the update. Any trigger side effect outside the authorized fields
  -- aborts the transaction.
  if (
    select count(*)
    from pg_temp.recent_mechanic_job_actor_before before_state
  ) <> v_expected_count or exists (
    select 1
    from pg_temp.recent_mechanic_job_actor_before before_state
    join public.mechanic_jobs job
      on job.id = before_state.job_id
    join pg_temp.recent_mechanic_job_actor_evidence evidence
      on evidence.job_id = job.id
    join public.erp_notifications notification
      on notification.id = evidence.notification_id
    where to_jsonb(job) - 'created_by'
            is distinct from before_state.job_preserved
       or to_jsonb(notification) - array['data', 'updated_at']::text[]
            is distinct from before_state.notification_preserved
       or coalesce(notification.data, '{}'::jsonb) - array[
            'recorded_by_name',
            'recorded_by_evidence_source',
            'recorded_by_evidence_log_id',
            'recorded_by_evidence_at',
            'recorded_by_backfill'
          ]::text[] is distinct from before_state.notification_data_preserved
       or (
         not before_state.notification_was_pending
         and notification.updated_at is distinct from
           before_state.notification_updated_at
       )
       or (
         before_state.notification_was_pending
         and notification.updated_at <= before_state.notification_updated_at
       )
  ) then
    raise exception 'Recent job actor backfill changed a protected job or notification field.'
      using errcode = '23514';
  end if;

  if (
    select count(*)
    from public.mechanic_jobs job
    join pg_temp.recent_mechanic_job_actor_evidence evidence
      on evidence.job_id = job.id
    join public.erp_notifications notification
      on notification.id = evidence.notification_id
    where job.tenant_id = v_tenant_id
      and job.created_by = evidence.actor_id
      and notification.tenant_id = v_tenant_id
      and notification.data->>'recorded_by_name' = evidence.actor_name
      and notification.data->>'recorded_by_evidence_source' =
        'supabase_edge_log'
      and notification.data->>'recorded_by_evidence_log_id' =
        evidence.edge_log_id::text
      and notification.data->>'recorded_by_evidence_at' = to_char(
        evidence.edge_log_at at time zone 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
      )
      and notification.data->>'recorded_by_backfill' = v_migration
  ) <> v_expected_count then
    raise exception 'Recent job actor final invariant failed.'
      using errcode = '23514';
  end if;
end;
$backfill$;

commit;
