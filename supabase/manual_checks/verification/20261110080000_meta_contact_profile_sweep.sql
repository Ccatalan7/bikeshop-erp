-- Read-back for 20261110080000_meta_contact_profile_sweep. Plain SQL; it fails
-- with «division by zero» when an invariant is missing.

-- Diagnosis: the state the assertions below judge.
select
  to_regclass('public.meta_contact_profile_runtime') is not null as runtime_exists,
  to_regclass('public.meta_contact_profile_sweeps') is not null as tickets_exist,
  to_regprocedure('public.dispatch_meta_contact_profile_sweeps()') is not null
    as dispatch_exists,
  to_regprocedure('public.redeem_meta_contact_profile_sweep(uuid,text)') is not null
    as redeem_exists,
  to_regprocedure(
    'public.meta_contact_profile_due(text,text,timestamp with time zone)'
  ) is not null as due_rule_exists,
  (
    select count(*) from cron.job job
    where job.jobname = 'vinabike_meta_contact_profiles' and job.active
  ) as active_schedules;

-- Diagnosis: who the next run would ask Meta about, per provider.
select
  channel.provider,
  count(*) as contactos,
  count(*) filter (
    where nullif(btrim(binding.contact_name), '') is null
      and nullif(btrim(binding.username), '') is null
  ) as sin_nombre,
  count(*) filter (where binding.profile_checked_at is not null) as consultados
from public.meta_conversation_bindings binding
join public.meta_channels channel
  on channel.id = binding.channel_id
 and channel.tenant_id = binding.tenant_id
where binding.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
group by channel.provider;

-- The pieces exist, with the signatures the function calls.
select 1 / (
  case when
    to_regclass('public.meta_contact_profile_runtime') is not null
    and to_regclass('public.meta_contact_profile_sweeps') is not null
    and to_regprocedure('public.dispatch_meta_contact_profile_sweeps()') is not null
    and to_regprocedure('public.redeem_meta_contact_profile_sweep(uuid,text)') is not null
    and to_regprocedure(
      'public.meta_contact_profile_due(text,text,timestamp with time zone)'
    ) is not null
  then 1 else 0 end
) as sweep_pieces_exist;

-- Tickets and the switch are private, and only the server dispatches or redeems.
select 1 / (
  case when
    (
      select count(*) = 2
      from pg_class relation
      where relation.oid in (
        to_regclass('public.meta_contact_profile_runtime'),
        to_regclass('public.meta_contact_profile_sweeps')
      )
        and relation.relrowsecurity
        and not has_table_privilege('authenticated', relation.oid, 'select')
        and not has_table_privilege('authenticated', relation.oid, 'insert')
        and not has_table_privilege('authenticated', relation.oid, 'update')
        and not has_table_privilege('anon', relation.oid, 'select')
        and not has_table_privilege('anon', relation.oid, 'insert')
    )
    and (
      select count(*) = 2
      from pg_proc routine
      where routine.oid in (
        to_regprocedure('public.dispatch_meta_contact_profile_sweeps()'),
        to_regprocedure('public.redeem_meta_contact_profile_sweep(uuid,text)')
      )
        and routine.prosecdef
        and has_function_privilege('service_role', routine.oid, 'execute')
        and not has_function_privilege('authenticated', routine.oid, 'execute')
        and not has_function_privilege('anon', routine.oid, 'execute')
    )
  then 1 else 0 end
) as sweep_is_server_only;

-- A ticket is hashed, single use and bound to its channel; who is due is one
-- rule, shared with the webhook's claim; and message ingestion is untouched.
select 1 / (
  case when (
    select routine.prosrc like '%extensions.digest(v_token, ''sha256'')%'
      and routine.prosrc like '%meta_contact_profile_due(%'
      and routine.prosrc like '%net.http_post(%'
    from pg_proc routine
    where routine.oid = to_regprocedure('public.dispatch_meta_contact_profile_sweeps()')
  ) and (
    select routine.prosrc like '%delete from public.meta_contact_profile_sweeps%'
      and routine.prosrc like '%sweep.lease_until > clock_timestamp()%'
      and routine.prosrc like '%sweep.token_hash%'
      and routine.prosrc like '%sweep.channel_id = p_channel_id%'
    from pg_proc routine
    where routine.oid = to_regprocedure('public.redeem_meta_contact_profile_sweep(uuid,text)')
  ) and (
    select routine.prosrc like '%meta_contact_profile_due(%'
    from pg_proc routine
    where routine.oid = to_regprocedure(
      'public.claim_meta_contact_profiles_due(text,text,integer)'
    )
  ) and (
    select md5(routine.prosrc) = 'd7db1f59a4c49ad098523008fda8f478'
    from pg_proc routine
    where routine.oid = to_regprocedure(
      'public.ingest_meta_message(text,text,text,text,text,text,text,text,text,timestamp with time zone,jsonb)'
    )
  ) then 1 else 0 end
) as ticket_is_fenced_and_due_rule_is_shared;

-- The claim kept its privileges through the redefinition.
select 1 / (
  case when
    has_function_privilege(
      'service_role',
      to_regprocedure('public.claim_meta_contact_profiles_due(text,text,integer)'),
      'execute'
    )
    and not has_function_privilege(
      'authenticated',
      to_regprocedure('public.claim_meta_contact_profiles_due(text,text,integer)'),
      'execute'
    )
    and not has_function_privilege(
      'anon',
      to_regprocedure('public.claim_meta_contact_profiles_due(text,text,integer)'),
      'execute'
    )
  then 1 else 0 end
) as claim_is_still_server_only;

-- It runs on its schedule, against the function that asks Meta.
select 1 / count(*)::integer as scheduler_active
from cron.job job
where job.jobname = 'vinabike_meta_contact_profiles'
  and job.active
  and job.schedule = '7,22,37,52 * * * *'
  and job.command = 'select public.dispatch_meta_contact_profile_sweeps();';

select 1 / (
  case when to_regclass('public.meta_contact_profile_runtime') is not null
  then 1 else 0 end
) as runtime_table_exists;

select 1 / count(*)::integer as sweep_runtime
from public.meta_contact_profile_runtime runtime
where runtime.singleton
  and runtime.enabled
  and runtime.endpoint
    = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/meta-contact-profiles';
