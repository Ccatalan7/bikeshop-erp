-- Read-back for 20261110100000_meta_message_media. Plain SQL; it fails with
-- «division by zero» when an invariant is missing.

-- Diagnosis: the state the assertions below judge.
select
  (
    select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'meta_webhook_events'
      and column_name in (
        'media_attached_at', 'media_checked_at', 'media_attempts', 'media_error'
      )
  ) as media_columns,
  to_regclass('public.meta_channel_sweep_runtime') is not null as runtime_exists,
  to_regclass('public.meta_channel_sweep_tickets') is not null as tickets_exist,
  to_regclass('public.meta_contact_profile_sweeps') is null as old_tickets_gone,
  (
    select count(*) from cron.job job
    where job.jobname = 'vinabike_meta_channel_sweep' and job.active
  ) as active_schedules,
  (
    select count(*) from cron.job job
    where job.jobname = 'vinabike_meta_contact_profiles'
  ) as old_schedules;

-- Diagnosis: the inbound Meta messages of the tenant and their files.
select
  event.payload->>'message_type' as tipo,
  count(*) as mensajes,
  count(*) filter (where event.media_attached_at is not null) as con_archivo,
  count(*) filter (where public.meta_message_media_due(event)) as pendientes
from public.meta_webhook_events event
where event.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and event.event_type = 'message'
  and event.direction = 'inbound'
group by 1
order by 1;

-- The pieces exist, with the signatures the functions call.
select 1 / (
  case when
    (
      select count(*) = 4 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'meta_webhook_events'
        and column_name in (
          'media_attached_at', 'media_checked_at', 'media_attempts', 'media_error'
        )
    )
    and to_regprocedure('public.meta_message_media_due(public.meta_webhook_events)') is not null
    and to_regprocedure('public.claim_meta_message_media_due(text,text,integer)') is not null
    and to_regprocedure('public.claim_meta_message_media(uuid)') is not null
    and to_regprocedure(
      'public.attach_meta_message_media(uuid,uuid,text,text,text,bigint,boolean,integer)'
    ) is not null
    and to_regprocedure('public.fail_meta_message_media(uuid,text,boolean)') is not null
    and to_regprocedure('public.dispatch_meta_channel_sweeps()') is not null
    and to_regprocedure('public.redeem_meta_channel_sweep_ticket(uuid,text)') is not null
    and to_regclass('public.meta_channel_sweep_runtime') is not null
    and to_regclass('public.meta_channel_sweep_tickets') is not null
  then 1 else 0 end
) as media_and_sweep_pieces_exist;

-- The sweep of 20261110080000 was replaced, not doubled.
select 1 / (
  case when
    to_regprocedure('public.dispatch_meta_contact_profile_sweeps()') is null
    and to_regprocedure('public.redeem_meta_contact_profile_sweep(uuid,text)') is null
    and to_regclass('public.meta_contact_profile_sweeps') is null
    and to_regclass('public.meta_contact_profile_runtime') is null
    and not exists (
      select 1 from cron.job job
      where job.jobname = 'vinabike_meta_contact_profiles'
    )
  then 1 else 0 end
) as previous_sweep_replaced;

-- Only the server claims, attaches, fails, dispatches or redeems.
select 1 / (
  case when (
    select count(*) = 6
    from pg_proc routine
    where routine.oid in (
      to_regprocedure('public.claim_meta_message_media_due(text,text,integer)'),
      to_regprocedure('public.claim_meta_message_media(uuid)'),
      to_regprocedure(
        'public.attach_meta_message_media(uuid,uuid,text,text,text,bigint,boolean,integer)'
      ),
      to_regprocedure('public.fail_meta_message_media(uuid,text,boolean)'),
      to_regprocedure('public.dispatch_meta_channel_sweeps()'),
      to_regprocedure('public.redeem_meta_channel_sweep_ticket(uuid,text)')
    )
      and routine.prosecdef
      and has_function_privilege('service_role', routine.oid, 'execute')
      and not has_function_privilege('authenticated', routine.oid, 'execute')
      and not has_function_privilege('anon', routine.oid, 'execute')
  ) and (
    select count(*) = 2
    from pg_class relation
    where relation.oid in (
      to_regclass('public.meta_channel_sweep_runtime'),
      to_regclass('public.meta_channel_sweep_tickets')
    )
      and relation.relrowsecurity
      and not has_table_privilege('authenticated', relation.oid, 'select')
      and not has_table_privilege('authenticated', relation.oid, 'update')
      and not has_table_privilege('anon', relation.oid, 'select')
  ) then 1 else 0 end
) as media_and_sweep_are_server_only;

-- A file is attached only after the stored object is read back, into the
-- registry, and the sweep wakes for files as well as for names; message
-- ingestion is untouched.
select 1 / (
  case when (
    select routine.prosrc like '%from storage.objects object%'
      and routine.prosrc like '%insert into public.messaging_attachments%'
      and routine.prosrc like '%''private_signed_runtime''%'
      and routine.prosrc like '%v_object_size is distinct from p_size_bytes%'
    from pg_proc routine
    where routine.oid = to_regprocedure(
      'public.attach_meta_message_media(uuid,uuid,text,text,text,bigint,boolean,integer)'
    )
  ) and (
    select routine.prosrc like '%meta_contact_profile_due(%'
      and routine.prosrc like '%meta_message_media_due(%'
      and routine.prosrc like '%extensions.digest(v_token, ''sha256'')%'
    from pg_proc routine
    where routine.oid = to_regprocedure('public.dispatch_meta_channel_sweeps()')
  ) and (
    select md5(routine.prosrc) = 'd7db1f59a4c49ad098523008fda8f478'
    from pg_proc routine
    where routine.oid = to_regprocedure(
      'public.ingest_meta_message(text,text,text,text,text,text,text,text,text,timestamp with time zone,jsonb)'
    )
  ) then 1 else 0 end
) as files_are_read_back_and_ingest_is_untouched;

-- It runs on its schedule, against the function that sweeps.
select 1 / count(*)::integer as scheduler_active
from cron.job job
where job.jobname = 'vinabike_meta_channel_sweep'
  and job.active
  and job.schedule = '7,22,37,52 * * * *'
  and job.command = 'select public.dispatch_meta_channel_sweeps();';

select 1 / (
  case when to_regclass('public.meta_channel_sweep_runtime') is not null
  then 1 else 0 end
) as runtime_table_exists;

select 1 / count(*)::integer as sweep_runtime
from public.meta_channel_sweep_runtime runtime
where runtime.singleton
  and runtime.enabled
  and runtime.endpoint
    = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/meta-channel-sweep';

-- No message of the tenant carries a Meta URL, name or raw id.
select 1 / (
  case when not exists (
    select 1
    from public.messages message
    where message.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and message.external_provider in ('instagram', 'facebook_messenger')
      and message.message_direction = 'inbound'
      and (
        message.metadata ?| array[
          'external_account_id', 'external_user_id', 'contact_name', 'username',
          'url', 'media_url', 'image_url', 'file_url'
        ]
        or message.metadata::text ~ '(fbsbx|fbcdn|cdninstagram)'
      )
  ) then 1 else 0 end
) as message_metadata_carries_no_meta_url;
