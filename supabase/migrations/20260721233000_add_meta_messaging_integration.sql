-- Deployment status: DEPLOYED AND VERIFIED (2026-07-21, project xzdvtzdqjeyqxnkqprtf).
--
-- Add a tenant-scoped Meta transport for Instagram professional accounts and
-- Facebook Pages. Webhook evidence and outbound attempts are durable; access
-- tokens live only in Supabase Vault and are never exposed to authenticated
-- clients. The first delivery slice accepts inbound text/media placeholders,
-- comments/mentions, provider read/delivery evidence, and outbound text inside
-- the standard 24-hour reply window.
--
-- Forward plan:
--   * extend canonical conversation/message provider constraints;
--   * add tenant-owned channel, binding, webhook and send-attempt ledgers;
--   * add one-time OAuth state plus Vault-backed credential commands;
--   * add service-only webhook/send RPCs with replay-safe receipts.
--
-- Recovery plan:
--   Roll back Edge Functions and client callers while retaining all additive
--   tables and provider evidence. Do not delete webhook/send history or Vault
--   secrets. A forward migration may deactivate channels or replace RPC bodies.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '90s';

do $$
begin
  if to_regclass('public.conversations') is null
     or to_regclass('public.messages') is null
     or to_regclass('public.erp_notifications') is null then
    raise exception 'Messaging and ERP notification foundations are required';
  end if;

  if not exists (
    select 1 from pg_extension where extname = 'supabase_vault'
  ) then
    raise exception 'Supabase Vault is required for Meta credentials';
  end if;
end;
$$;

-- Keep the base messaging aggregate canonical. Existing values are retained;
-- only the supported provider vocabulary expands.
alter table public.conversations
  drop constraint if exists conversations_channel_check;
alter table public.conversations
  add constraint conversations_channel_check
  check (
    channel in (
      'internal',
      'website_portal',
      'whatsapp',
      'instagram',
      'facebook_messenger'
    )
  );

alter table public.conversations
  drop constraint if exists conversations_type_channel_check;
alter table public.conversations
  add constraint conversations_type_channel_check
  check (
    (type = 'internal' and channel = 'internal')
    or (
      type = 'support'
      and channel in (
        'website_portal',
        'whatsapp',
        'instagram',
        'facebook_messenger'
      )
    )
  );

alter table public.messages
  drop constraint if exists messages_external_provider_check;
alter table public.messages
  add constraint messages_external_provider_check
  check (
    external_provider in (
      'whatsapp',
      'instagram',
      'facebook_messenger'
    )
    or external_provider is null
  );

create or replace function public.normalize_conversation_channel()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.type = 'internal' then
    new.channel := 'internal';
  elsif new.channel is null or new.channel = 'internal' then
    new.channel := 'website_portal';
  end if;

  return new;
end;
$$;

create table if not exists public.meta_channels (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  provider text not null
    check (provider in ('instagram', 'facebook_messenger')),
  external_account_id text not null,
  display_name text,
  username text,
  granted_scopes text[] not null default '{}'::text[],
  token_expires_at timestamptz,
  subscribed_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(provider, external_account_id),
  unique(tenant_id, provider, external_account_id)
);

create table if not exists public.meta_channel_credentials (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  channel_id uuid not null references public.meta_channels(id) on delete restrict,
  vault_secret_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(channel_id)
);

comment on table public.meta_channel_credentials is
  'Service-only references to Supabase Vault secrets; no provider token is stored in public tables.';

create table if not exists public.meta_conversation_bindings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  channel_id uuid not null references public.meta_channels(id) on delete restrict,
  conversation_id uuid not null references public.conversations(id) on delete restrict,
  external_user_id text not null,
  contact_name text,
  username text,
  last_inbound_at timestamptz,
  last_outbound_at timestamptz,
  reply_window_expires_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(channel_id, external_user_id),
  unique(channel_id, conversation_id)
);

create table if not exists public.meta_webhook_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  channel_id uuid not null references public.meta_channels(id) on delete restrict,
  event_key text not null,
  event_type text not null check (
    event_type in (
      'message',
      'message_echo',
      'message_status',
      'comment',
      'mention',
      'unknown'
    )
  ),
  direction text not null default 'system'
    check (direction in ('inbound', 'outbound', 'system')),
  occurred_at timestamptz,
  conversation_id uuid references public.conversations(id) on delete set null,
  message_id uuid references public.messages(id) on delete set null,
  external_user_id text,
  external_message_id text,
  external_object_id text,
  payload jsonb not null default '{}'::jsonb,
  processed_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  unique(channel_id, event_key)
);

comment on column public.meta_webhook_events.payload is
  'Sanitized identifiers and previews only; provider tokens and remote media URLs are forbidden.';

create table if not exists public.meta_outbound_send_attempts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete restrict,
  channel_id uuid not null references public.meta_channels(id) on delete restrict,
  binding_id uuid not null references public.meta_conversation_bindings(id) on delete restrict,
  conversation_id uuid not null references public.conversations(id) on delete restrict,
  idempotency_key text not null,
  request_fingerprint text not null,
  message_text text not null,
  state text not null default 'prepared' check (
    state in (
      'prepared',
      'preflight_failed',
      'provider_accepted',
      'finalized',
      'provider_rejected',
      'outcome_unknown'
    )
  ),
  external_message_id text,
  message_id uuid references public.messages(id) on delete set null,
  provider_accepted_at timestamptz,
  finalized_at timestamptz,
  error_code text,
  error_message text,
  provider_response jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(tenant_id, idempotency_key)
);

alter table public.meta_outbound_send_attempts
  drop constraint if exists meta_outbound_send_attempts_state_check;
alter table public.meta_outbound_send_attempts
  add constraint meta_outbound_send_attempts_state_check check (
    state in (
      'prepared',
      'preflight_failed',
      'provider_accepted',
      'finalized',
      'provider_rejected',
      'outcome_unknown'
    )
  );

create table if not exists public.meta_oauth_states (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete cascade,
  state_hash text not null unique,
  redirect_uri text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  check (length(state_hash) = 64),
  check (expires_at > created_at)
);

create index if not exists idx_meta_channels_tenant_active
  on public.meta_channels(tenant_id, provider, is_active);
create index if not exists idx_meta_bindings_tenant_conversation
  on public.meta_conversation_bindings(tenant_id, conversation_id);
create index if not exists idx_meta_bindings_reply_window
  on public.meta_conversation_bindings(tenant_id, reply_window_expires_at)
  where reply_window_expires_at is not null;
create index if not exists idx_meta_events_tenant_created
  on public.meta_webhook_events(tenant_id, created_at desc);
create index if not exists idx_meta_events_external_message
  on public.meta_webhook_events(channel_id, external_message_id)
  where external_message_id is not null;
create index if not exists idx_meta_attempts_tenant_created
  on public.meta_outbound_send_attempts(tenant_id, created_at desc);
create index if not exists idx_meta_attempts_conversation_created
  on public.meta_outbound_send_attempts(
    tenant_id,
    conversation_id,
    created_at desc
  );
create index if not exists idx_meta_oauth_states_expiry
  on public.meta_oauth_states(expires_at)
  where consumed_at is null;

alter table public.meta_channels enable row level security;
alter table public.meta_channel_credentials enable row level security;
alter table public.meta_conversation_bindings enable row level security;
alter table public.meta_webhook_events enable row level security;
alter table public.meta_outbound_send_attempts enable row level security;
alter table public.meta_oauth_states enable row level security;

drop policy if exists meta_channels_staff_select on public.meta_channels;
create policy meta_channels_staff_select
  on public.meta_channels for select to authenticated
  using (public.messaging_is_staff_in_tenant(tenant_id));

drop policy if exists meta_bindings_staff_select
  on public.meta_conversation_bindings;

drop policy if exists meta_events_staff_select on public.meta_webhook_events;

revoke all on table public.meta_channels
  from public, anon, authenticated, service_role;
revoke all on table public.meta_channel_credentials
  from public, anon, authenticated, service_role;
revoke all on table public.meta_conversation_bindings
  from public, anon, authenticated, service_role;
revoke all on table public.meta_webhook_events
  from public, anon, authenticated, service_role;
revoke all on table public.meta_outbound_send_attempts
  from public, anon, authenticated, service_role;
revoke all on table public.meta_oauth_states
  from public, anon, authenticated, service_role;

grant select on table public.meta_channels to authenticated;
grant select, insert, update on table public.meta_channels to service_role;
grant select, insert, update on table public.meta_channel_credentials to service_role;
grant select, insert, update on table public.meta_conversation_bindings to service_role;
grant select, insert, update on table public.meta_webhook_events to service_role;
grant select, insert, update on table public.meta_outbound_send_attempts to service_role;
grant select, insert, update on table public.meta_oauth_states to service_role;

drop trigger if exists trg_meta_channels_updated_at on public.meta_channels;
create trigger trg_meta_channels_updated_at
  before update on public.meta_channels
  for each row execute function public.set_updated_at();

drop trigger if exists trg_meta_credentials_updated_at
  on public.meta_channel_credentials;
create trigger trg_meta_credentials_updated_at
  before update on public.meta_channel_credentials
  for each row execute function public.set_updated_at();

drop trigger if exists trg_meta_bindings_updated_at
  on public.meta_conversation_bindings;
create trigger trg_meta_bindings_updated_at
  before update on public.meta_conversation_bindings
  for each row execute function public.set_updated_at();

drop trigger if exists trg_meta_attempts_updated_at
  on public.meta_outbound_send_attempts;
create trigger trg_meta_attempts_updated_at
  before update on public.meta_outbound_send_attempts
  for each row execute function public.set_updated_at();

create or replace function public.enforce_meta_tenant_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_channel public.meta_channels%rowtype;
  v_conversation public.conversations%rowtype;
  v_binding public.meta_conversation_bindings%rowtype;
  v_message public.messages%rowtype;
begin
  if tg_op = 'UPDATE' and new.tenant_id is distinct from old.tenant_id then
    raise exception 'Meta tenant_id is immutable' using errcode = '23514';
  end if;

  if tg_table_name = 'meta_channels' then
    if tg_op = 'UPDATE' and (
      new.provider is distinct from old.provider
      or new.external_account_id is distinct from old.external_account_id
    ) then
      raise exception 'Meta provider account identity is immutable'
        using errcode = '23514';
    end if;
    return new;
  end if;

  if tg_table_name = 'meta_oauth_states' then
    if not exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = new.actor_id
        and profile.tenant_id = new.tenant_id
        and coalesce(profile.is_active, true)
    ) then
      raise exception 'Meta OAuth actor does not belong to tenant'
        using errcode = '23514';
    end if;
    if tg_op = 'UPDATE' and (
      new.actor_id is distinct from old.actor_id
      or new.state_hash is distinct from old.state_hash
      or new.redirect_uri is distinct from old.redirect_uri
      or new.expires_at is distinct from old.expires_at
      or new.created_at is distinct from old.created_at
    ) then
      raise exception 'Meta OAuth state evidence is immutable'
        using errcode = '23514';
    end if;
    return new;
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.id = new.channel_id;

  if not found or v_channel.tenant_id is distinct from new.tenant_id then
    raise exception 'Meta channel must belong to row tenant'
      using errcode = '23514';
  end if;

  if tg_op = 'UPDATE' and new.channel_id is distinct from old.channel_id then
    raise exception 'Meta channel binding is immutable' using errcode = '23514';
  end if;

  if tg_table_name = 'meta_channel_credentials' then
    return new;
  end if;

  if new.conversation_id is not null then
    select conversation.* into v_conversation
    from public.conversations conversation
    where conversation.id = new.conversation_id;

    if not found
       or v_conversation.tenant_id is distinct from new.tenant_id
       or v_conversation.type <> 'support'
       or v_conversation.channel is distinct from v_channel.provider then
      raise exception 'Meta conversation must match tenant and provider'
        using errcode = '23514';
    end if;
  end if;

  if tg_table_name = 'meta_conversation_bindings' then
    if tg_op = 'UPDATE' and (
      new.external_user_id is distinct from old.external_user_id
      or new.created_at is distinct from old.created_at
    ) then
      raise exception 'Meta external user identity is immutable'
        using errcode = '23514';
    end if;
    return new;
  end if;

  if tg_table_name = 'meta_webhook_events' then
    if tg_op = 'UPDATE' and (
      new.event_key is distinct from old.event_key
      or new.event_type is distinct from old.event_type
      or new.direction is distinct from old.direction
      or new.occurred_at is distinct from old.occurred_at
      or new.external_user_id is distinct from old.external_user_id
      or new.external_message_id is distinct from old.external_message_id
      or new.external_object_id is distinct from old.external_object_id
      or new.payload is distinct from old.payload
      or new.created_at is distinct from old.created_at
    ) then
      raise exception 'Meta webhook evidence is append-only'
        using errcode = '23514';
    end if;

    if new.message_id is not null then
      select message.* into v_message
      from public.messages message
      where message.id = new.message_id;
      if not found
         or v_message.tenant_id is distinct from new.tenant_id
         or v_message.conversation_id is distinct from new.conversation_id then
        raise exception 'Meta event message must match its conversation tenant'
          using errcode = '23514';
      end if;
    end if;
    return new;
  end if;

  if tg_table_name = 'meta_outbound_send_attempts' then
    select binding.* into v_binding
    from public.meta_conversation_bindings binding
    where binding.id = new.binding_id;
    if not found
       or v_binding.tenant_id is distinct from new.tenant_id
       or v_binding.channel_id is distinct from new.channel_id
       or v_binding.conversation_id is distinct from new.conversation_id then
      raise exception 'Meta send attempt binding is inconsistent'
        using errcode = '23514';
    end if;
    if new.message_id is not null then
      select message.* into v_message
      from public.messages message
      where message.id = new.message_id;
      if not found
         or v_message.tenant_id is distinct from new.tenant_id
         or v_message.conversation_id is distinct from new.conversation_id then
        raise exception 'Meta send attempt message is inconsistent'
          using errcode = '23514';
      end if;
    end if;
    if tg_op = 'UPDATE' and (
      new.actor_id is distinct from old.actor_id
      or new.binding_id is distinct from old.binding_id
      or new.conversation_id is distinct from old.conversation_id
      or new.idempotency_key is distinct from old.idempotency_key
      or new.request_fingerprint is distinct from old.request_fingerprint
      or new.message_text is distinct from old.message_text
      or new.created_at is distinct from old.created_at
    ) then
      raise exception 'Meta send request identity is immutable'
        using errcode = '23514';
    end if;
    return new;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_meta_channels_consistency on public.meta_channels;
create trigger trg_meta_channels_consistency
  before insert or update on public.meta_channels
  for each row execute function public.enforce_meta_tenant_consistency();
drop trigger if exists trg_meta_credentials_consistency
  on public.meta_channel_credentials;
create trigger trg_meta_credentials_consistency
  before insert or update on public.meta_channel_credentials
  for each row execute function public.enforce_meta_tenant_consistency();
drop trigger if exists trg_meta_bindings_consistency
  on public.meta_conversation_bindings;
create trigger trg_meta_bindings_consistency
  before insert or update on public.meta_conversation_bindings
  for each row execute function public.enforce_meta_tenant_consistency();
drop trigger if exists trg_meta_events_consistency on public.meta_webhook_events;
create trigger trg_meta_events_consistency
  before insert or update on public.meta_webhook_events
  for each row execute function public.enforce_meta_tenant_consistency();
drop trigger if exists trg_meta_attempts_consistency
  on public.meta_outbound_send_attempts;
create trigger trg_meta_attempts_consistency
  before insert or update on public.meta_outbound_send_attempts
  for each row execute function public.enforce_meta_tenant_consistency();
drop trigger if exists trg_meta_oauth_states_consistency
  on public.meta_oauth_states;
create trigger trg_meta_oauth_states_consistency
  before insert or update on public.meta_oauth_states
  for each row execute function public.enforce_meta_tenant_consistency();

create or replace function public.store_meta_channel_credential(
  p_tenant_id uuid,
  p_provider text,
  p_external_account_id text,
  p_display_name text,
  p_username text,
  p_access_token text,
  p_granted_scopes text[] default '{}'::text[],
  p_token_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, vault, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_account_id text := btrim(coalesce(p_external_account_id, ''));
  v_channel public.meta_channels%rowtype;
  v_credential public.meta_channel_credentials%rowtype;
  v_secret_id uuid;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta credential storage requires service role'
      using errcode = '42501';
  end if;
  if p_tenant_id is null
     or v_provider not in ('instagram', 'facebook_messenger')
     or v_account_id = ''
     or nullif(p_access_token, '') is null then
    raise exception 'Valid tenant, provider, account and access token are required'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('meta_channel:' || v_provider || ':' || v_account_id, 0)
  );

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.provider = v_provider
    and channel.external_account_id = v_account_id
  for update;

  if found and v_channel.tenant_id is distinct from p_tenant_id then
    raise exception 'Meta account is already owned by another tenant'
      using errcode = '23514';
  end if;

  if not found then
    insert into public.meta_channels (
      tenant_id,
      provider,
      external_account_id,
      display_name,
      username,
      granted_scopes,
      token_expires_at,
      is_active
    ) values (
      p_tenant_id,
      v_provider,
      v_account_id,
      nullif(btrim(p_display_name), ''),
      nullif(btrim(p_username), ''),
      coalesce(p_granted_scopes, '{}'::text[]),
      p_token_expires_at,
      true
    ) returning * into v_channel;
  else
    update public.meta_channels
    set display_name = coalesce(nullif(btrim(p_display_name), ''), display_name),
        username = coalesce(nullif(btrim(p_username), ''), username),
        granted_scopes = coalesce(p_granted_scopes, granted_scopes),
        token_expires_at = p_token_expires_at,
        subscribed_at = null,
        is_active = true,
        updated_at = clock_timestamp()
    where id = v_channel.id
    returning * into v_channel;
  end if;

  select credential.* into v_credential
  from public.meta_channel_credentials credential
  where credential.channel_id = v_channel.id
  for update;

  if found then
    perform vault.update_secret(
      v_credential.vault_secret_id,
      p_access_token,
      'meta_channel_access_token_' || v_channel.id::text,
      'Meta access token for server-side channel ' || v_channel.id::text
    );
    v_secret_id := v_credential.vault_secret_id;
  else
    v_secret_id := vault.create_secret(
      p_access_token,
      'meta_channel_access_token_' || v_channel.id::text,
      'Meta access token for server-side channel ' || v_channel.id::text
    );
    insert into public.meta_channel_credentials (
      tenant_id,
      channel_id,
      vault_secret_id
    ) values (
      p_tenant_id,
      v_channel.id,
      v_secret_id
    );
  end if;

  return jsonb_build_object(
    'channel_id', v_channel.id,
    'tenant_id', v_channel.tenant_id,
    'provider', v_channel.provider,
    'external_account_id', v_channel.external_account_id,
    'display_name', v_channel.display_name,
    'username', v_channel.username,
    'token_expires_at', v_channel.token_expires_at,
    'credential_stored', true
  );
end;
$$;

create or replace function public.mark_meta_channel_subscribed(
  p_channel_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_channel public.meta_channels%rowtype;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta subscription update requires service role'
      using errcode = '42501';
  end if;

  update public.meta_channels
  set subscribed_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where id = p_channel_id
    and is_active
  returning * into v_channel;
  if not found then
    raise exception 'Active Meta channel not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'channel_id', v_channel.id,
    'tenant_id', v_channel.tenant_id,
    'subscribed_at', v_channel.subscribed_at
  );
end;
$$;

create or replace function public.get_meta_channel_access_token(
  p_channel_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, vault, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_result jsonb;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta credential access requires service role'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'channel_id', channel.id,
    'tenant_id', channel.tenant_id,
    'provider', channel.provider,
    'external_account_id', channel.external_account_id,
    'display_name', channel.display_name,
    'username', channel.username,
    'access_token', secret.decrypted_secret,
    'token_expires_at', channel.token_expires_at
  ) into v_result
  from public.meta_channels channel
  join public.meta_channel_credentials credential
    on credential.channel_id = channel.id
   and credential.tenant_id = channel.tenant_id
  join vault.decrypted_secrets secret
    on secret.id = credential.vault_secret_id
  where channel.id = p_channel_id
    and channel.is_active
    and nullif(secret.decrypted_secret, '') is not null;

  if v_result is null then
    raise exception 'Active Meta channel credential not found'
      using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

-- Remove the earlier ambiguous overload if this pending migration was already
-- exercised on a disposable database before the tenant-explicit contract.
drop function if exists public.create_meta_oauth_state(
  uuid, text, text, timestamptz
);

create or replace function public.create_meta_oauth_state(
  p_actor_id uuid,
  p_tenant_id uuid,
  p_state_hash text,
  p_redirect_uri text,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_state_id uuid;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta OAuth state creation requires service role'
      using errcode = '42501';
  end if;

  -- OAuth state is an ephemeral anti-replay nonce rather than business audit.
  -- Keep it bounded while retaining a 30-day diagnostic window.
  delete from public.meta_oauth_states state
  where state.expires_at < clock_timestamp() - interval '30 days'
     or state.consumed_at < clock_timestamp() - interval '30 days';

  if p_actor_id is null
     or p_tenant_id is null
     or coalesce(p_state_hash, '') !~ '^[0-9a-f]{64}$'
     or nullif(btrim(p_redirect_uri), '') is null
     or p_expires_at <= clock_timestamp()
     or p_expires_at > clock_timestamp() + interval '15 minutes' then
    raise exception 'Invalid Meta OAuth state request' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = p_actor_id
      and profile.tenant_id = p_tenant_id
      and coalesce(profile.is_active, true)
      and profile.role in ('admin', 'manager')
  ) then
    raise exception 'Meta OAuth requires an active admin or manager'
      using errcode = '42501';
  end if;

  insert into public.meta_oauth_states (
    tenant_id,
    actor_id,
    state_hash,
    redirect_uri,
    expires_at
  ) values (
    p_tenant_id,
    p_actor_id,
    p_state_hash,
    btrim(p_redirect_uri),
    p_expires_at
  ) returning id into v_state_id;

  return jsonb_build_object(
    'state_id', v_state_id,
    'tenant_id', p_tenant_id,
    'expires_at', p_expires_at
  );
end;
$$;

create or replace function public.consume_meta_oauth_state(
  p_state_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_state public.meta_oauth_states%rowtype;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta OAuth state consumption requires service role'
      using errcode = '42501';
  end if;
  if coalesce(p_state_hash, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid Meta OAuth state' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('meta_oauth:' || p_state_hash, 0));
  select state.* into v_state
  from public.meta_oauth_states state
  where state.state_hash = p_state_hash
  for update;

  if not found or v_state.consumed_at is not null
     or v_state.expires_at <= clock_timestamp() then
    raise exception 'Meta OAuth state is invalid, expired, or already consumed'
      using errcode = '22023';
  end if;

  update public.meta_oauth_states
  set consumed_at = clock_timestamp()
  where id = v_state.id;

  return jsonb_build_object(
    'state_id', v_state.id,
    'tenant_id', v_state.tenant_id,
    'actor_id', v_state.actor_id,
    'redirect_uri', v_state.redirect_uri
  );
end;
$$;

create or replace function public.ensure_meta_conversation_binding(
  p_channel_id uuid,
  p_external_user_id text,
  p_contact_name text default null,
  p_username text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_external_user_id text := btrim(coalesce(p_external_user_id, ''));
  v_channel public.meta_channels%rowtype;
  v_binding record;
  v_binding_id uuid;
  v_conversation_id uuid;
  v_previous_conversation_id uuid;
  v_title text;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta conversation binding requires service role'
      using errcode = '42501';
  end if;
  if p_channel_id is null or v_external_user_id = '' then
    raise exception 'Meta channel and external user are required'
      using errcode = '22023';
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.id = p_channel_id
    and channel.is_active;
  if not found then
    raise exception 'Active Meta channel not found' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'meta_binding:' || p_channel_id::text || ':' || v_external_user_id,
    0
  ));

  select
    binding.*,
    conversation.status as conversation_status
  into v_binding
  from public.meta_conversation_bindings binding
  join public.conversations conversation
    on conversation.id = binding.conversation_id
   and conversation.tenant_id = binding.tenant_id
  where binding.channel_id = p_channel_id
    and binding.external_user_id = v_external_user_id
  for update of binding, conversation;

  if found and v_binding.tenant_id is distinct from v_channel.tenant_id then
    raise exception 'Meta binding belongs to another tenant'
      using errcode = '23514';
  end if;

  if found and v_binding.conversation_status in ('pending', 'active') then
    v_binding_id := v_binding.id;
    v_conversation_id := v_binding.conversation_id;
  elsif found then
    v_binding_id := v_binding.id;
    v_previous_conversation_id := v_binding.conversation_id;
  end if;

  if v_conversation_id is null then
    v_title := coalesce(
      nullif(btrim(p_contact_name), ''),
      nullif(btrim(p_username), ''),
      (case
        when v_channel.provider = 'instagram' then 'Instagram'
        else 'Messenger'
      end) || ' • ' || upper(substr(md5(v_external_user_id), 1, 6))
    );

    insert into public.conversations (
      tenant_id,
      type,
      channel,
      counterparty_type,
      title,
      status,
      created_by,
      last_message_at,
      updated_at
    ) values (
      v_channel.tenant_id,
      'support',
      v_channel.provider,
      'customer',
      v_title,
      'pending',
      null,
      clock_timestamp(),
      clock_timestamp()
    ) returning id into v_conversation_id;
  end if;

  if v_binding_id is null then
    insert into public.meta_conversation_bindings (
      tenant_id,
      channel_id,
      conversation_id,
      external_user_id,
      contact_name,
      username
    ) values (
      v_channel.tenant_id,
      v_channel.id,
      v_conversation_id,
      v_external_user_id,
      nullif(btrim(p_contact_name), ''),
      nullif(btrim(p_username), '')
    ) returning id into v_binding_id;
  elsif v_previous_conversation_id is not null then
    update public.meta_conversation_bindings
    set conversation_id = v_conversation_id,
        contact_name = coalesce(nullif(btrim(p_contact_name), ''), contact_name),
        username = coalesce(nullif(btrim(p_username), ''), username),
        updated_at = clock_timestamp()
    where id = v_binding_id;
  else
    update public.meta_conversation_bindings
    set contact_name = coalesce(nullif(btrim(p_contact_name), ''), contact_name),
        username = coalesce(nullif(btrim(p_username), ''), username),
        updated_at = clock_timestamp()
    where id = v_binding_id;
  end if;

  update public.conversations
  set title = case
        when nullif(btrim(p_contact_name), '') is not null then btrim(p_contact_name)
        when nullif(btrim(title), '') is null
          then coalesce(nullif(btrim(p_username), ''), title)
        else title
      end,
      updated_at = clock_timestamp()
  where id = v_conversation_id;

  return jsonb_build_object(
    'tenant_id', v_channel.tenant_id,
    'channel_id', v_channel.id,
    'provider', v_channel.provider,
    'binding_id', v_binding_id,
    'conversation_id', v_conversation_id,
    'external_user_id', v_external_user_id,
    'rebound_from_conversation_id', v_previous_conversation_id
  );
end;
$$;

create or replace function public.meta_message_status_rank(p_status text)
returns integer
language sql
immutable
set search_path = public, pg_temp
as $$
  select case lower(coalesce(p_status, ''))
    when 'accepted' then 10
    when 'sent' then 20
    when 'delivered' then 30
    when 'read' then 40
    when 'failed' then 5
    else 0
  end;
$$;

create or replace function public.ingest_meta_message(
  p_provider text,
  p_external_account_id text,
  p_event_key text,
  p_external_message_id text,
  p_external_user_id text,
  p_contact_name text default null,
  p_username text default null,
  p_message_type text default 'text',
  p_message_body text default null,
  p_occurred_at timestamptz default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_event_key text := btrim(coalesce(p_event_key, ''));
  v_raw_message_id text := btrim(coalesce(p_external_message_id, ''));
  v_external_user_id text := btrim(coalesce(p_external_user_id, ''));
  v_channel public.meta_channels%rowtype;
  v_existing_event public.meta_webhook_events%rowtype;
  v_existing_message public.messages%rowtype;
  v_binding jsonb;
  v_binding_id uuid;
  v_conversation_id uuid;
  v_message_id uuid;
  v_event_id uuid;
  v_canonical_message_id text;
  v_message_type text;
  v_ui_type text;
  v_content text;
  v_occurred_at timestamptz := least(
    coalesce(p_occurred_at, clock_timestamp()),
    clock_timestamp() + interval '5 minutes'
  );
begin
  if v_role <> 'service_role' then
    raise exception 'Meta message ingestion requires service role'
      using errcode = '42501';
  end if;
  if v_provider not in ('instagram', 'facebook_messenger')
     or btrim(coalesce(p_external_account_id, '')) = ''
     or v_event_key = ''
     or v_raw_message_id = ''
     or v_external_user_id = '' then
    raise exception 'Meta inbound message identifiers are required'
      using errcode = '22023';
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.provider = v_provider
    and channel.external_account_id = btrim(p_external_account_id)
    and channel.is_active;
  if not found then
    return jsonb_build_object(
      'ignored', true,
      'reason', 'channel_not_found',
      'provider', v_provider,
      'external_account_id', btrim(p_external_account_id)
    );
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'meta_event:' || v_channel.id::text || ':' || v_event_key,
    0
  ));
  select event.* into v_existing_event
  from public.meta_webhook_events event
  where event.channel_id = v_channel.id
    and event.event_key = v_event_key;
  if found then
    return jsonb_build_object(
      'duplicate', true,
      'event_id', v_existing_event.id,
      'message_id', v_existing_event.message_id,
      'conversation_id', v_existing_event.conversation_id
    );
  end if;

  v_canonical_message_id := v_channel.id::text || ':' || v_raw_message_id;
  select message.* into v_existing_message
  from public.messages message
  where message.external_message_id = v_canonical_message_id;

  if found then
    insert into public.meta_webhook_events (
      tenant_id,
      channel_id,
      event_key,
      event_type,
      direction,
      occurred_at,
      conversation_id,
      message_id,
      external_user_id,
      external_message_id,
      payload
    ) values (
      v_channel.tenant_id,
      v_channel.id,
      v_event_key,
      'message',
      'inbound',
      v_occurred_at,
      v_existing_message.conversation_id,
      v_existing_message.id,
      v_external_user_id,
      v_raw_message_id,
      coalesce(p_payload, '{}'::jsonb)
    ) returning id into v_event_id;
    return jsonb_build_object(
      'duplicate', true,
      'event_id', v_event_id,
      'message_id', v_existing_message.id,
      'conversation_id', v_existing_message.conversation_id
    );
  end if;

  v_binding := public.ensure_meta_conversation_binding(
    v_channel.id,
    v_external_user_id,
    p_contact_name,
    p_username
  );
  v_binding_id := (v_binding->>'binding_id')::uuid;
  v_conversation_id := (v_binding->>'conversation_id')::uuid;
  v_message_type := lower(btrim(coalesce(p_message_type, 'text')));
  -- Remote Meta media is not hydrated into the private attachment registry in
  -- this MVP. Persist a plain text placeholder so ChatWindow never renders a
  -- broken attachment while retaining the provider type in metadata.
  v_ui_type := 'text';
  v_content := nullif(btrim(coalesce(p_message_body, '')), '');
  if v_content is null then
    v_content := case v_message_type
      when 'image' then '[Imagen recibida]'
      when 'video' then '[Video recibido]'
      when 'audio' then '[Audio recibido]'
      when 'sticker' then '[Sticker recibido]'
      when 'text' then '[Mensaje sin texto]'
      else '[Archivo recibido]'
    end;
  end if;
  v_content := left(v_content, 4000);

  insert into public.meta_webhook_events (
    tenant_id,
    channel_id,
    event_key,
    event_type,
    direction,
    occurred_at,
    conversation_id,
    external_user_id,
    external_message_id,
    payload
  ) values (
    v_channel.tenant_id,
    v_channel.id,
    v_event_key,
    'message',
    'inbound',
    v_occurred_at,
    v_conversation_id,
    v_external_user_id,
    v_raw_message_id,
    coalesce(p_payload, '{}'::jsonb)
  ) returning id into v_event_id;

  insert into public.messages (
    conversation_id,
    sender_id,
    tenant_id,
    content,
    type,
    metadata,
    external_provider,
    external_message_id,
    message_direction,
    created_at
  ) values (
    v_conversation_id,
    null,
    v_channel.tenant_id,
    v_content,
    v_ui_type,
    jsonb_strip_nulls(jsonb_build_object(
      'provider', v_provider,
      'meta_channel_id', v_channel.id,
      'meta_event_id', v_event_id,
      'contact_label', (case
        when v_provider = 'instagram' then 'Instagram'
        else 'Messenger'
      end) || ' • ' || upper(substr(md5(v_external_user_id), 1, 6)),
      'message_type', v_message_type,
      'media_placeholder', v_message_type <> 'text'
    )),
    v_provider,
    v_canonical_message_id,
    'inbound',
    v_occurred_at
  ) returning id into v_message_id;

  update public.meta_webhook_events
  set message_id = v_message_id
  where id = v_event_id;

  update public.meta_conversation_bindings
  set last_inbound_at = greatest(
        coalesce(last_inbound_at, '-infinity'::timestamptz),
        v_occurred_at
      ),
      reply_window_expires_at = greatest(
        coalesce(reply_window_expires_at, '-infinity'::timestamptz),
        v_occurred_at + interval '24 hours'
      ),
      updated_at = clock_timestamp()
  where id = v_binding_id;

  update public.conversations
  set status = case when status = 'pending' then 'active' else status end,
      last_message_at = greatest(
        coalesce(last_message_at, '-infinity'::timestamptz),
        v_occurred_at
      ),
      updated_at = clock_timestamp()
  where id = v_conversation_id;

  return jsonb_build_object(
    'duplicate', false,
    'event_id', v_event_id,
    'message_id', v_message_id,
    'conversation_id', v_conversation_id,
    'binding_id', v_binding_id,
    'tenant_id', v_channel.tenant_id
  );
end;
$$;

create or replace function public.record_meta_echo_event(
  p_provider text,
  p_external_account_id text,
  p_event_key text,
  p_external_message_id text,
  p_external_user_id text default null,
  p_occurred_at timestamptz default null,
  p_payload jsonb default '{}'::jsonb
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
  v_event public.meta_webhook_events%rowtype;
  v_message public.messages%rowtype;
  v_event_id uuid;
  v_canonical_message_id text;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta echo recording requires service role'
      using errcode = '42501';
  end if;
  if v_provider not in ('instagram', 'facebook_messenger')
     or nullif(btrim(p_external_account_id), '') is null
     or nullif(btrim(p_event_key), '') is null
     or nullif(btrim(p_external_message_id), '') is null then
    raise exception 'Meta echo identifiers are required' using errcode = '22023';
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.provider = v_provider
    and channel.external_account_id = btrim(p_external_account_id)
    and channel.is_active;
  if not found then
    return jsonb_build_object('ignored', true, 'reason', 'channel_not_found');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'meta_event:' || v_channel.id::text || ':' || btrim(p_event_key),
    0
  ));
  select event.* into v_event
  from public.meta_webhook_events event
  where event.channel_id = v_channel.id
    and event.event_key = btrim(p_event_key);
  if found then
    return jsonb_build_object(
      'duplicate', true,
      'event_id', v_event.id,
      'message_id', v_event.message_id,
      'conversation_id', v_event.conversation_id
    );
  end if;

  v_canonical_message_id := v_channel.id::text || ':' || btrim(p_external_message_id);
  select message.* into v_message
  from public.messages message
  where message.external_message_id = v_canonical_message_id
    and message.external_provider = v_provider;

  insert into public.meta_webhook_events (
    tenant_id,
    channel_id,
    event_key,
    event_type,
    direction,
    occurred_at,
    conversation_id,
    message_id,
    external_user_id,
    external_message_id,
    payload
  ) values (
    v_channel.tenant_id,
    v_channel.id,
    btrim(p_event_key),
    'message_echo',
    'outbound',
    coalesce(p_occurred_at, clock_timestamp()),
    v_message.conversation_id,
    v_message.id,
    nullif(btrim(p_external_user_id), ''),
    btrim(p_external_message_id),
    coalesce(p_payload, '{}'::jsonb)
  ) returning id into v_event_id;

  if v_message.id is not null
     and public.meta_message_status_rank(v_message.external_status) <
       public.meta_message_status_rank('sent') then
    update public.messages
    set external_status = 'sent',
        metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
          'meta_echo_event_id', v_event_id,
          'meta_echo_at', coalesce(p_occurred_at, clock_timestamp())
        )
    where id = v_message.id;
  end if;

  return jsonb_build_object(
    'duplicate', false,
    'event_id', v_event_id,
    'message_id', v_message.id,
    'conversation_id', v_message.conversation_id,
    'echo_ignored_as_inbound', true
  );
end;
$$;

create or replace function public.record_meta_message_status(
  p_provider text,
  p_external_account_id text,
  p_event_key text,
  p_external_user_id text,
  p_external_message_id text default null,
  p_status text default 'read',
  p_watermark timestamptz default null,
  p_occurred_at timestamptz default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_status text := case lower(btrim(coalesce(p_status, '')))
    when 'seen' then 'read'
    else lower(btrim(coalesce(p_status, '')))
  end;
  v_channel public.meta_channels%rowtype;
  v_binding public.meta_conversation_bindings%rowtype;
  v_existing_event public.meta_webhook_events%rowtype;
  v_exact_message public.messages%rowtype;
  v_event_id uuid;
  v_updated_count integer := 0;
  v_canonical_message_id text;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta status recording requires service role'
      using errcode = '42501';
  end if;
  if v_provider not in ('instagram', 'facebook_messenger')
     or nullif(btrim(p_external_account_id), '') is null
     or nullif(btrim(p_event_key), '') is null
     or nullif(btrim(p_external_user_id), '') is null
     or v_status not in ('sent', 'delivered', 'read', 'failed') then
    raise exception 'Valid Meta status identifiers are required'
      using errcode = '22023';
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.provider = v_provider
    and channel.external_account_id = btrim(p_external_account_id)
    and channel.is_active;
  if not found then
    return jsonb_build_object('ignored', true, 'reason', 'channel_not_found');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'meta_event:' || v_channel.id::text || ':' || btrim(p_event_key),
    0
  ));
  select event.* into v_existing_event
  from public.meta_webhook_events event
  where event.channel_id = v_channel.id
    and event.event_key = btrim(p_event_key);
  if found then
    return jsonb_build_object(
      'duplicate', true,
      'event_id', v_existing_event.id,
      'message_id', v_existing_event.message_id,
      'conversation_id', v_existing_event.conversation_id
    );
  end if;

  select binding.* into v_binding
  from public.meta_conversation_bindings binding
  where binding.channel_id = v_channel.id
    and binding.external_user_id = btrim(p_external_user_id);

  if nullif(btrim(p_external_message_id), '') is not null then
    v_canonical_message_id := v_channel.id::text || ':' || btrim(p_external_message_id);
    select message.* into v_exact_message
    from public.messages message
    where message.external_message_id = v_canonical_message_id
      and message.external_provider = v_provider;
  end if;

  insert into public.meta_webhook_events (
    tenant_id,
    channel_id,
    event_key,
    event_type,
    direction,
    occurred_at,
    conversation_id,
    message_id,
    external_user_id,
    external_message_id,
    payload
  ) values (
    v_channel.tenant_id,
    v_channel.id,
    btrim(p_event_key),
    'message_status',
    'system',
    coalesce(p_occurred_at, p_watermark, clock_timestamp()),
    coalesce(v_exact_message.conversation_id, v_binding.conversation_id),
    v_exact_message.id,
    btrim(p_external_user_id),
    nullif(btrim(p_external_message_id), ''),
    coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('status', v_status)
  ) returning id into v_event_id;

  if v_exact_message.id is not null
     and public.meta_message_status_rank(v_exact_message.external_status) <
       public.meta_message_status_rank(v_status) then
    update public.messages
    set external_status = v_status,
        metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
          'meta_status_event_id', v_event_id,
          'meta_status_updated_at', clock_timestamp()
        )
    where id = v_exact_message.id;
    v_updated_count := 1;
  elsif p_watermark is not null and v_binding.id is not null
        and v_status in ('delivered', 'read') then
    update public.messages message
    set external_status = v_status,
        metadata = coalesce(message.metadata, '{}'::jsonb) || jsonb_build_object(
          'meta_status_event_id', v_event_id,
          'meta_status_watermark', p_watermark,
          'meta_status_updated_at', clock_timestamp()
        )
    where message.tenant_id = v_channel.tenant_id
      and message.conversation_id = v_binding.conversation_id
      and message.external_provider = v_provider
      and message.message_direction = 'outbound'
      and message.created_at <= p_watermark
      and public.meta_message_status_rank(message.external_status) <
        public.meta_message_status_rank(v_status);
    get diagnostics v_updated_count = row_count;
  end if;

  return jsonb_build_object(
    'duplicate', false,
    'event_id', v_event_id,
    'message_id', v_exact_message.id,
    'conversation_id', coalesce(
      v_exact_message.conversation_id,
      v_binding.conversation_id
    ),
    'status', v_status,
    'updated_count', v_updated_count
  );
end;
$$;

create or replace function public.ingest_meta_interaction(
  p_provider text,
  p_external_account_id text,
  p_event_key text,
  p_interaction_type text,
  p_external_user_id text,
  p_external_object_id text,
  p_parent_object_id text default null,
  p_actor_name text default null,
  p_body text default null,
  p_permalink text default null,
  p_occurred_at timestamptz default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_interaction text := lower(btrim(coalesce(p_interaction_type, '')));
  v_channel public.meta_channels%rowtype;
  v_existing_event public.meta_webhook_events%rowtype;
  v_event_id uuid;
  v_notification_type text;
  v_title text;
  v_body text;
  v_safe_permalink text;
  v_verb text := lower(btrim(coalesce(p_payload->>'verb', '')));
begin
  if v_role <> 'service_role' then
    raise exception 'Meta interaction ingestion requires service role'
      using errcode = '42501';
  end if;
  if v_provider not in ('instagram', 'facebook_messenger')
     or v_interaction not in ('comment', 'mention')
     or nullif(btrim(p_external_account_id), '') is null
     or nullif(btrim(p_event_key), '') is null
     or nullif(btrim(p_external_object_id), '') is null then
    raise exception 'Valid Meta interaction identifiers are required'
      using errcode = '22023';
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.provider = v_provider
    and channel.external_account_id = btrim(p_external_account_id)
    and channel.is_active;
  if not found then
    return jsonb_build_object('ignored', true, 'reason', 'channel_not_found');
  end if;

  v_safe_permalink := case
    when v_provider = 'instagram'
      and length(btrim(coalesce(p_permalink, ''))) <= 2048
      and lower(btrim(p_permalink)) ~
        '^https://(www\.)?instagram\.com(/|$)'
      then btrim(p_permalink)
    when v_provider = 'facebook_messenger'
      and length(btrim(coalesce(p_permalink, ''))) <= 2048
      and lower(btrim(p_permalink)) ~
        '^https://(www\.|m\.)?facebook\.com(/|$)'
      then btrim(p_permalink)
    else null
  end;

  perform pg_advisory_xact_lock(hashtextextended(
    'meta_event:' || v_channel.id::text || ':' || btrim(p_event_key),
    0
  ));
  select event.* into v_existing_event
  from public.meta_webhook_events event
  where event.channel_id = v_channel.id
    and event.event_key = btrim(p_event_key);
  if found then
    return jsonb_build_object(
      'duplicate', true,
      'event_id', v_existing_event.id
    );
  end if;

  insert into public.meta_webhook_events (
    tenant_id,
    channel_id,
    event_key,
    event_type,
    direction,
    occurred_at,
    external_user_id,
    external_object_id,
    payload
  ) values (
    v_channel.tenant_id,
    v_channel.id,
    btrim(p_event_key),
    v_interaction,
    'system',
    coalesce(p_occurred_at, clock_timestamp()),
    nullif(btrim(p_external_user_id), ''),
    btrim(p_external_object_id),
    jsonb_strip_nulls(
      (coalesce(p_payload, '{}'::jsonb) - 'permalink')
      || jsonb_build_object('permalink', v_safe_permalink)
    )
  ) returning id into v_event_id;

  -- Page feed removals/edits are durable provider evidence, but they are not
  -- new customer activity. Only an absent verb (Instagram) or explicit Page
  -- `add` event may create a "new comment/mention" notification.
  if v_verb <> '' and v_verb <> 'add' then
    return jsonb_build_object(
      'duplicate', false,
      'event_id', v_event_id,
      'notification_created', false,
      'reason', 'interaction_not_new',
      'tenant_id', v_channel.tenant_id
    );
  end if;

  v_notification_type := 'meta_' || case
    when v_provider = 'instagram' then 'instagram'
    else 'facebook'
  end || '_' || v_interaction;
  v_title := case
    when v_provider = 'instagram' and v_interaction = 'comment'
      then 'Nuevo comentario de Instagram'
    when v_provider = 'instagram' then 'Nueva mención de Instagram'
    when v_interaction = 'comment' then 'Nuevo comentario de Facebook'
    else 'Nueva mención de Facebook'
  end;
  v_body := left(
    concat_ws(
      ': ',
      coalesce(nullif(btrim(p_actor_name), ''), 'Persona'),
      coalesce(nullif(btrim(p_body), ''), 'Nueva interacción')
    ),
    240
  );

  insert into public.erp_notifications (
    tenant_id,
    type,
    title,
    body,
    route,
    entity_type,
    entity_id,
    severity,
    data
  ) values (
    v_channel.tenant_id,
    v_notification_type,
    v_title,
    v_body,
    coalesce(v_safe_permalink, '/chat'),
    'meta_event',
    v_event_id,
    'info',
    jsonb_strip_nulls(jsonb_build_object(
      'provider', v_provider,
      'interaction_type', v_interaction,
      'actor_name', nullif(btrim(p_actor_name), ''),
      'preview', left(coalesce(nullif(btrim(p_body), ''), ''), 240),
      'permalink', v_safe_permalink
    ))
  ) on conflict (tenant_id, type, entity_type, entity_id) do nothing;

  return jsonb_build_object(
    'duplicate', false,
    'event_id', v_event_id,
    'notification_type', v_notification_type,
    'tenant_id', v_channel.tenant_id
  );
end;
$$;

create or replace function public.begin_meta_outbound_send(
  p_actor_id uuid,
  p_conversation_id uuid,
  p_idempotency_key text,
  p_request_fingerprint text,
  p_message_text text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_message_text text := btrim(coalesce(p_message_text, ''));
  v_fingerprint text;
  v_conversation public.conversations%rowtype;
  v_binding public.meta_conversation_bindings%rowtype;
  v_channel public.meta_channels%rowtype;
  v_attempt public.meta_outbound_send_attempts%rowtype;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta send preparation requires service role'
      using errcode = '42501';
  end if;
  if p_actor_id is null
     or p_conversation_id is null
     or nullif(btrim(p_idempotency_key), '') is null
     or length(btrim(p_idempotency_key)) > 200
     or v_message_text = ''
     or char_length(v_message_text) > 2000 then
    raise exception 'Valid actor, conversation, idempotency key and text are required'
      using errcode = '22023';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(
    p_conversation_id::text || E'\n' || v_message_text,
    'UTF8'
  ), 'sha256'), 'hex');
  if lower(coalesce(p_request_fingerprint, '')) is distinct from v_fingerprint then
    raise exception 'Meta send request fingerprint does not match payload'
      using errcode = '23514';
  end if;

  select conversation.* into v_conversation
  from public.conversations conversation
  where conversation.id = p_conversation_id
  for share;
  if not found
     or v_conversation.type <> 'support'
     or v_conversation.channel not in ('instagram', 'facebook_messenger') then
    raise exception 'Meta support conversation not found' using errcode = 'P0002';
  end if;
  if v_conversation.status not in ('pending', 'active') then
    raise exception 'Meta conversation is closed' using errcode = '23514';
  end if;
  if not exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = p_actor_id
      and profile.tenant_id = v_conversation.tenant_id
      and coalesce(profile.is_active, true)
  ) then
    raise exception 'Meta send actor is not active staff in tenant'
      using errcode = '42501';
  end if;

  select binding.* into v_binding
  from public.meta_conversation_bindings binding
  where binding.conversation_id = v_conversation.id
    and binding.tenant_id = v_conversation.tenant_id;
  if not found then
    raise exception 'Meta conversation binding not found' using errcode = 'P0002';
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.id = v_binding.channel_id
    and channel.tenant_id = v_binding.tenant_id
    and channel.provider = v_conversation.channel
    and channel.is_active;
  if not found then
    raise exception 'Active Meta channel not found' using errcode = 'P0002';
  end if;
  if v_binding.reply_window_expires_at is null
     or v_binding.reply_window_expires_at <= clock_timestamp()
     or v_binding.reply_window_expires_at >
       clock_timestamp() + interval '24 hours 5 minutes' then
    raise exception 'Meta 24-hour reply window is closed'
      using errcode = 'P0001', hint = 'reply_window_closed';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    v_conversation.tenant_id::text || ':meta_send:' || btrim(p_idempotency_key),
    0
  ));
  select attempt.* into v_attempt
  from public.meta_outbound_send_attempts attempt
  where attempt.tenant_id = v_conversation.tenant_id
    and attempt.idempotency_key = btrim(p_idempotency_key)
  for update;

  if found then
    if v_attempt.actor_id is distinct from p_actor_id
       or v_attempt.conversation_id is distinct from p_conversation_id
       or v_attempt.request_fingerprint is distinct from v_fingerprint then
      raise exception 'Meta idempotency key belongs to another request'
        using errcode = '23514';
    end if;
    return jsonb_strip_nulls(jsonb_build_object(
      'replayed', true,
      'attempt_id', v_attempt.id,
      'state', v_attempt.state,
      'tenant_id', v_attempt.tenant_id,
      'channel_id', v_attempt.channel_id,
      'binding_id', v_attempt.binding_id,
      'conversation_id', v_attempt.conversation_id,
      'client_message_id', v_attempt.idempotency_key,
      'provider', v_channel.provider,
      'external_account_id', v_channel.external_account_id,
      'external_user_id', v_binding.external_user_id,
      'message_id', v_attempt.message_id,
      'external_message_id', v_attempt.external_message_id,
      'error_code', v_attempt.error_code,
      'error_message', v_attempt.error_message
    ));
  end if;

  insert into public.meta_outbound_send_attempts (
    tenant_id,
    actor_id,
    channel_id,
    binding_id,
    conversation_id,
    idempotency_key,
    request_fingerprint,
    message_text,
    state
  ) values (
    v_conversation.tenant_id,
    p_actor_id,
    v_channel.id,
    v_binding.id,
    v_conversation.id,
    btrim(p_idempotency_key),
    v_fingerprint,
    v_message_text,
    'prepared'
  ) returning * into v_attempt;

  return jsonb_build_object(
    'replayed', false,
    'attempt_id', v_attempt.id,
    'state', v_attempt.state,
    'tenant_id', v_attempt.tenant_id,
    'channel_id', v_attempt.channel_id,
    'binding_id', v_attempt.binding_id,
    'conversation_id', v_attempt.conversation_id,
    'client_message_id', v_attempt.idempotency_key,
    'provider', v_channel.provider,
    'external_account_id', v_channel.external_account_id,
    'external_user_id', v_binding.external_user_id,
    'reply_window_expires_at', v_binding.reply_window_expires_at
  );
end;
$$;

create or replace function public.get_meta_conversation_transport(
  p_conversation_id uuid
)
returns table (
  provider text,
  reply_window_expires_at timestamptz,
  can_reply boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_conversation public.conversations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated Meta transport reader required'
      using errcode = '42501';
  end if;
  select conversation.* into v_conversation
  from public.conversations conversation
  where conversation.id = p_conversation_id;
  if not found
     or v_conversation.channel not in ('instagram', 'facebook_messenger')
     or not public.messaging_is_staff_in_tenant(v_conversation.tenant_id)
     or not public.messaging_can_read_conversation_messages(v_conversation.id) then
    raise exception 'Meta conversation transport is not available to this user'
      using errcode = '42501';
  end if;

  return query
  select
    channel.provider,
    binding.reply_window_expires_at,
    channel.is_active
      and binding.reply_window_expires_at is not null
      and binding.reply_window_expires_at > now()
      and binding.reply_window_expires_at <=
        now() + interval '24 hours 5 minutes'
  from public.meta_conversation_bindings binding
  join public.meta_channels channel
    on channel.id = binding.channel_id
   and channel.tenant_id = binding.tenant_id
  where binding.tenant_id = v_conversation.tenant_id
    and binding.conversation_id = v_conversation.id
    and channel.provider = v_conversation.channel;

  if not found then
    raise exception 'Meta conversation binding is unavailable'
      using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public.list_meta_outbound_send_receipts(
  p_conversation_id uuid
)
returns table (
  attempt_id uuid,
  conversation_id uuid,
  actor_id uuid,
  client_message_id text,
  state text,
  message_text text,
  message_id uuid,
  external_message_id text,
  error_code text,
  error_message text,
  provider_accepted_at timestamptz,
  finalized_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_conversation public.conversations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated Meta receipt reader required'
      using errcode = '42501';
  end if;
  select conversation.* into v_conversation
  from public.conversations conversation
  where conversation.id = p_conversation_id;
  if not found
     or v_conversation.channel not in ('instagram', 'facebook_messenger')
     or not public.messaging_is_staff_in_tenant(v_conversation.tenant_id)
     or not public.messaging_can_read_conversation_messages(v_conversation.id) then
    raise exception 'Meta send receipts are not available to this user'
      using errcode = '42501';
  end if;

  return query
  select
    attempt.id,
    attempt.conversation_id,
    attempt.actor_id,
    attempt.idempotency_key,
    attempt.state,
    attempt.message_text,
    attempt.message_id,
    attempt.external_message_id,
    attempt.error_code,
    attempt.error_message,
    attempt.provider_accepted_at,
    attempt.finalized_at,
    attempt.created_at,
    attempt.updated_at
  from public.meta_outbound_send_attempts attempt
  where attempt.tenant_id = v_conversation.tenant_id
    and attempt.conversation_id = v_conversation.id
    and (
      attempt.state in ('prepared', 'provider_accepted', 'outcome_unknown')
      or attempt.created_at >= now() - interval '30 days'
    )
  order by attempt.created_at asc, attempt.id asc;
end;
$$;

create or replace function public.mark_meta_outbound_attempt(
  p_attempt_id uuid,
  p_state text,
  p_error_code text default null,
  p_error_message text default null,
  p_provider_response jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_state text := lower(btrim(coalesce(p_state, '')));
  v_attempt public.meta_outbound_send_attempts%rowtype;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta send attempt update requires service role'
      using errcode = '42501';
  end if;
  if v_state not in ('preflight_failed', 'provider_rejected', 'outcome_unknown') then
    raise exception 'Invalid Meta send terminal state' using errcode = '22023';
  end if;

  select attempt.* into v_attempt
  from public.meta_outbound_send_attempts attempt
  where attempt.id = p_attempt_id
  for update;
  if not found then
    raise exception 'Meta send attempt not found' using errcode = 'P0002';
  end if;

  if v_attempt.state = 'prepared' then
    update public.meta_outbound_send_attempts
    set state = v_state,
        error_code = left(nullif(btrim(p_error_code), ''), 120),
        error_message = left(nullif(btrim(p_error_message), ''), 500),
        provider_response = coalesce(p_provider_response, '{}'::jsonb),
        updated_at = clock_timestamp()
    where id = v_attempt.id
    returning * into v_attempt;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'attempt_id', v_attempt.id,
    'state', v_attempt.state,
    'message_id', v_attempt.message_id,
    'external_message_id', v_attempt.external_message_id,
    'error_code', v_attempt.error_code,
    'error_message', v_attempt.error_message
  ));
end;
$$;

create or replace function public.accept_meta_outbound_attempt(
  p_attempt_id uuid,
  p_external_message_id text,
  p_provider_response jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_external_message_id text := btrim(coalesce(p_external_message_id, ''));
  v_attempt public.meta_outbound_send_attempts%rowtype;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta provider acceptance requires service role'
      using errcode = '42501';
  end if;
  if p_attempt_id is null or v_external_message_id = ''
     or length(v_external_message_id) > 512 then
    raise exception 'Meta provider message id is required' using errcode = '22023';
  end if;

  select attempt.* into v_attempt
  from public.meta_outbound_send_attempts attempt
  where attempt.id = p_attempt_id
  for update;
  if not found then
    raise exception 'Meta send attempt not found' using errcode = 'P0002';
  end if;
  if v_attempt.state in (
    'preflight_failed',
    'provider_rejected',
    'outcome_unknown'
  ) then
    raise exception 'Meta send attempt is already terminal'
      using errcode = '23514';
  end if;
  if v_attempt.external_message_id is not null
     and v_attempt.external_message_id is distinct from v_external_message_id then
    raise exception 'Meta attempt provider id is immutable'
      using errcode = '23514';
  end if;

  if v_attempt.state = 'prepared' then
    update public.meta_outbound_send_attempts
    set state = 'provider_accepted',
        external_message_id = v_external_message_id,
        provider_accepted_at = clock_timestamp(),
        provider_response = coalesce(p_provider_response, '{}'::jsonb),
        error_code = null,
        error_message = null,
        updated_at = clock_timestamp()
    where id = v_attempt.id
    returning * into v_attempt;
  end if;

  return jsonb_build_object(
    'attempt_id', v_attempt.id,
    'state', v_attempt.state,
    'external_message_id', v_attempt.external_message_id,
    'message_id', v_attempt.message_id
  );
end;
$$;

-- Provider acceptance can race a staff archive after begin_meta_outbound_send.
-- Preserve that accepted provider result without reopening the conversation,
-- but only when an exact service-owned attempt authorizes this single insert.
create or replace function public.enforce_messaging_tenant_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_parent_tenant_id uuid;
  v_parent_status text;
  v_parent_type text;
  v_parent_channel text;
  v_resolution_event_capability text;
  v_is_trusted_provider_inbound boolean := false;
  v_is_trusted_meta_inbound boolean := false;
  v_is_trusted_meta_outbound boolean := false;
begin
  if tg_table_name = 'conversations' then
    if tg_op = 'UPDATE' then
      if new.tenant_id is distinct from old.tenant_id then
        raise exception 'Conversation tenant_id is immutable'
          using errcode = '23514';
      end if;
      if new.created_by is distinct from old.created_by then
        raise exception 'Conversation created_by is immutable'
          using errcode = '23514';
      end if;
      if new.channel is distinct from old.channel
         and (
           old.channel in ('instagram', 'facebook_messenger')
           or new.channel in ('instagram', 'facebook_messenger')
         ) then
        raise exception 'Meta conversation channel is immutable'
          using errcode = '23514';
      end if;
    elsif new.tenant_id is null then
      new.tenant_id := public.user_tenant_id();
    end if;

    if new.tenant_id is null then
      raise exception 'Conversation tenant_id is required'
        using errcode = '23502';
    end if;

    if tg_op = 'INSERT'
       and new.channel in ('instagram', 'facebook_messenger')
       and coalesce(auth.jwt()->>'role', auth.role(), '') <> 'service_role' then
      raise exception 'Meta conversations require trusted provider transport'
        using errcode = '42501';
    end if;

    if tg_op = 'INSERT'
       and auth.uid() is not null
       and coalesce(auth.jwt()->>'role', '') = 'authenticated' then
      new.created_by := auth.uid();
    end if;
    return new;
  end if;

  if new.conversation_id is null then
    raise exception '% conversation_id is required', tg_table_name
      using errcode = '23502';
  end if;

  if tg_table_name = 'messages' and tg_op = 'INSERT' then
    select conversation.tenant_id,
           conversation.status,
           conversation.type,
           conversation.channel
    into v_parent_tenant_id,
         v_parent_status,
         v_parent_type,
         v_parent_channel
    from public.conversations conversation
    where conversation.id = new.conversation_id
    for share;
  else
    select conversation.tenant_id,
           conversation.status,
           conversation.type,
           conversation.channel
    into v_parent_tenant_id,
         v_parent_status,
         v_parent_type,
         v_parent_channel
    from public.conversations conversation
    where conversation.id = new.conversation_id;
  end if;

  if v_parent_tenant_id is null then
    raise exception 'Parent conversation not found' using errcode = '23503';
  end if;

  if new.tenant_id is null then
    new.tenant_id := v_parent_tenant_id;
  elsif new.tenant_id is distinct from v_parent_tenant_id then
    raise exception '% tenant_id must match its conversation', tg_table_name
      using errcode = '23514';
  end if;

  -- Keep every reference to message-only columns inside a message-only PL/pgSQL
  -- branch. SQL boolean expressions are not an evaluation-order boundary: when
  -- this generic trigger runs for conversation_participants, the executor may
  -- otherwise inspect new.type/new.metadata and abort with 42703.
  if tg_table_name = 'messages' and tg_op = 'INSERT' then
    v_resolution_event_capability := nullif(current_setting(
      'app.messaging_resolution_event_conversation_id',
      true
    ), '');

    if v_parent_channel in ('instagram', 'facebook_messenger')
       and not coalesce((
         v_resolution_event_capability = new.conversation_id::text
         and new.type = 'system'
         and coalesce(new.metadata, '{}'::jsonb)->>'event' =
           'conversation_resolved'
       ), false) then
      v_is_trusted_meta_inbound := coalesce(
        coalesce(auth.jwt()->>'role', auth.role(), '') = 'service_role'
        and v_parent_type = 'support'
        and new.sender_id is null
        and new.type = 'text'
        and new.external_provider = v_parent_channel
        and new.message_direction = 'inbound'
        and nullif(btrim(coalesce(new.external_message_id, '')), '') is not null
        and exists (
          select 1
          from public.meta_webhook_events event
          join public.meta_conversation_bindings binding
            on binding.channel_id = event.channel_id
           and binding.tenant_id = event.tenant_id
           and binding.conversation_id = new.conversation_id
          where event.tenant_id = new.tenant_id
            and event.conversation_id = new.conversation_id
            and event.event_type = 'message'
            and event.direction = 'inbound'
            and event.external_message_id is not null
            and new.external_message_id =
              event.channel_id::text || ':' || event.external_message_id
        ),
        false
      );
      v_is_trusted_meta_outbound := coalesce(
        coalesce(auth.jwt()->>'role', auth.role(), '') = 'service_role'
        and v_parent_type = 'support'
        and v_parent_channel in ('instagram', 'facebook_messenger')
        and new.sender_id is not null
        and new.type = 'text'
        and new.external_provider = v_parent_channel
        and new.message_direction = 'outbound'
        and nullif(btrim(coalesce(new.external_message_id, '')), '') is not null
        and exists (
          select 1
          from public.meta_outbound_send_attempts attempt
          where attempt.id::text = coalesce(new.metadata, '{}'::jsonb)
            ->> 'meta_attempt_id'
            and attempt.tenant_id = new.tenant_id
            and attempt.conversation_id = new.conversation_id
            and attempt.actor_id = new.sender_id
            and attempt.state = 'provider_accepted'
            and new.external_message_id =
              attempt.channel_id::text || ':' || attempt.external_message_id
        ),
        false
      );

      if not (v_is_trusted_meta_inbound or v_is_trusted_meta_outbound) then
        raise exception 'Meta conversations require trusted provider transport'
          using errcode = '42501';
      end if;
    end if;

    if coalesce(v_parent_status, '') not in ('pending', 'active') then
      v_is_trusted_provider_inbound := coalesce(
        coalesce(auth.jwt()->>'role', auth.role(), '') = 'service_role'
        and v_parent_type = 'support'
        and v_parent_channel = 'whatsapp'
        and new.sender_id is null
        and coalesce(new.type, '') in ('text', 'image', 'file')
        and coalesce(new.external_provider, '') = 'whatsapp'
        and coalesce(new.message_direction, '') = 'inbound'
        and nullif(btrim(coalesce(new.external_message_id, '')), '') is not null
        and exists (
          select 1
          from public.whatsapp_webhook_events event
          join public.whatsapp_conversation_bindings binding
            on binding.channel_id = event.channel_id
           and binding.tenant_id = event.tenant_id
           and binding.conversation_id = new.conversation_id
          where event.tenant_id = new.tenant_id
            and event.event_key = 'message:' || new.external_message_id
            and event.event_type = 'message'
            and event.direction = 'inbound'
            and event.payload #>> '{message,id}' = new.external_message_id
        ),
        false
      );

      if not coalesce((
        (
          v_resolution_event_capability = new.conversation_id::text
          and new.type = 'system'
          and coalesce(new.metadata, '{}'::jsonb)->>'event' =
            'conversation_resolved'
        )
        or v_is_trusted_provider_inbound
        or v_is_trusted_meta_inbound
        or v_is_trusted_meta_outbound
      ), false) then
        raise exception 'Conversation is closed to new messages'
          using errcode = '23514';
      end if;
    end if;
  end if;

  if tg_table_name = 'conversation_contexts' then
    if not public.messaging_context_belongs_to_tenant(
      new.context_type,
      new.context_id,
      v_parent_tenant_id
    ) then
      raise exception 'Messaging context does not belong to the conversation tenant'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.finalize_meta_outbound_send(
  p_attempt_id uuid,
  p_external_message_id text,
  p_provider_response jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_raw_message_id text := btrim(coalesce(p_external_message_id, ''));
  v_attempt public.meta_outbound_send_attempts%rowtype;
  v_channel public.meta_channels%rowtype;
  v_binding public.meta_conversation_bindings%rowtype;
  v_message public.messages%rowtype;
  v_canonical_message_id text;
  v_replayed_status text;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta send finalization requires service role'
      using errcode = '42501';
  end if;
  if p_attempt_id is null or v_raw_message_id = ''
     or length(v_raw_message_id) > 512 then
    raise exception 'Meta provider message id is required' using errcode = '22023';
  end if;

  select attempt.* into v_attempt
  from public.meta_outbound_send_attempts attempt
  where attempt.id = p_attempt_id
  for update;
  if not found then
    raise exception 'Meta send attempt not found' using errcode = 'P0002';
  end if;
  if v_attempt.state = 'finalized' then
    if v_attempt.external_message_id is distinct from v_raw_message_id then
      raise exception 'Meta attempt already finalized with another provider id'
        using errcode = '23514';
    end if;
    return jsonb_build_object(
      'replayed', true,
      'attempt_id', v_attempt.id,
      'state', v_attempt.state,
      'message_id', v_attempt.message_id,
      'client_message_id', v_attempt.idempotency_key,
      'external_message_id', v_attempt.external_message_id,
      'external_status', 'accepted'
    );
  end if;
  if v_attempt.state not in ('prepared', 'provider_accepted') then
    raise exception 'Meta send attempt is already terminal'
      using errcode = '23514';
  end if;
  if v_attempt.external_message_id is not null
     and v_attempt.external_message_id is distinct from v_raw_message_id then
    raise exception 'Meta attempt provider id is immutable'
      using errcode = '23514';
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.id = v_attempt.channel_id
    and channel.tenant_id = v_attempt.tenant_id;
  select binding.* into v_binding
  from public.meta_conversation_bindings binding
  where binding.id = v_attempt.binding_id
    and binding.tenant_id = v_attempt.tenant_id;
  if v_channel.id is null or v_binding.id is null then
    raise exception 'Meta send attempt dependencies are missing'
      using errcode = '23503';
  end if;

  update public.meta_outbound_send_attempts
  set state = 'provider_accepted',
      external_message_id = v_raw_message_id,
      provider_accepted_at = coalesce(provider_accepted_at, clock_timestamp()),
      provider_response = coalesce(p_provider_response, '{}'::jsonb),
      error_code = null,
      error_message = null,
      updated_at = clock_timestamp()
  where id = v_attempt.id
  returning * into v_attempt;

  v_canonical_message_id := v_attempt.channel_id::text || ':' || v_raw_message_id;
  select message.* into v_message
  from public.messages message
  where message.external_message_id = v_canonical_message_id;

  if found then
    if v_message.tenant_id is distinct from v_attempt.tenant_id
       or v_message.conversation_id is distinct from v_attempt.conversation_id
       or v_message.external_provider is distinct from v_channel.provider
       or v_message.message_direction is distinct from 'outbound' then
      raise exception 'Meta provider message id conflicts with another message'
        using errcode = '23514';
    end if;
  else
    insert into public.messages (
      conversation_id,
      sender_id,
      tenant_id,
      content,
      type,
      metadata,
      external_provider,
      external_message_id,
      message_direction,
      external_status,
      created_at
    ) values (
      v_attempt.conversation_id,
      v_attempt.actor_id,
      v_attempt.tenant_id,
      v_attempt.message_text,
      'text',
      jsonb_build_object(
        'provider', v_channel.provider,
        'meta_attempt_id', v_attempt.id,
        'client_message_id', v_attempt.idempotency_key,
        'meta_channel_id', v_attempt.channel_id
      ),
      v_channel.provider,
      v_canonical_message_id,
      'outbound',
      'accepted',
      v_attempt.provider_accepted_at
    ) returning * into v_message;
  end if;

  -- Echo/read/delivery webhooks can beat the Edge Function's final database
  -- write. Back-link that already durable evidence once the exact provider id
  -- has an authoritative message row.
  update public.meta_webhook_events event
  set conversation_id = v_attempt.conversation_id,
      message_id = v_message.id
  where event.channel_id = v_attempt.channel_id
    and event.external_message_id = v_raw_message_id
    and event.event_type in ('message_echo', 'message_status')
    and (event.conversation_id is null
      or event.conversation_id = v_attempt.conversation_id)
    and (event.message_id is null or event.message_id = v_message.id);

  select case
    when bool_or(event.event_type = 'message_status'
      and event.payload->>'status' = 'read') then 'read'
    when bool_or(event.event_type = 'message_status'
      and event.payload->>'status' = 'delivered') then 'delivered'
    when bool_or(event.event_type = 'message_echo') then 'sent'
    else null
  end into v_replayed_status
  from public.meta_webhook_events event
  where event.channel_id = v_attempt.channel_id
    and event.external_message_id = v_raw_message_id;

  if v_replayed_status is not null
     and public.meta_message_status_rank(v_message.external_status) <
       public.meta_message_status_rank(v_replayed_status) then
    update public.messages
    set external_status = v_replayed_status,
        metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
          'meta_status_replayed_at_finalize', true
        )
    where id = v_message.id
    returning * into v_message;
  end if;

  update public.meta_conversation_bindings
  set last_outbound_at = greatest(
        coalesce(last_outbound_at, '-infinity'::timestamptz),
        v_attempt.provider_accepted_at
      ),
      updated_at = clock_timestamp()
  where id = v_attempt.binding_id;

  update public.meta_outbound_send_attempts
  set state = 'finalized',
      message_id = v_message.id,
      finalized_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where id = v_attempt.id
  returning * into v_attempt;

  return jsonb_build_object(
    'replayed', false,
    'attempt_id', v_attempt.id,
    'state', v_attempt.state,
    'message_id', v_message.id,
    'client_message_id', v_attempt.idempotency_key,
    'external_message_id', v_attempt.external_message_id,
    'external_status', v_message.external_status,
    'conversation_id', v_attempt.conversation_id,
    'tenant_id', v_attempt.tenant_id
  );
end;
$$;

-- SECURITY DEFINER routines default to PUBLIC EXECUTE. Every transport command
-- is service-only; authenticated clients call the Edge Functions instead.
revoke all on function public.enforce_meta_tenant_consistency()
  from public, anon, authenticated, service_role;
revoke all on function public.normalize_conversation_channel()
  from public, anon, authenticated, service_role;
revoke all on function public.store_meta_channel_credential(
  uuid, text, text, text, text, text, text[], timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public.mark_meta_channel_subscribed(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_meta_channel_access_token(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.create_meta_oauth_state(
  uuid, uuid, text, text, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public.consume_meta_oauth_state(text)
  from public, anon, authenticated, service_role;
revoke all on function public.ensure_meta_conversation_binding(
  uuid, text, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.meta_message_status_rank(text)
  from public, anon, authenticated, service_role;
revoke all on function public.ingest_meta_message(
  text, text, text, text, text, text, text, text, text, timestamptz, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.record_meta_echo_event(
  text, text, text, text, text, timestamptz, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.record_meta_message_status(
  text, text, text, text, text, text, timestamptz, timestamptz, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.ingest_meta_interaction(
  text, text, text, text, text, text, text, text, text, text,
  timestamptz, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.begin_meta_outbound_send(
  uuid, uuid, text, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.get_meta_conversation_transport(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.list_meta_outbound_send_receipts(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.mark_meta_outbound_attempt(
  uuid, text, text, text, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.accept_meta_outbound_attempt(uuid, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.finalize_meta_outbound_send(uuid, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.enforce_messaging_tenant_consistency()
  from public, anon, authenticated, service_role;

grant execute on function public.store_meta_channel_credential(
  uuid, text, text, text, text, text, text[], timestamptz
) to service_role;
grant execute on function public.mark_meta_channel_subscribed(uuid)
  to service_role;
grant execute on function public.get_meta_channel_access_token(uuid)
  to service_role;
grant execute on function public.create_meta_oauth_state(
  uuid, uuid, text, text, timestamptz
) to service_role;
grant execute on function public.consume_meta_oauth_state(text)
  to service_role;
grant execute on function public.ensure_meta_conversation_binding(
  uuid, text, text, text
) to service_role;
grant execute on function public.ingest_meta_message(
  text, text, text, text, text, text, text, text, text, timestamptz, jsonb
) to service_role;
grant execute on function public.record_meta_echo_event(
  text, text, text, text, text, timestamptz, jsonb
) to service_role;
grant execute on function public.record_meta_message_status(
  text, text, text, text, text, text, timestamptz, timestamptz, jsonb
) to service_role;
grant execute on function public.ingest_meta_interaction(
  text, text, text, text, text, text, text, text, text, text,
  timestamptz, jsonb
) to service_role;
grant execute on function public.begin_meta_outbound_send(
  uuid, uuid, text, text, text
) to service_role;
grant execute on function public.get_meta_conversation_transport(uuid)
  to authenticated;
grant execute on function public.list_meta_outbound_send_receipts(uuid)
  to authenticated;
grant execute on function public.mark_meta_outbound_attempt(
  uuid, text, text, text, jsonb
) to service_role;
grant execute on function public.accept_meta_outbound_attempt(uuid, text, jsonb)
  to service_role;
grant execute on function public.finalize_meta_outbound_send(uuid, text, jsonb)
  to service_role;

comment on function public.begin_meta_outbound_send(
  uuid, uuid, text, text, text
) is 'Creates an exact replay receipt and enforces the standard Meta 24-hour reply window before any provider call.';
comment on function public.get_meta_conversation_transport(uuid)
  is 'Returns only provider and reply-window state for an authorized Meta conversation; external account and user identifiers stay service-only.';
comment on function public.finalize_meta_outbound_send(uuid, text, jsonb)
  is 'Atomically preserves provider acceptance as an outbound message, including an archive race and early webhook replay.';

commit;
