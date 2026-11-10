-- Read-back for 20261110060000_meta_contact_names. Plain SQL; it fails with
-- «division by zero» when an invariant is missing.

-- Diagnosis: the state the assertions below judge.
select
  to_regprocedure('public.claim_meta_contact_profiles_due(text,text,integer)') is not null
    as claim_exists,
  to_regprocedure('public.record_meta_contact_profile(uuid,text,text,text,boolean)') is not null
    as record_exists,
  to_regprocedure('public.meta_contact_display_name(text,text)') is not null
    as display_name_exists,
  (
    select count(*) from information_schema.columns
    where table_schema = 'public'
      and table_name = 'meta_conversation_bindings'
      and column_name in ('profile_checked_at', 'profile_error')
  ) as profile_columns,
  (
    select prosrc like '%meta_contact_display_name%'
    from pg_proc
    where oid = to_regprocedure(
      'public.ensure_meta_conversation_binding(uuid,text,text,text)'
    )
  ) as reopened_conversation_keeps_name,
  (
    select md5(prosrc) = 'd7db1f59a4c49ad098523008fda8f478'
    from pg_proc
    where oid = to_regprocedure(
      'public.ingest_meta_message(text,text,text,text,text,text,text,text,text,timestamp with time zone,jsonb)'
    )
  ) as ingest_untouched;

-- Diagnosis: how many contacts of the tenant the webhook would ask Meta about.
select
  channel.provider,
  count(*) as contactos,
  count(*) filter (
    where nullif(btrim(binding.contact_name), '') is null
      and nullif(btrim(binding.username), '') is null
  ) as sin_nombre
from public.meta_conversation_bindings binding
join public.meta_channels channel
  on channel.id = binding.channel_id
 and channel.tenant_id = binding.tenant_id
where binding.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
group by channel.provider;

-- The pieces exist, with the signatures the webhook calls.
select 1 / (
  case when
    to_regprocedure('public.claim_meta_contact_profiles_due(text,text,integer)') is not null
    and to_regprocedure('public.record_meta_contact_profile(uuid,text,text,text,boolean)') is not null
    and to_regprocedure('public.meta_contact_display_name(text,text)') is not null
    and to_regprocedure('public.meta_contact_fallback_label(text,text)') is not null
    and (
      select count(*) = 2 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'meta_conversation_bindings'
        and column_name in ('profile_checked_at', 'profile_error')
    )
  then 1 else 0 end
) as contact_profile_pieces_exist;

-- Only the server may claim or record a contact profile.
select 1 / (
  case when
    has_function_privilege(
      'service_role',
      to_regprocedure('public.claim_meta_contact_profiles_due(text,text,integer)'),
      'execute'
    )
    and has_function_privilege(
      'service_role',
      to_regprocedure('public.record_meta_contact_profile(uuid,text,text,text,boolean)'),
      'execute'
    )
    and not has_function_privilege(
      'authenticated',
      to_regprocedure('public.claim_meta_contact_profiles_due(text,text,integer)'),
      'execute'
    )
    and not has_function_privilege(
      'authenticated',
      to_regprocedure('public.record_meta_contact_profile(uuid,text,text,text,boolean)'),
      'execute'
    )
    and not has_function_privilege(
      'anon',
      to_regprocedure('public.record_meta_contact_profile(uuid,text,text,text,boolean)'),
      'execute'
    )
  then 1 else 0 end
) as contact_profiles_are_server_only;

-- A reopened conversation keeps the contact's name, and message ingestion is
-- the function it was: message metadata stays pseudonymous.
select 1 / (
  case when (
    select prosrc like '%meta_contact_display_name%'
    from pg_proc
    where oid = to_regprocedure(
      'public.ensure_meta_conversation_binding(uuid,text,text,text)'
    )
  ) and (
    select md5(prosrc) = 'd7db1f59a4c49ad098523008fda8f478'
    from pg_proc
    where oid = to_regprocedure(
      'public.ingest_meta_message(text,text,text,text,text,text,text,text,text,timestamp with time zone,jsonb)'
    )
  ) then 1 else 0 end
) as titles_follow_the_name_and_ingest_is_untouched;

-- No message of the tenant carries a Meta name, username or raw id.
select 1 / (
  case when not exists (
    select 1
    from public.messages message
    where message.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and message.external_provider in ('instagram', 'facebook_messenger')
      and message.message_direction = 'inbound'
      and message.metadata ?| array[
        'external_account_id', 'external_user_id', 'contact_name', 'username'
      ]
  ) then 1 else 0 end
) as message_metadata_stays_pseudonymous;
