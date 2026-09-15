-- Acceptance is a database transaction; delivery never depends on the client
-- remaining open. Dispatch capabilities are random, short-lived and single-use.
begin;

alter table public.messages drop constraint messages_external_status_check;
alter table public.messages add constraint messages_external_status_check
  check (external_status in ('queued', 'accepted', 'sent', 'delivered', 'read', 'failed')
    or external_status is null);

create table if not exists public.whatsapp_outbox (
  message_id uuid primary key references public.messages(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id),
  actor_id uuid not null references auth.users(id),
  client_message_id text not null,
  request jsonb not null,
  request_hash text not null,
  state text not null default 'queued'
    check (state in ('queued', 'dispatched', 'processing', 'sending',
      'accepted', 'failed', 'outcome_unknown')),
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  lease_until timestamptz,
  token_hash text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, actor_id, client_message_id)
);
create index if not exists whatsapp_outbox_pending on public.whatsapp_outbox(available_at)
  where state in ('queued', 'dispatched', 'processing', 'sending');
alter table public.whatsapp_outbox enable row level security;
revoke all on public.whatsapp_outbox from public, anon, authenticated;
grant all on public.whatsapp_outbox to service_role;

create table if not exists public.whatsapp_outbox_runtime (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default true,
  endpoint text not null check (endpoint ~ '^https://[^/]+/functions/v1/whatsapp-deliver$')
);
insert into public.whatsapp_outbox_runtime(singleton, endpoint)
values (true, 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/whatsapp-deliver')
on conflict (singleton) do nothing;
alter table public.whatsapp_outbox_runtime enable row level security;
revoke all on public.whatsapp_outbox_runtime from public, anon, authenticated;
grant all on public.whatsapp_outbox_runtime to service_role;

create or replace function public.guard_whatsapp_outbox_message_v1()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(auth.role(), '') not in ('', 'service_role')
     and exists (select 1 from public.whatsapp_outbox where message_id = old.id)
     and (new.content, new.type, new.metadata, new.external_status,
       new.external_provider, new.external_message_id, new.message_direction)
       is distinct from (old.content, old.type, old.metadata, old.external_status,
       old.external_provider, old.external_message_id, old.message_direction) then
    raise exception 'Accepted WhatsApp messages are server-owned' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_whatsapp_outbox_message_v1() from public, anon, authenticated;
create or replace trigger trg_whatsapp_outbox_message_guard
before update on public.messages for each row
execute function public.guard_whatsapp_outbox_message_v1();

create or replace function public.recover_whatsapp_outbox_v1()
returns void language plpgsql security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  -- A request that might have reached Meta must NEVER be retried automatically.
  with expired as (
    update public.whatsapp_outbox
    set state = 'outcome_unknown', last_error = 'delivery_lease_expired',
        updated_at = now()
    where state = 'sending' and lease_until < now()
    returning message_id
  )
  update public.messages m
  set external_status = null,
      metadata = m.metadata || jsonb_build_object(
        'status', 'outcome_unknown', 'whatsapp_status', 'outcome_unknown',
        'pending', false, 'retry_disabled', true)
  from expired where m.id = expired.message_id
    and m.external_message_id is null;

  with exhausted as (
    update public.whatsapp_outbox
    set state = 'failed', last_error = 'worker_unavailable', updated_at = now()
    where state in ('dispatched', 'processing') and lease_until < now()
      and attempts >= 3
    returning message_id
  )
  update public.messages m set external_status = 'failed',
    metadata = m.metadata || jsonb_build_object(
      'status', 'failed', 'whatsapp_status', 'failed', 'pending', false,
      'external_error_message', 'No se pudo iniciar el envío. Inténtalo nuevamente.')
  from exhausted where m.id = exhausted.message_id;

  update public.whatsapp_outbox
  set state = 'queued', token_hash = null, lease_until = null,
      available_at = now(), updated_at = now()
  where state in ('dispatched', 'processing') and lease_until < now()
    and attempts < 3;
end;
$$;

create or replace function public.dispatch_whatsapp_outbox_v1()
returns integer language plpgsql security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_job public.whatsapp_outbox%rowtype;
  v_endpoint text;
  v_token text;
  v_count integer := 0;
begin
  -- Keep recovery out of the acceptance path: it locks old message rows and
  -- conversations, whereas dispatch only touches skip-locked queue intents.
  select endpoint into v_endpoint from public.whatsapp_outbox_runtime
  where singleton and enabled;
  if v_endpoint is null then return 0; end if;

  for v_job in
    select * from public.whatsapp_outbox
    where state = 'queued' and available_at <= now()
    order by available_at, created_at limit 20 for update skip locked
  loop
    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    update public.whatsapp_outbox
    set state = 'dispatched', attempts = attempts + 1,
        token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex'),
        lease_until = now() + interval '2 minutes', updated_at = now()
    where message_id = v_job.message_id;
    perform net.http_post(
      url := v_endpoint,
      headers := '{"Content-Type":"application/json","x-region":"sa-east-1"}'::jsonb,
      body := jsonb_build_object('message_id', v_job.message_id, 'token', v_token),
      timeout_milliseconds := 10000
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.enqueue_whatsapp_message_v1(p_request jsonb)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid := public.user_tenant_id();
  v_conversation uuid;
  v_channel public.whatsapp_channels%rowtype;
  v_job public.whatsapp_outbox%rowtype;
  v_message public.messages%rowtype;
  v_attachment public.messaging_attachments%rowtype;
  v_key text := nullif(btrim(p_request #>> '{metadata,client_message_id}'), '');
  v_hash text := encode(extensions.digest(p_request::text, 'sha256'), 'hex');
  v_phone text := public.normalize_whatsapp_phone(p_request->>'phoneNumber');
  v_type text := p_request->>'type';
  v_id uuid := gen_random_uuid();
  v_binding jsonb;
  v_metadata jsonb;
begin
  if not public.messaging_is_staff_in_tenant(v_tenant) then
    raise exception 'Active messaging staff required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_request) is distinct from 'object'
     or octet_length(p_request::text) > 65536
     or v_key is null or length(v_key) > 128
     or v_phone is null or v_phone !~ '^[0-9]{8,15}$'
     or v_type is null or v_type not in ('text', 'template', 'image', 'document', 'audio', 'interactive') then
    raise exception 'Invalid WhatsApp outbox request' using errcode = '22023';
  end if;
  v_conversation := (p_request->>'conversationId')::uuid;
  -- Serialize only the idempotency key, not every message in the conversation.
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text || ':' || v_key, 0));
  select * into v_job from public.whatsapp_outbox
  where tenant_id = v_tenant and actor_id = v_actor and client_message_id = v_key;
  if found then
    if v_job.request_hash <> v_hash then
      raise exception 'Idempotency key reused for a different message' using errcode = '22023';
    end if;
    select * into strict v_message from public.messages where id = v_job.message_id;
    return jsonb_build_object('ok', true, 'accepted', true, 'queued', true,
      'message_id', v_message.id, 'external_message_id', v_message.external_message_id,
      'external_status', coalesce(v_message.external_status, v_message.metadata->>'whatsapp_status'),
      'delivery_strategy', v_message.metadata->>'delivery_strategy', 'retry_safe', false);
  end if;

  if v_conversation is null or not public.messaging_can_write_conversation(v_conversation)
     or not exists (select 1 from public.conversations
       where id = v_conversation and tenant_id = v_tenant and channel = 'whatsapp') then
    raise exception 'Writable WhatsApp conversation required' using errcode = '42501';
  end if;
  if (v_type = 'text' and nullif(btrim(p_request->>'text'), '') is null)
     or (v_type = 'template' and nullif(btrim(p_request->>'templateName'), '') is null) then
    raise exception 'Message content is required' using errcode = '22023';
  end if;
  select * into v_channel from public.whatsapp_channels
  where tenant_id = v_tenant and is_active
    and (nullif(p_request->>'phoneNumberId', '') is null
      or phone_number_id = p_request->>'phoneNumberId')
  order by created_at limit 1;
  if not found then
    raise exception 'Active WhatsApp channel required' using errcode = '22023';
  end if;
  -- Existing conversation identity cannot be rebound by changing the request.
  if exists (select 1 from public.whatsapp_conversation_bindings
    where conversation_id = v_conversation
      and (channel_id <> v_channel.id or external_wa_id <> v_phone)) then
    raise exception 'WhatsApp recipient does not match conversation' using errcode = '42501';
  end if;
  v_binding := public.ensure_whatsapp_conversation_binding(
    p_tenant_id => v_tenant, p_channel_id => v_channel.id, p_wa_id => v_phone,
    p_phone_number => v_phone, p_contact_name => p_request->>'contactName',
    p_customer_id => nullif(p_request->>'customerId', '')::uuid,
    p_conversation_id => v_conversation);
  if (v_binding->>'conversation_id')::uuid is distinct from v_conversation then
    raise exception 'WhatsApp binding does not match conversation' using errcode = '42501';
  end if;

  -- Do not trust caller-supplied receipt/action/provider fields in the first
  -- durable row. The existing delivery handler reconstructs them later.
  v_metadata := jsonb_build_object('client_message_id', v_key,
    'channel', 'whatsapp', 'provider', 'whatsapp', 'outbound_type', v_type,
    'status', 'queued', 'pending', false, 'server_ack_durable', true);
  if v_type in ('image', 'document', 'audio') then
    select * into v_attachment from public.messaging_attachments
    where id = nullif(p_request->>'attachmentId', '')::uuid
      and tenant_id = v_tenant and conversation_id = v_conversation
      and created_by = v_actor and status = 'reserved' for update;
    if not found then
      raise exception 'Sendable private attachment required' using errcode = '42501';
    end if;
    v_metadata := v_metadata || jsonb_build_object(
      'attachment_id', v_attachment.id, 'storage_bucket', v_attachment.storage_bucket,
      'storage_path', v_attachment.storage_path, 'filename', v_attachment.original_filename,
      'content_type', v_attachment.declared_mime_type, 'size_bytes', v_attachment.size_bytes);
  end if;
  insert into public.messages(id, conversation_id, tenant_id, sender_id, content,
    type, metadata, external_provider, message_direction, external_status)
  values (v_id, v_conversation, v_tenant, v_actor,
    coalesce(nullif(p_request->>'text', ''), nullif(p_request->>'caption', ''),
      p_request->>'templateName', v_attachment.original_filename, ''),
    case when v_type = 'image' then 'image'
      when v_type in ('document', 'audio') then 'file' else 'text' end,
    v_metadata, 'whatsapp', 'outbound', 'queued');
  if v_attachment.id is not null then
    update public.messaging_attachments set status = 'attached', message_id = v_id,
      attached_at = now(), updated_at = now() where id = v_attachment.id;
  end if;
  insert into public.whatsapp_outbox(message_id, tenant_id, actor_id, client_message_id,
    request, request_hash)
  values (v_id, v_tenant, v_actor, v_key,
    p_request || jsonb_build_object('phoneNumber', v_phone, 'phoneNumberId', v_channel.phone_number_id), v_hash);
  -- pg_net runs after commit. A scheduler outage cannot undo the accepted row.
  begin
    perform public.dispatch_whatsapp_outbox_v1();
  exception when others then
    update public.whatsapp_outbox set last_error = 'dispatch_deferred'
    where message_id = v_id;
  end;
  return jsonb_build_object('ok', true, 'accepted', true, 'queued', true,
    'message_id', v_id, 'external_status', 'queued', 'retry_safe', false);
end;
$$;

create or replace function public.claim_whatsapp_outbox_v1(p_message_id uuid, p_token text)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, extensions
as $$
declare v_job public.whatsapp_outbox%rowtype;
begin
  update public.whatsapp_outbox set state = 'processing', updated_at = now()
  where message_id = p_message_id and state = 'dispatched' and lease_until > now()
    and token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
  returning * into v_job;
  if not found then return null; end if;
  return jsonb_build_object('message_id', v_job.message_id, 'tenant_id', v_job.tenant_id,
    'actor_id', v_job.actor_id, 'request', v_job.request);
end;
$$;

create or replace function public.start_whatsapp_outbox_send_v1(p_message_id uuid, p_token text)
returns boolean language plpgsql security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  update public.whatsapp_outbox q set state = 'sending', updated_at = now()
  where q.message_id = p_message_id and q.state = 'processing' and q.lease_until > now()
    and q.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and exists (select 1 from public.user_profiles p join public.tenants t on t.id = p.tenant_id
      where p.user_id = q.actor_id and p.tenant_id = q.tenant_id
        and p.is_active is true and t.is_active is true)
    and exists (select 1 from public.messages m join public.conversations c on c.id = m.conversation_id
      join public.whatsapp_conversation_bindings b on b.conversation_id = c.id
      join public.whatsapp_channels ch on ch.id = b.channel_id
      where m.id = q.message_id and c.tenant_id = q.tenant_id and c.status in ('active', 'pending')
        and c.channel = 'whatsapp' and b.external_wa_id = q.request->>'phoneNumber'
        and ch.tenant_id = q.tenant_id and ch.is_active
        and ch.phone_number_id = q.request->>'phoneNumberId');
  return found;
end;
$$;

create or replace function public.finish_whatsapp_outbox_v1(
  p_message_id uuid, p_token text, p_status text, p_patch jsonb default '{}'::jsonb
)
returns boolean language plpgsql security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_job public.whatsapp_outbox%rowtype;
  v_status text := p_status;
  v_external_id text := nullif(p_patch->>'external_message_id', '');
  v_metadata jsonb := coalesce(p_patch->'metadata', '{}'::jsonb);
begin
  if v_status not in ('accepted', 'failed', 'outcome_unknown', 'retry') then
    raise exception 'Invalid outbox completion' using errcode = '22023';
  end if;
  select * into v_job from public.whatsapp_outbox
  where message_id = p_message_id
    and token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') for update;
  if not found or v_job.state not in ('processing', 'sending', 'outcome_unknown') then return false; end if;
  if v_job.state = 'outcome_unknown' and v_status <> 'accepted' then return false; end if;
  if v_status = 'accepted' and (v_external_id is null or v_job.state = 'processing') then
    raise exception 'Provider acceptance requires a fenced send and provider id' using errcode = '22023';
  end if;
  if v_status = 'retry' then
    v_status := case when v_job.attempts < 3 then 'queued' else 'failed' end;
  end if;
  update public.whatsapp_outbox set state = v_status, updated_at = now(),
    available_at = now() + make_interval(secs => 30 * greatest(v_job.attempts, 1)),
    lease_until = null,
    token_hash = case when v_status = 'queued' then null else token_hash end,
    last_error = p_patch->>'error'
  where message_id = p_message_id;
  update public.messages m set
    content = coalesce(p_patch->>'content', m.content),
    type = coalesce(nullif(p_patch->>'type', 'audio'), m.type),
    external_message_id = coalesce(v_external_id, m.external_message_id),
    external_status = case
      when m.external_status in ('sent', 'delivered', 'read') then m.external_status
      when v_status = 'outcome_unknown' then null else v_status end,
    metadata = m.metadata || v_metadata || jsonb_build_object(
      'status', v_status, 'whatsapp_status', v_status, 'pending', false,
      'outcome_unknown', v_status = 'outcome_unknown',
      'retry_disabled', v_status = 'outcome_unknown', 'server_ack_durable', true)
  where m.id = p_message_id;
  if v_status = 'failed' then
    update public.messaging_attachments set status = 'failed', failed_at = now(),
      failure_code = coalesce(p_patch->>'error', 'whatsapp_send_failed'), updated_at = now()
    where message_id = p_message_id and status = 'attached';
  end if;
  return true;
end;
$$;

revoke all on function public.enqueue_whatsapp_message_v1(jsonb) from public, anon;
grant execute on function public.enqueue_whatsapp_message_v1(jsonb) to authenticated;
revoke all on function public.dispatch_whatsapp_outbox_v1() from public, anon, authenticated;
revoke all on function public.recover_whatsapp_outbox_v1() from public, anon, authenticated;
revoke all on function public.claim_whatsapp_outbox_v1(uuid, text) from public, anon, authenticated;
revoke all on function public.start_whatsapp_outbox_send_v1(uuid, text) from public, anon, authenticated;
revoke all on function public.finish_whatsapp_outbox_v1(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.dispatch_whatsapp_outbox_v1() to service_role;
grant execute on function public.recover_whatsapp_outbox_v1() to service_role;
grant execute on function public.claim_whatsapp_outbox_v1(uuid, text) to service_role;
grant execute on function public.start_whatsapp_outbox_send_v1(uuid, text) to service_role;
grant execute on function public.finish_whatsapp_outbox_v1(uuid, text, text, jsonb) to service_role;

select cron.schedule('vinabike_whatsapp_outbox', '* * * * *',
  'select public.recover_whatsapp_outbox_v1(); select public.dispatch_whatsapp_outbox_v1();');

comment on table public.whatsapp_outbox is
  'Private durable WhatsApp delivery intent. queued is ERP acceptance, never proof of Meta acceptance. Unknown sends are never automatically retried.';
comment on function public.enqueue_whatsapp_message_v1(jsonb) is
  'Authenticated staff acceptance; conversation authorization, private attachment ownership and idempotency are checked in the same transaction.';
commit;
