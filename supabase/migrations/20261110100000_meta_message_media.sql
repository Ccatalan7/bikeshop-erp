-- A photo sent by Instagram or Messenger showed as the words «Imagen
-- recibida» (owner, 2026-11-10: «la imagen no llegó»). Since 2026-07-22 the
-- integration kept only a text placeholder for remote media
-- (`ingest_meta_message`: «not hydrated … in this MVP»), so no file ever
-- reached the ERP.
--
-- From here the file is downloaded on the server into the private attachment
-- registry, like a WhatsApp file, and the message becomes the image or file
-- bubble every app version already draws:
-- - when the message arrives, the webhook downloads it from the URL Meta
--   sends with the event;
-- - a schedule recovers the ones that were missed or arrived before this
--   existed, asking Meta for the message by its id.
-- The remote URL is never stored. What is kept is on the service-only event
-- row: when the file was attached, how many times it was tried and why not.
--
-- The schedule is the one 20261110080000 made for contact names. It now does
-- both jobs for a channel, so its pieces take the name of what they are: a
-- sweep of a Meta channel. Nothing but that migration, two hours old, used
-- the previous names.

alter table public.meta_webhook_events
  add column if not exists media_attached_at timestamptz,
  add column if not exists media_checked_at timestamptz,
  add column if not exists media_attempts integer not null default 0,
  add column if not exists media_error text;

comment on column public.meta_webhook_events.media_attached_at is
  'When the file of this inbound message was stored and attached. Null: not yet, or the message has no file.';
comment on column public.meta_webhook_events.media_checked_at is
  'Last attempt to fetch the file. Null: try on the next run.';
comment on column public.meta_webhook_events.media_attempts is
  'Attempts to fetch the file. After 8 the message keeps its placeholder.';
comment on column public.meta_webhook_events.media_error is
  'Why the last attempt stored no file (a short code, never a URL or a message).';

-- Who is due: an inbound message with a storable file that has none yet, was
-- not tried in the last day and has tries left. At this volume (25 inbound
-- messages in four months) the channel index is enough; no index of its own.
create or replace function public.meta_message_media_due(
  p_event public.meta_webhook_events
)
returns boolean
language sql
set search_path = public, pg_temp
as $$
  select p_event.event_type = 'message'
    and p_event.direction = 'inbound'
    and p_event.message_id is not null
    and nullif(btrim(p_event.external_message_id), '') is not null
    and (p_event.payload->>'message_type') in ('image', 'video', 'audio', 'file')
    and p_event.media_attached_at is null
    and p_event.media_attempts < 8
    and (
      p_event.media_checked_at is null
      or p_event.media_checked_at < clock_timestamp() - interval '24 hours'
    );
$$;

comment on function public.meta_message_media_due(public.meta_webhook_events) is
  'An inbound Meta message is due for its file: storable type, none attached, not tried in the last day, tries left.';

-- What a claim hands to the function that downloads: the message that will
-- own the file, and Meta's id for it. Service only.
create or replace function public.meta_message_media_claim_item(
  p_event public.meta_webhook_events
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'message_id', message.id,
    'tenant_id', message.tenant_id,
    'conversation_id', message.conversation_id,
    'external_message_id', p_event.external_message_id,
    'media_type', p_event.payload->>'message_type'
  )
  from public.messages message
  where message.id = p_event.message_id
    and message.tenant_id = p_event.tenant_id;
$$;

create or replace function public.claim_meta_message_media_due(
  p_provider text,
  p_external_account_id text,
  p_limit integer default 3
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_channel public.meta_channels%rowtype;
  v_messages jsonb;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta message media claims require service role'
      using errcode = '42501';
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.provider = v_provider
    and channel.external_account_id = btrim(coalesce(p_external_account_id, ''))
    and channel.is_active;
  if not found then
    return jsonb_build_object('channel_id', null, 'messages', '[]'::jsonb);
  end if;

  -- Claiming stamps the attempt, so two runs never fetch the same file.
  with due as (
    select event.id
    from public.meta_webhook_events event
    where event.channel_id = v_channel.id
      and event.tenant_id = v_channel.tenant_id
      and public.meta_message_media_due(event)
    order by event.occurred_at desc nulls last, event.created_at desc
    limit greatest(1, least(coalesce(p_limit, 3), 10))
    for update skip locked
  ), claimed as (
    update public.meta_webhook_events event
    set media_checked_at = clock_timestamp(),
        media_attempts = event.media_attempts + 1
    from due
    where event.id = due.id
    returning event as claimed_event
  )
  select coalesce(
    jsonb_agg(public.meta_message_media_claim_item(claimed.claimed_event)),
    '[]'::jsonb
  ) into v_messages
  from claimed
  where public.meta_message_media_claim_item(claimed.claimed_event) is not null;

  return jsonb_build_object(
    'channel_id', v_channel.id,
    'provider', v_channel.provider,
    'messages', v_messages
  );
end;
$$;

comment on function public.claim_meta_message_media_due(text, text, integer) is
  'Service only: claims the inbound messages of a Meta account whose file is due, and stamps the attempt.';

-- The webhook claims the message it just stored before it downloads, so the
-- schedule does not fetch the same file meanwhile.
create or replace function public.claim_meta_message_media(p_message_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_event public.meta_webhook_events%rowtype;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta message media claims require service role'
      using errcode = '42501';
  end if;

  update public.meta_webhook_events event
  set media_checked_at = clock_timestamp(),
      media_attempts = event.media_attempts + 1
  where event.id = (
    select candidate.id
    from public.meta_webhook_events candidate
    where candidate.message_id = p_message_id
      and public.meta_message_media_due(candidate)
    order by candidate.created_at
    limit 1
    for update skip locked
  )
  returning event.* into v_event;
  if not found then
    return null;
  end if;

  return public.meta_message_media_claim_item(v_event);
end;
$$;

comment on function public.claim_meta_message_media(uuid) is
  'Service only: claims one inbound Meta message for its file. Null when it is not due.';

-- The file is uploaded first; this registers it and turns the message into
-- its bubble in one transaction, after reading the stored object back. The
-- message never points at a file that is not there, and never at a URL.
create or replace function public.attach_meta_message_media(
  p_message_id uuid,
  p_attachment_id uuid,
  p_original_filename text,
  p_extension text,
  p_declared_mime_type text,
  p_size_bytes bigint,
  p_has_playback_twin boolean default false,
  p_more_files integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_message public.messages%rowtype;
  v_extension text := lower(btrim(coalesce(p_extension, '')));
  v_mime text := lower(btrim(coalesce(p_declared_mime_type, '')));
  v_filename text := left(nullif(btrim(coalesce(p_original_filename, '')), ''), 200);
  v_path text;
  v_object_metadata jsonb;
  v_object_size bigint;
  v_object_mime text;
  v_reference jsonb;
  v_more_files integer := greatest(coalesce(p_more_files, 0), 0);
begin
  if v_role <> 'service_role' then
    raise exception 'Meta message media requires service role'
      using errcode = '42501';
  end if;
  if p_message_id is null or p_attachment_id is null or v_filename is null then
    raise exception 'Meta message media needs its message, id and filename'
      using errcode = '22023';
  end if;

  select message.* into v_message
  from public.messages message
  where message.id = p_message_id
  for update;
  if not found
     or coalesce(v_message.external_provider, '')
       not in ('instagram', 'facebook_messenger')
     or v_message.message_direction is distinct from 'inbound' then
    raise exception 'Not an inbound Meta message' using errcode = 'P0002';
  end if;

  -- One file per message: whoever attached first keeps it.
  if exists (
    select 1
    from public.messaging_attachments attachment
    where attachment.message_id = v_message.id
  ) then
    update public.meta_webhook_events event
    set media_attached_at = coalesce(event.media_attached_at, clock_timestamp()),
        media_error = null
    where event.message_id = v_message.id
      and event.tenant_id = v_message.tenant_id;
    return jsonb_build_object('attached', false, 'reason', 'already_attached');
  end if;

  v_path := v_message.tenant_id::text || '/' || v_message.conversation_id::text
    || '/' || p_attachment_id::text || '.' || v_extension;

  select coalesce(object.metadata, '{}'::jsonb)
  into v_object_metadata
  from storage.objects object
  where object.bucket_id = 'chat-attachments'
    and object.name = v_path;
  if not found then
    raise exception 'Private object readback is missing' using errcode = 'P0002';
  end if;

  begin
    v_object_size := nullif(v_object_metadata->>'size', '')::bigint;
  exception when invalid_text_representation then
    v_object_size := null;
  end;
  v_object_mime := lower(split_part(coalesce(
    nullif(v_object_metadata->>'mimetype', ''),
    nullif(v_object_metadata->>'contentType', ''),
    ''
  ), ';', 1));
  if v_object_size is distinct from p_size_bytes
     or v_object_mime is distinct from v_mime then
    raise exception 'Private object does not match what was declared'
      using errcode = '23514';
  end if;

  -- The registry's own checks judge the type, the extension and the size.
  insert into public.messaging_attachments (
    id, tenant_id, conversation_id, message_id, storage_bucket, storage_path,
    original_filename, extension, declared_mime_type, size_bytes, status,
    created_by, attached_at
  ) values (
    p_attachment_id, v_message.tenant_id, v_message.conversation_id,
    v_message.id, 'chat-attachments', v_path, v_filename, v_extension, v_mime,
    p_size_bytes, 'attached', null, clock_timestamp()
  );

  v_reference := jsonb_build_object(
    'attachment_id', p_attachment_id,
    'storage_bucket', 'chat-attachments',
    'storage_path', v_path,
    'filename', v_filename,
    'extension', v_extension,
    'content_type', v_mime,
    'size_bytes', p_size_bytes,
    'attachment_access', 'private_signed_runtime'
  );
  -- A voice note's WAV twin, when the function made one and it is there.
  if coalesce(p_has_playback_twin, false) and exists (
    select 1
    from storage.objects object
    where object.bucket_id = 'chat-attachments'
      and object.name = v_path || '.wav'
  ) then
    v_reference := v_reference || jsonb_build_object(
      'playback_storage_path', v_path || '.wav',
      'playback_content_type', 'audio/wav'
    );
  end if;

  -- A message holds one file. When Meta sent several in one message, the
  -- first is kept and the bubble says so, instead of dropping the rest in
  -- silence.
  if v_more_files > 0 then
    v_reference := v_reference || jsonb_build_object(
      'caption',
      'Llegaron ' || (v_more_files + 1) || ' archivos en este mensaje. '
        || 'Este es el primero; el resto se ve en '
        || (case
          when v_message.external_provider = 'instagram' then 'Instagram'
          else 'Messenger'
        end) || '.'
    );
  end if;

  -- The same types a WhatsApp file gets: a picture is `image`, the rest `file`.
  update public.messages message
  set type = case when v_mime like 'image/%' then 'image' else 'file' end,
      metadata = (coalesce(message.metadata, '{}'::jsonb) - 'media_placeholder')
        || v_reference
  where message.id = v_message.id;

  update public.meta_webhook_events event
  set media_attached_at = clock_timestamp(),
      media_error = null
  where event.message_id = v_message.id
    and event.tenant_id = v_message.tenant_id;

  return jsonb_build_object(
    'attached', true,
    'message_id', v_message.id,
    'attachment_id', p_attachment_id
  );
end;
$$;

comment on function public.attach_meta_message_media(uuid, uuid, text, text, text, bigint, boolean, integer) is
  'Service only: registers an uploaded file for an inbound Meta message and turns the message into its image or file bubble, in one transaction.';

create or replace function public.fail_meta_message_media(
  p_message_id uuid,
  p_error text,
  p_retry_soon boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
begin
  if v_role <> 'service_role' then
    raise exception 'Meta message media requires service role'
      using errcode = '42501';
  end if;

  -- An outage is tried again on the next run; a refusal waits a day. Both
  -- count against the same eight tries, so nothing is asked for ever.
  update public.meta_webhook_events event
  set media_error = left(coalesce(nullif(btrim(p_error), ''), 'unknown'), 120),
      media_checked_at = case
        when coalesce(p_retry_soon, false) then null
        else clock_timestamp()
      end
  where event.message_id = p_message_id
    and event.event_type = 'message'
    and event.direction = 'inbound'
    and event.media_attached_at is null;
  return found;
end;
$$;

comment on function public.fail_meta_message_media(uuid, text, boolean) is
  'Service only: records why an inbound Meta message got no file, and whether to try again soon.';

revoke all on function public.meta_message_media_due(public.meta_webhook_events)
  from public, anon, authenticated;
revoke all on function public.meta_message_media_claim_item(public.meta_webhook_events)
  from public, anon, authenticated;
revoke all on function public.claim_meta_message_media_due(text, text, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_meta_message_media(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.attach_meta_message_media(uuid, uuid, text, text, text, bigint, boolean, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.fail_meta_message_media(uuid, text, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.meta_message_media_due(public.meta_webhook_events)
  to service_role;
grant execute on function public.meta_message_media_claim_item(public.meta_webhook_events)
  to service_role;
grant execute on function public.claim_meta_message_media_due(text, text, integer)
  to service_role;
grant execute on function public.claim_meta_message_media(uuid)
  to service_role;
grant execute on function public.attach_meta_message_media(uuid, uuid, text, text, text, bigint, boolean, integer)
  to service_role;
grant execute on function public.fail_meta_message_media(uuid, text, boolean)
  to service_role;

-- The schedule of 20261110080000 becomes the sweep of a Meta channel: one
-- ticket opens both jobs, contact names and message files.
select cron.unschedule(job.jobid)
from cron.job job
where job.jobname = 'vinabike_meta_contact_profiles';

drop function if exists public.dispatch_meta_contact_profile_sweeps();
drop function if exists public.redeem_meta_contact_profile_sweep(uuid, text);
-- Both held only a switch and tickets that live two minutes.
drop table if exists public.meta_contact_profile_sweeps;
drop table if exists public.meta_contact_profile_runtime;

create table if not exists public.meta_channel_sweep_runtime (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default true,
  endpoint text not null
    check (endpoint ~ '^https://[^/]+/functions/v1/meta-channel-sweep$')
);
insert into public.meta_channel_sweep_runtime (singleton, endpoint)
values (
  true,
  'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/meta-channel-sweep'
)
on conflict (singleton) do nothing;
alter table public.meta_channel_sweep_runtime enable row level security;
revoke all on public.meta_channel_sweep_runtime from public, anon, authenticated;
grant all on public.meta_channel_sweep_runtime to service_role;

comment on table public.meta_channel_sweep_runtime is
  'Private switch and endpoint of the scheduled sweep of Meta channels (contact names and message files).';

-- The ticket of a channel's pending sweep: one row per channel, replaced by
-- the next dispatch and deleted when redeemed. Only its hash is kept.
create table if not exists public.meta_channel_sweep_tickets (
  channel_id uuid primary key
    references public.meta_channels(id) on delete cascade,
  tenant_id uuid not null
    references public.tenants(id) on delete cascade,
  token_hash text not null,
  lease_until timestamptz not null,
  dispatched_at timestamptz not null default clock_timestamp()
);
alter table public.meta_channel_sweep_tickets enable row level security;
revoke all on public.meta_channel_sweep_tickets from public, anon, authenticated;
grant all on public.meta_channel_sweep_tickets to service_role;

comment on table public.meta_channel_sweep_tickets is
  'Private single-use tickets of the scheduled sweep of Meta channels. The token is never stored, only its hash.';

create or replace function public.dispatch_meta_channel_sweeps()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_endpoint text;
  v_channel record;
  v_token text;
  v_count integer := 0;
begin
  select runtime.endpoint into v_endpoint
  from public.meta_channel_sweep_runtime runtime
  where runtime.singleton and runtime.enabled;
  if v_endpoint is null then
    return 0;
  end if;

  -- Nothing is posted for a channel with nothing due, or with a ticket still
  -- out: a quiet account costs two reads per run and no request.
  for v_channel in
    select channel.id, channel.tenant_id
    from public.meta_channels channel
    where channel.is_active
      and (
        exists (
          select 1
          from public.meta_conversation_bindings binding
          where binding.channel_id = channel.id
            and binding.tenant_id = channel.tenant_id
            and public.meta_contact_profile_due(
              binding.contact_name, binding.username, binding.profile_checked_at
            )
        )
        or exists (
          select 1
          from public.meta_webhook_events event
          where event.channel_id = channel.id
            and event.tenant_id = channel.tenant_id
            and public.meta_message_media_due(event)
        )
      )
      and not exists (
        select 1
        from public.meta_channel_sweep_tickets ticket
        where ticket.channel_id = channel.id
          and ticket.lease_until > clock_timestamp()
      )
    order by channel.id
    limit 20
  loop
    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.meta_channel_sweep_tickets as ticket (
      channel_id, tenant_id, token_hash, lease_until, dispatched_at
    ) values (
      v_channel.id,
      v_channel.tenant_id,
      encode(extensions.digest(v_token, 'sha256'), 'hex'),
      clock_timestamp() + interval '2 minutes',
      clock_timestamp()
    )
    on conflict (channel_id) do update
    set tenant_id = excluded.tenant_id,
        token_hash = excluded.token_hash,
        lease_until = excluded.lease_until,
        dispatched_at = excluded.dispatched_at;
    perform net.http_post(
      url := v_endpoint,
      headers := '{"Content-Type":"application/json","x-region":"sa-east-1"}'::jsonb,
      body := jsonb_build_object('channel_id', v_channel.id, 'token', v_token),
      timeout_milliseconds := 120000
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

comment on function public.dispatch_meta_channel_sweeps() is
  'Scheduled: posts a single-use ticket to meta-channel-sweep for each active Meta channel with contact names or message files due.';

create or replace function public.redeem_meta_channel_sweep_ticket(
  p_channel_id uuid,
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_tenant_id uuid;
  v_channel public.meta_channels%rowtype;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta channel sweeps require service role'
      using errcode = '42501';
  end if;

  -- Single use: the ticket is gone once it opens a sweep.
  delete from public.meta_channel_sweep_tickets ticket
  where ticket.channel_id = p_channel_id
    and ticket.lease_until > clock_timestamp()
    and ticket.token_hash
      = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
  returning ticket.tenant_id into v_tenant_id;
  if not found then
    return null;
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.id = p_channel_id
    and channel.tenant_id = v_tenant_id
    and channel.is_active;
  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'provider', v_channel.provider,
    'external_account_id', v_channel.external_account_id
  );
end;
$$;

comment on function public.redeem_meta_channel_sweep_ticket(uuid, text) is
  'Service only: exchanges a dispatched ticket for the Meta account to sweep. Null when the ticket is wrong, used or expired.';

revoke all on function public.dispatch_meta_channel_sweeps()
  from public, anon, authenticated, service_role;
revoke all on function public.redeem_meta_channel_sweep_ticket(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.dispatch_meta_channel_sweeps()
  to service_role;
grant execute on function public.redeem_meta_channel_sweep_ticket(uuid, text)
  to service_role;

-- Off the quarter hours other schedules use. A new message and a new contact
-- are still handled at once by the webhook; this covers what already existed,
-- the daily retry of a refusal and the quick retry of an outage.
select cron.schedule(
  'vinabike_meta_channel_sweep',
  '7,22,37,52 * * * *',
  'select public.dispatch_meta_channel_sweeps();'
);
