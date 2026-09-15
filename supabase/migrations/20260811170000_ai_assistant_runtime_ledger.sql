-- Durable, provider-neutral runtime ledger for the ERP AI assistant.
--
-- ERP reads, run admission/replay and post-admission mutations retain the
-- operator JWT and derive auth.uid(). Each of the four post-admission mutators
-- additionally requires a short-lived server HMAC attestation bound to its
-- exact canonical body, actor, tenant, authority, run, lease, fence, operation
-- and single-use nonce. There is deliberately no service-role/custom-JWT path
-- and no direct table DML grant. Provider
-- continuations, reasoning payloads, prompts, raw tool arguments/results and
-- exception text are not canonical state and are never stored here.

begin;

create schema if not exists assistant_runtime;
revoke all on schema assistant_runtime from public, anon, authenticated,
  service_role;
grant usage on schema assistant_runtime to authenticated;
alter default privileges in schema assistant_runtime
  revoke execute on functions from public, anon, authenticated, service_role;

create table if not exists assistant_runtime.attestation_keys (
  key_id text primary key
    check (key_id ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'),
  vault_secret_id uuid not null unique,
  audience text not null
    check (audience ~ '^supabase:[a-z0-9][a-z0-9_-]{2,63}:assistant-runtime$'),
  is_active boolean not null default true,
  not_before timestamptz not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default statement_timestamp(),
  check (not_before < expires_at),
  check (not_before >= created_at - interval '5 minutes'),
  check (expires_at <= created_at + interval '400 days')
);

create table if not exists assistant_runtime.attestation_nonces (
  nonce uuid primary key,
  key_id text not null references assistant_runtime.attestation_keys(key_id),
  operation text not null check (operation in (
    'assistant_heartbeat_run_v2',
    'assistant_record_provider_attempt_v2',
    'assistant_record_tool_receipt_v2',
    'assistant_complete_run_v2'
  )),
  actor_user_id uuid not null,
  tenant_id uuid not null,
  authority_fingerprint text not null
    check (authority_fingerprint ~ '^[0-9a-f]{64}$'),
  run_id uuid not null,
  lease_token uuid not null,
  fence_token bigint not null check (fence_token > 0),
  envelope_hash text not null check (envelope_hash ~ '^[0-9a-f]{64}$'),
  body_hash text not null check (body_hash ~ '^[0-9a-f]{64}$'),
  mac_hash text not null check (mac_hash ~ '^[0-9a-f]{64}$'),
  response jsonb not null,
  created_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null default statement_timestamp() + interval '15 minutes',
  check (expires_at > created_at),
  check (expires_at <= created_at + interval '15 minutes')
);
create index if not exists assistant_attestation_nonces_expiry_idx
  on assistant_runtime.attestation_nonces(expires_at);

alter table assistant_runtime.attestation_keys enable row level security;
alter table assistant_runtime.attestation_keys force row level security;
alter table assistant_runtime.attestation_nonces enable row level security;
alter table assistant_runtime.attestation_nonces force row level security;
revoke all on table assistant_runtime.attestation_keys,
  assistant_runtime.attestation_nonces
from public, anon, authenticated, service_role;

create table if not exists public.assistant_threads (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  state text not null default 'active'
    check (state in ('active', 'archived', 'deleted')),
  title text check (title is null or octet_length(title) <= 160),
  canonical_summary text
    check (canonical_summary is null or octet_length(canonical_summary) <= 4000),
  authority_role text not null check (octet_length(authority_role) between 1 and 32),
  authority_fingerprint text not null
    check (authority_fingerprint ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  last_activity_at timestamptz not null default statement_timestamp(),
  transcript_expires_at timestamptz not null default statement_timestamp() + interval '90 days',
  ledger_expires_at timestamptz not null default statement_timestamp() + interval '365 days',
  unique (tenant_id, actor_user_id, id)
);

create table if not exists public.assistant_messages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  actor_user_id uuid not null,
  thread_id uuid not null,
  sequence_no integer not null check (sequence_no > 0),
  role text not null check (role in ('user', 'assistant', 'notice')),
  content text not null check (octet_length(content) between 1 and 65536),
  cards jsonb not null default '[]'::jsonb,
  run_id uuid,
  created_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null default statement_timestamp() + interval '90 days',
  unique (tenant_id, actor_user_id, id),
  unique (thread_id, sequence_no),
  foreign key (tenant_id, actor_user_id, thread_id)
    references public.assistant_threads(tenant_id, actor_user_id, id)
    on delete cascade
);

create table if not exists public.assistant_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  actor_user_id uuid not null,
  thread_id uuid not null,
  run_no integer not null check (run_no > 0),
  client_request_id uuid not null,
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  request_message_id uuid,
  response_message_id uuid,
  model_role text not null check (model_role in ('fast', 'deep', 'vision')),
  status text not null default 'running'
    check (status in (
      'queued', 'running', 'waiting_tool', 'succeeded', 'failed',
      'cancelled', 'timed_out'
    )),
  authority_role text not null check (octet_length(authority_role) between 1 and 32),
  authority_fingerprint text not null
    check (authority_fingerprint ~ '^[0-9a-f]{64}$'),
  turn_budget integer not null check (turn_budget between 1 and 20),
  provider_attempt_budget integer not null
    check (provider_attempt_budget between 2 and 42),
  tool_call_budget integer not null check (tool_call_budget between 0 and 40),
  max_output_tokens integer not null check (max_output_tokens between 64 and 8192),
  input_tokens bigint not null default 0 check (input_tokens >= 0),
  output_tokens bigint not null default 0 check (output_tokens >= 0),
  estimated_cost_microusd bigint not null default 0
    check (estimated_cost_microusd >= 0),
  cancel_requested_at timestamptz,
  started_at timestamptz not null default statement_timestamp(),
  heartbeat_at timestamptz not null default statement_timestamp(),
  completed_at timestamptz,
  error_code text check (
    error_code is null or error_code ~ '^[a-z][a-z0-9_]{0,63}$'
  ),
  created_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null default statement_timestamp() + interval '365 days',
  unique (tenant_id, actor_user_id, id),
  unique (tenant_id, actor_user_id, client_request_id),
  unique (thread_id, run_no),
  foreign key (tenant_id, actor_user_id, thread_id)
    references public.assistant_threads(tenant_id, actor_user_id, id)
    on delete cascade,
  foreign key (tenant_id, actor_user_id, request_message_id)
    references public.assistant_messages(tenant_id, actor_user_id, id)
    on delete set null (request_message_id),
  foreign key (tenant_id, actor_user_id, response_message_id)
    references public.assistant_messages(tenant_id, actor_user_id, id)
    on delete set null (response_message_id)
);

alter table public.assistant_messages
  drop constraint if exists assistant_messages_run_fkey;
alter table public.assistant_messages
  add constraint assistant_messages_run_fkey
  foreign key (tenant_id, actor_user_id, run_id)
  references public.assistant_runs(tenant_id, actor_user_id, id)
  on delete set null (run_id);

create table if not exists public.assistant_provider_attempts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  actor_user_id uuid not null,
  run_id uuid not null,
  attempt_no integer not null check (attempt_no > 0),
  provider text not null check (provider in ('gemini', 'openai', 'anthropic')),
  model text not null check (
    octet_length(model) between 1 and 120
    and model ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]*$'
  ),
  model_role text not null check (model_role in ('fast', 'deep', 'vision')),
  status text not null check (
    status in ('succeeded', 'failed', 'timed_out', 'cancelled')
  ),
  finish_reason text check (
    finish_reason is null or finish_reason in (
      'stop', 'tool_calls', 'length', 'blocked', 'unknown'
    )
  ),
  provider_request_hash text check (
    provider_request_hash is null or provider_request_hash ~ '^[0-9a-f]{64}$'
  ),
  response_hash text check (
    response_hash is null or response_hash ~ '^[0-9a-f]{64}$'
  ),
  input_tokens bigint not null default 0 check (input_tokens >= 0),
  output_tokens bigint not null default 0 check (output_tokens >= 0),
  estimated_cost_microusd bigint not null default 0
    check (estimated_cost_microusd >= 0),
  error_code text check (
    error_code is null or error_code ~ '^[a-z][a-z0-9_]{0,63}$'
  ),
  started_at timestamptz not null,
  completed_at timestamptz,
  created_at timestamptz not null default statement_timestamp(),
  unique (run_id, attempt_no),
  check (completed_at is not null and started_at <= completed_at),
  check (
    (status = 'succeeded' and finish_reason is not null and error_code is null)
    or (status <> 'succeeded' and finish_reason is null and error_code is not null)
  ),
  foreign key (tenant_id, actor_user_id, run_id)
    references public.assistant_runs(tenant_id, actor_user_id, id)
    on delete cascade
);

create table if not exists public.assistant_tool_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  actor_user_id uuid not null,
  run_id uuid not null,
  provider_attempt_id uuid,
  ordinal integer not null check (ordinal > 0),
  provider_call_hash text not null check (provider_call_hash ~ '^[0-9a-f]{64}$'),
  tool_name text not null check (tool_name ~ '^[a-z][a-z0-9_]{1,63}$'),
  tool_version text not null check (tool_version ~ '^v[1-9][0-9]{0,5}$'),
  risk text not null check (risk in (
    'read', 'draft', 'reversible_write', 'sensitive_write',
    'public_research', 'authenticated_browser'
  )),
  policy_decision text not null
    check (policy_decision in ('allowed', 'denied', 'approval_required')),
  status text not null check (status in (
    'succeeded', 'rejected', 'failed', 'timed_out', 'cancelled'
  )),
  arguments_hash text not null check (arguments_hash ~ '^[0-9a-f]{64}$'),
  output_hash text check (output_hash is null or output_hash ~ '^[0-9a-f]{64}$'),
  result_count integer not null default 0 check (result_count >= 0),
  output_bytes integer not null default 0 check (output_bytes >= 0),
  approval_used boolean not null default false,
  read_back_verified boolean not null default false,
  failure_code text check (
    failure_code is null or failure_code ~ '^[a-z][a-z0-9_]{0,63}$'
  ),
  started_at timestamptz not null,
  completed_at timestamptz,
  created_at timestamptz not null default statement_timestamp(),
  unique (run_id, ordinal),
  unique (run_id, provider_call_hash),
  check (completed_at is not null and started_at <= completed_at),
  check (
    (status = 'succeeded' and failure_code is null)
    or (status <> 'succeeded' and failure_code is not null)
  ),
  foreign key (tenant_id, actor_user_id, run_id)
    references public.assistant_runs(tenant_id, actor_user_id, id)
    on delete cascade,
  foreign key (provider_attempt_id)
    references public.assistant_provider_attempts(id)
    on delete set null
);

create table if not exists public.assistant_quota_buckets (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  scope text not null check (scope in ('tenant', 'user')),
  scope_id uuid not null,
  period text not null check (period in ('five_minutes', 'day')),
  window_started_at timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  provider_attempt_count integer not null default 0
    check (provider_attempt_count >= 0),
  tool_call_count integer not null default 0 check (tool_call_count >= 0),
  input_tokens bigint not null default 0 check (input_tokens >= 0),
  output_tokens bigint not null default 0 check (output_tokens >= 0),
  estimated_cost_microusd bigint not null default 0
    check (estimated_cost_microusd >= 0),
  updated_at timestamptz not null default statement_timestamp(),
  primary key (tenant_id, scope, scope_id, period, window_started_at),
  check (scope <> 'tenant' or scope_id = tenant_id)
);

create table if not exists public.assistant_run_leases (
  run_id uuid primary key,
  tenant_id uuid not null,
  actor_user_id uuid not null,
  lease_token uuid not null unique,
  fence_token bigint not null check (fence_token > 0),
  lease_owner text not null check (octet_length(lease_owner) between 1 and 128),
  acquired_at timestamptz not null default statement_timestamp(),
  heartbeat_at timestamptz not null default statement_timestamp(),
  lease_expires_at timestamptz not null,
  foreign key (tenant_id, actor_user_id, run_id)
    references public.assistant_runs(tenant_id, actor_user_id, id)
    on delete cascade
);

create index if not exists assistant_threads_actor_activity_idx
  on public.assistant_threads(tenant_id, actor_user_id, last_activity_at desc);
create index if not exists assistant_messages_thread_created_idx
  on public.assistant_messages(thread_id, sequence_no);
create index if not exists assistant_runs_recovery_idx
  on public.assistant_runs(status, heartbeat_at)
  where status in ('queued', 'running', 'waiting_tool');
create index if not exists assistant_runs_retention_idx
  on public.assistant_runs(expires_at);
create index if not exists assistant_messages_retention_idx
  on public.assistant_messages(expires_at);
create index if not exists assistant_leases_expiry_idx
  on public.assistant_run_leases(lease_expires_at);

alter table public.assistant_threads enable row level security;
alter table public.assistant_threads force row level security;
alter table public.assistant_messages enable row level security;
alter table public.assistant_messages force row level security;
alter table public.assistant_runs enable row level security;
alter table public.assistant_runs force row level security;
alter table public.assistant_provider_attempts enable row level security;
alter table public.assistant_provider_attempts force row level security;
alter table public.assistant_tool_receipts enable row level security;
alter table public.assistant_tool_receipts force row level security;
alter table public.assistant_quota_buckets enable row level security;
alter table public.assistant_quota_buckets force row level security;
alter table public.assistant_run_leases enable row level security;
alter table public.assistant_run_leases force row level security;

revoke all on table public.assistant_threads,
  public.assistant_messages,
  public.assistant_runs,
  public.assistant_provider_attempts,
  public.assistant_tool_receipts,
  public.assistant_quota_buckets,
  public.assistant_run_leases
from public, anon, authenticated, service_role;
create or replace function public.assistant_current_authority_internal_v1()
returns table (
  tenant_id uuid,
  actor_user_id uuid,
  authority_role text,
  permissions jsonb,
  capabilities jsonb,
  authority_fingerprint text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, extensions, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_tenant_id uuid;
  v_count integer;
  v_profile record;
  v_owner boolean;
  v_permissions jsonb;
  v_capabilities text[];
begin
  if v_user_id is null or coalesce(auth.role(), '') <> 'authenticated' then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select count(*), min(profile.tenant_id::text)::uuid
  into v_count, v_tenant_id
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id and tenant.is_active is true
  where profile.user_id = v_user_id and profile.is_active is true;

  if v_count <> 1 or v_tenant_id is null then
    raise exception 'A single active tenant is required' using errcode = '42501';
  end if;

  select profile.role as role,
         coalesce(profile.permissions, '{}'::jsonb) as permissions,
         tenant.owner_email as owner_email,
         auth_user.email as email,
         auth_user.raw_app_meta_data as raw_app_meta_data
  into strict v_profile
  from public.user_profiles profile
  join public.tenants tenant on tenant.id = profile.tenant_id
  join auth.users auth_user on auth_user.id = profile.user_id
  where profile.user_id = v_user_id
    and profile.tenant_id = v_tenant_id
    and profile.is_active is true
    and tenant.is_active is true;

  if v_profile.role not in ('admin', 'manager', 'cashier', 'mechanic', 'accountant') then
    raise exception 'Account access is invalid' using errcode = '42501';
  end if;

  v_owner := (
    nullif(lower(btrim(v_profile.email)), '') is not null
    and lower(btrim(v_profile.email)) = lower(btrim(v_profile.owner_email))
  ) or (
    v_profile.raw_app_meta_data ->> 'account_type' = 'erp_owner'
    and v_profile.raw_app_meta_data ->> 'tenant_id' = v_tenant_id::text
  );
  tenant_id := v_tenant_id;
  authority_role := case when v_owner then 'owner' else v_profile.role end;
  actor_user_id := v_user_id;
  v_permissions := v_profile.permissions;
  permissions := v_permissions;
  v_capabilities := array['ai.read.operational']::text[];
  if authority_role in ('owner', 'admin', 'manager', 'cashier', 'accountant')
     or v_permissions @> '{"create_invoices":true}'::jsonb
     or v_permissions @> '{"access_accounting":true}'::jsonb then
    v_capabilities := array_append(v_capabilities, 'ai.read.sales');
  end if;
  if authority_role in ('owner', 'admin', 'manager', 'accountant')
     or v_permissions @> '{"access_accounting":true}'::jsonb then
    v_capabilities := array_append(v_capabilities, 'ai.read.purchases');
  end if;
  capabilities := to_jsonb(v_capabilities);
  authority_fingerprint := encode(extensions.digest(
    convert_to(jsonb_build_object(
      'tenantId', tenant_id,
      'actorUserId', actor_user_id,
      'role', authority_role,
      'permissions', permissions,
      'capabilities', capabilities
    )::text, 'UTF8'), 'sha256'), 'hex');
  return next;
end;
$$;

revoke all on function public.assistant_current_authority_internal_v1()
from public, anon, authenticated, service_role;

create or replace function public.assistant_server_authority_internal_v1(
  p_tenant_id uuid,
  p_actor_user_id uuid,
  p_authority_fingerprint text
)
returns table (
  tenant_id uuid,
  actor_user_id uuid,
  authority_role text,
  permissions jsonb,
  capabilities jsonb,
  authority_fingerprint text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_current record;
begin
  if p_tenant_id is null or p_actor_user_id is null
     or coalesce(p_authority_fingerprint, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid runtime authority' using errcode = '22023';
  end if;
  select * into strict v_current
  from public.assistant_current_authority_internal_v1();
  if v_current.tenant_id <> p_tenant_id
     or v_current.actor_user_id <> p_actor_user_id then
    raise exception 'Runtime actor access is invalid' using errcode = '42501';
  end if;
  if v_current.authority_fingerprint <> p_authority_fingerprint then
    raise exception 'Runtime authority fingerprint is stale' using errcode = '42501';
  end if;
  tenant_id := v_current.tenant_id;
  actor_user_id := v_current.actor_user_id;
  authority_role := v_current.authority_role;
  permissions := v_current.permissions;
  capabilities := v_current.capabilities;
  authority_fingerprint := v_current.authority_fingerprint;
  return next;
end;
$$;

revoke all on function public.assistant_server_authority_internal_v1(uuid, uuid, text)
from public, anon, authenticated, service_role;

create or replace function assistant_runtime.assistant_canonical_json_internal_v1(
  p_value jsonb
)
returns text
language plpgsql
immutable
set search_path = pg_catalog, assistant_runtime, pg_temp
as $$
declare
  v_type text := jsonb_typeof(p_value);
  v_scalar text;
  v_result text;
begin
  if v_type = 'null' then return 'null'; end if;
  if v_type = 'boolean' then return p_value::text; end if;
  if v_type = 'string' then return p_value::text; end if;
  if v_type = 'number' then
    v_scalar := p_value #>> '{}';
    if v_scalar !~ '^-?(0|[1-9][0-9]*)$'
       or v_scalar::numeric not between -9007199254740991 and 9007199254740991 then
      raise exception 'Attested JSON number is invalid' using errcode = '22023';
    end if;
    return v_scalar;
  end if;
  if v_type = 'array' then
    select '[' || coalesce(string_agg(
      assistant_runtime.assistant_canonical_json_internal_v1(element.value),
      ',' order by element.ordinality
    ), '') || ']'
    into v_result
    from jsonb_array_elements(p_value) with ordinality element(value, ordinality);
    return v_result;
  end if;
  if v_type = 'object' then
    if exists (
      select 1 from jsonb_object_keys(p_value) object_key(key)
      where key !~ '^[A-Za-z0-9_]+$'
    ) then
      raise exception 'Attested JSON key is invalid' using errcode = '22023';
    end if;
    select '{' || coalesce(string_agg(
      to_jsonb(member.key)::text || ':' ||
        assistant_runtime.assistant_canonical_json_internal_v1(member.value),
      ',' order by member.key collate "C"
    ), '') || '}'
    into v_result
    from jsonb_each(p_value) member(key, value);
    return v_result;
  end if;
  raise exception 'Attested JSON value is invalid' using errcode = '22023';
end;
$$;

create or replace function assistant_runtime.assistant_json_has_exact_keys_internal_v1(
  p_value jsonb,
  p_expected text[]
)
returns boolean
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_typeof(p_value) = 'object'
    and coalesce((
      select array_agg(object_key.key order by object_key.key collate "C")
      from jsonb_object_keys(p_value) object_key(key)
    ), array[]::text[]) = (
      select coalesce(array_agg(expected.key order by expected.key collate "C"), array[]::text[])
      from unnest(p_expected) expected(key)
    )
$$;

create or replace function assistant_runtime.assistant_constant_time_hex_equal_internal_v1(
  p_left text,
  p_right text
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  v_left bytea;
  v_right bytea;
  v_difference integer := 0;
  v_index integer;
begin
  if p_left !~ '^[0-9a-f]{64}$' or p_right !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  v_left := decode(p_left, 'hex');
  v_right := decode(p_right, 'hex');
  for v_index in 0..31 loop
    v_difference := v_difference | (get_byte(v_left, v_index) # get_byte(v_right, v_index));
  end loop;
  return v_difference = 0;
end;
$$;

create or replace function assistant_runtime.assistant_verify_attestation_internal_v1(
  p_operation text,
  p_envelope text,
  p_body text,
  p_mac_hex text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, assistant_runtime, extensions, vault, pg_temp
as $$
declare
  v_lines text[];
  v_key_id text;
  v_audience text;
  v_nonce uuid;
  v_issued_at bigint;
  v_expires_at bigint;
  v_actor_user_id uuid;
  v_tenant_id uuid;
  v_authority_fingerprint text;
  v_run_id uuid;
  v_lease_token uuid;
  v_fence_token bigint;
  v_body_bytes integer;
  v_now_epoch bigint := floor(extract(epoch from statement_timestamp()))::bigint;
  v_body jsonb;
  v_authority record;
  v_key record;
  v_receipt assistant_runtime.attestation_nonces%rowtype;
  v_envelope_hash text;
  v_body_hash text;
  v_mac_hash text;
  v_expected_mac text;
begin
  if p_operation not in (
       'assistant_heartbeat_run_v2',
       'assistant_record_provider_attempt_v2',
       'assistant_record_tool_receipt_v2',
       'assistant_complete_run_v2'
     )
     or p_envelope is null or p_body is null or p_mac_hex is null
     or octet_length(p_envelope) > 2048
     or octet_length(p_body) > 131072
     or octet_length(p_envelope) <> length(p_envelope)
     or position(E'\r' in p_envelope) > 0
     or right(p_envelope, 1) = E'\n'
     or p_mac_hex !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid runtime attestation' using errcode = '22023';
  end if;
  v_lines := string_to_array(p_envelope, E'\n');
  if cardinality(v_lines) <> 15
     or v_lines[1] <> 'VINABIKE-AI-ATTESTATION-V1'
     or v_lines[2] !~ '^kid=[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
     or v_lines[3] !~ '^aud=supabase:[a-z0-9][a-z0-9_-]{2,63}:assistant-runtime$'
     or v_lines[4] <> 'iss=ai-agent-gateway'
     or v_lines[5] <> 'op=' || p_operation
     or v_lines[6] !~ '^nonce=[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or v_lines[7] !~ '^iat=[0-9]{1,12}$'
     or v_lines[8] !~ '^exp=[0-9]{1,12}$'
     or v_lines[9] !~ '^sub=[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or v_lines[10] !~ '^tenant=[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or v_lines[11] !~ '^authority=[0-9a-f]{64}$'
     or v_lines[12] !~ '^run=[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or v_lines[13] !~ '^lease=[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or v_lines[14] !~ '^fence=[1-9][0-9]{0,18}$'
     or v_lines[15] !~ '^body-bytes=(0|[1-9][0-9]{0,6})$' then
    raise exception 'Invalid runtime attestation' using errcode = '22023';
  end if;

  v_key_id := substr(v_lines[2], 5);
  v_audience := substr(v_lines[3], 5);
  v_nonce := substr(v_lines[6], 7)::uuid;
  v_issued_at := substr(v_lines[7], 5)::bigint;
  v_expires_at := substr(v_lines[8], 5)::bigint;
  v_actor_user_id := substr(v_lines[9], 5)::uuid;
  v_tenant_id := substr(v_lines[10], 8)::uuid;
  v_authority_fingerprint := substr(v_lines[11], 11);
  v_run_id := substr(v_lines[12], 5)::uuid;
  v_lease_token := substr(v_lines[13], 7)::uuid;
  v_fence_token := substr(v_lines[14], 7)::bigint;
  v_body_bytes := substr(v_lines[15], 12)::integer;
  if v_body_bytes <> octet_length(p_body) then
    raise exception 'Invalid runtime attestation' using errcode = '22023';
  end if;

  -- This transaction-level nonce lock is deliberately first. Every mutator
  -- continues with nonce -> tenant -> user -> thread -> run -> lease ordering.
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:attestation:' || v_nonce::text, 0
  ));

  begin
    v_body := p_body::jsonb;
  exception when others then
    raise exception 'Invalid runtime attestation body' using errcode = '22023';
  end;
  if assistant_runtime.assistant_canonical_json_internal_v1(v_body) <> p_body
     or v_body ->> 'p_actor_user_id' <> v_actor_user_id::text
     or v_body ->> 'p_tenant_id' <> v_tenant_id::text
     or v_body ->> 'p_authority_fingerprint' <> v_authority_fingerprint
     or v_body ->> 'p_run_id' <> v_run_id::text
     or v_body ->> 'p_lease_token' <> v_lease_token::text
     or v_body ->> 'p_fence_token' <> v_fence_token::text then
    raise exception 'Runtime attestation binding mismatch' using errcode = '42501';
  end if;

  select * into strict v_authority
  from public.assistant_current_authority_internal_v1();
  if v_authority.actor_user_id <> v_actor_user_id
     or v_authority.tenant_id <> v_tenant_id
     or v_authority.authority_fingerprint <> v_authority_fingerprint then
    raise exception 'Runtime attestation caller mismatch' using errcode = '42501';
  end if;

  v_envelope_hash := encode(extensions.digest(convert_to(p_envelope, 'UTF8'), 'sha256'), 'hex');
  v_body_hash := encode(extensions.digest(convert_to(p_body, 'UTF8'), 'sha256'), 'hex');
  v_mac_hash := encode(extensions.digest(convert_to(p_mac_hex, 'UTF8'), 'sha256'), 'hex');
  select * into v_receipt
  from assistant_runtime.attestation_nonces receipt
  where receipt.nonce = v_nonce;
  if found then
    if v_receipt.expires_at <= statement_timestamp()
       or v_receipt.key_id <> v_key_id
       or v_receipt.operation <> p_operation
       or v_receipt.actor_user_id <> v_actor_user_id
       or v_receipt.tenant_id <> v_tenant_id
       or v_receipt.authority_fingerprint <> v_authority_fingerprint
       or v_receipt.run_id <> v_run_id
       or v_receipt.lease_token <> v_lease_token
       or v_receipt.fence_token <> v_fence_token
       or v_receipt.envelope_hash <> v_envelope_hash
       or v_receipt.body_hash <> v_body_hash
       or v_receipt.mac_hash <> v_mac_hash then
      raise exception 'Runtime attestation nonce was already consumed'
        using errcode = '42501';
    end if;
    return jsonb_build_object(
      'replayed', true,
      'response', v_receipt.response,
      'nonce', v_nonce,
      'keyId', v_key_id,
      'operation', p_operation,
      'actorUserId', v_actor_user_id,
      'tenantId', v_tenant_id,
      'authorityFingerprint', v_authority_fingerprint,
      'runId', v_run_id,
      'leaseToken', v_lease_token,
      'fenceToken', v_fence_token,
      'envelopeHash', v_envelope_hash,
      'bodyHash', v_body_hash,
      'macHash', v_mac_hash
    );
  end if;

  if v_expires_at <> v_issued_at + 60
     or v_issued_at > v_now_epoch + 5
     or v_expires_at <= v_now_epoch then
    raise exception 'Runtime attestation expired' using errcode = '42501';
  end if;
  select metadata.*, decrypted.decrypted_secret
  into strict v_key
  from assistant_runtime.attestation_keys metadata
  join vault.decrypted_secrets decrypted
    on decrypted.id = metadata.vault_secret_id
  where metadata.key_id = v_key_id
    and metadata.audience = v_audience
    and metadata.is_active is true
    and metadata.not_before <= statement_timestamp()
    and metadata.expires_at > statement_timestamp();
  if v_key.decrypted_secret !~ '^[0-9A-Fa-f]{64}$' then
    raise exception 'Runtime attestation key is invalid' using errcode = '42501';
  end if;
  v_expected_mac := encode(extensions.hmac(
    convert_to(p_envelope, 'UTF8') || decode('00', 'hex') || convert_to(p_body, 'UTF8'),
    decode(lower(v_key.decrypted_secret), 'hex'),
    'sha256'
  ), 'hex');
  if not assistant_runtime.assistant_constant_time_hex_equal_internal_v1(
    p_mac_hex, v_expected_mac
  ) then
    raise exception 'Runtime attestation signature is invalid' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'replayed', false,
    'response', null,
    'nonce', v_nonce,
    'keyId', v_key_id,
    'operation', p_operation,
    'actorUserId', v_actor_user_id,
    'tenantId', v_tenant_id,
    'authorityFingerprint', v_authority_fingerprint,
    'runId', v_run_id,
    'leaseToken', v_lease_token,
    'fenceToken', v_fence_token,
    'envelopeHash', v_envelope_hash,
    'bodyHash', v_body_hash,
    'macHash', v_mac_hash
  );
exception
  when no_data_found then
    raise exception 'Runtime attestation key is unavailable' using errcode = '42501';
end;
$$;

create or replace function assistant_runtime.assistant_store_attestation_response_internal_v1(
  p_attestation jsonb,
  p_response jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, assistant_runtime, pg_temp
as $$
begin
  if p_attestation ->> 'replayed' <> 'false' or p_response is null then
    raise exception 'Invalid runtime attestation receipt' using errcode = '22023';
  end if;
  insert into assistant_runtime.attestation_nonces (
    nonce, key_id, operation, actor_user_id, tenant_id,
    authority_fingerprint, run_id, lease_token, fence_token,
    envelope_hash, body_hash, mac_hash, response
  ) values (
    (p_attestation ->> 'nonce')::uuid,
    p_attestation ->> 'keyId',
    p_attestation ->> 'operation',
    (p_attestation ->> 'actorUserId')::uuid,
    (p_attestation ->> 'tenantId')::uuid,
    p_attestation ->> 'authorityFingerprint',
    (p_attestation ->> 'runId')::uuid,
    (p_attestation ->> 'leaseToken')::uuid,
    (p_attestation ->> 'fenceToken')::bigint,
    p_attestation ->> 'envelopeHash',
    p_attestation ->> 'bodyHash',
    p_attestation ->> 'macHash',
    p_response
  );
  return p_response;
end;
$$;

revoke all on function assistant_runtime.assistant_canonical_json_internal_v1(jsonb),
  assistant_runtime.assistant_json_has_exact_keys_internal_v1(jsonb, text[]),
  assistant_runtime.assistant_constant_time_hex_equal_internal_v1(text, text),
  assistant_runtime.assistant_verify_attestation_internal_v1(text, text, text, text),
  assistant_runtime.assistant_store_attestation_response_internal_v1(jsonb, jsonb)
from public, anon, authenticated, service_role;

create or replace function public.assistant_get_authority_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select jsonb_build_object(
    'authorityTenantId', authority.tenant_id,
    'actorUserId', authority.actor_user_id,
    'role', authority.authority_role,
    'permissions', authority.permissions,
    'capabilities', authority.capabilities,
    'authorityFingerprint', authority.authority_fingerprint,
    'asOf', statement_timestamp()
  )
  from public.assistant_current_authority_internal_v1() authority
$$;

create or replace function public.assistant_cards_valid_v1(p_cards jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  v_card jsonb;
  v_chip jsonb;
  v_entity_ref jsonb;
  v_kind text;
  v_destination text;
begin
  if p_cards is null or jsonb_typeof(p_cards) <> 'array'
     or jsonb_array_length(p_cards) > 6 then
    return false;
  end if;
  for v_card in select value from jsonb_array_elements(p_cards) element(value)
  loop
    if jsonb_typeof(v_card) <> 'object'
       or not (v_card ? 'kind' and v_card ? 'title'
         and v_card ? 'destination' and v_card ? 'chips')
       or jsonb_typeof(v_card -> 'kind') <> 'string'
       or jsonb_typeof(v_card -> 'title') <> 'string'
       or jsonb_typeof(v_card -> 'destination') <> 'string'
       or jsonb_typeof(v_card -> 'chips') <> 'array'
       or (v_card ? 'eyebrow' and jsonb_typeof(v_card -> 'eyebrow') <> 'string')
       or (v_card ? 'subtitle' and jsonb_typeof(v_card -> 'subtitle') <> 'string')
       or (v_card ? 'description' and jsonb_typeof(v_card -> 'description') <> 'string')
       or (v_card ? 'entityRef' and jsonb_typeof(v_card -> 'entityRef') <> 'object')
       or exists (
         select 1 from jsonb_object_keys(v_card) key
         where key not in (
           'kind', 'title', 'destination', 'eyebrow', 'subtitle',
           'description', 'chips', 'entityRef'
         )
       ) then
      return false;
    end if;
    v_kind := v_card ->> 'kind';
    v_destination := v_card ->> 'destination';
    if v_kind !~ '^[a-z][a-z0-9_]{0,31}$'
       or octet_length(v_kind) > 32
       or octet_length(v_card ->> 'title') not between 1 and 160
       or octet_length(coalesce(v_card ->> 'eyebrow', '')) > 80
       or octet_length(coalesce(v_card ->> 'subtitle', '')) > 240
       or octet_length(coalesce(v_card ->> 'description', '')) > 500
       or not (
         (v_kind = 'customer' and v_destination = 'customers')
         or (v_kind = 'supplier' and v_destination = 'suppliers')
         or (v_kind = 'job' and v_destination = 'workshop_jobs')
         or (v_kind = 'sales_invoice' and v_destination = 'sales_invoices')
         or (v_kind = 'purchase_invoice' and v_destination = 'purchases')
         or (v_kind = 'inventory' and v_destination = 'inventory_products')
         or (v_kind = 'task' and v_destination = 'tasks')
         or (v_kind = 'expense' and v_destination = 'expenses')
         or (v_kind = 'conversation' and v_destination = 'conversations')
       )
       or jsonb_array_length(v_card -> 'chips') > 4 then
      return false;
    end if;
    if v_card ? 'entityRef' then
      v_entity_ref := v_card -> 'entityRef';
      if not (v_entity_ref ? 'kind' and v_entity_ref ? 'id')
         or jsonb_typeof(v_entity_ref -> 'kind') <> 'string'
         or jsonb_typeof(v_entity_ref -> 'id') <> 'string'
         or exists (
           select 1 from jsonb_object_keys(v_entity_ref) key
           where key not in ('kind', 'id')
         )
         or lower(v_entity_ref ->> 'id') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         or not (
           (v_kind = 'customer' and v_entity_ref ->> 'kind' = 'customer')
           or (v_kind = 'supplier' and v_entity_ref ->> 'kind' = 'supplier')
           or (v_kind = 'job' and v_entity_ref ->> 'kind' = 'workshopJob')
           or (v_kind = 'sales_invoice' and v_entity_ref ->> 'kind' = 'salesInvoice')
           or (v_kind = 'purchase_invoice' and v_entity_ref ->> 'kind' = 'purchaseInvoice')
           or (v_kind = 'inventory' and v_entity_ref ->> 'kind' = 'product')
           or (v_kind = 'expense' and v_entity_ref ->> 'kind' = 'expense')
           or (v_kind = 'conversation' and v_entity_ref ->> 'kind' = 'conversation')
         ) then
        return false;
      end if;
    end if;
    for v_chip in select value
      from jsonb_array_elements(v_card -> 'chips') element(value)
    loop
      if jsonb_typeof(v_chip) <> 'string'
         or octet_length(v_chip #>> '{}') not between 1 and 64 then
        return false;
      end if;
    end loop;
  end loop;
  return true;
end;
$$;

revoke all on function public.assistant_cards_valid_v1(jsonb)
from public, anon, authenticated, service_role;

alter table public.assistant_messages
  drop constraint if exists assistant_messages_cards_check;
alter table public.assistant_messages
  add constraint assistant_messages_cards_check
  check (public.assistant_cards_valid_v1(cards));

create or replace function public.assistant_run_snapshot_internal_v1(
  p_run_id uuid,
  p_replayed boolean,
  p_lease_token uuid,
  p_fence_token bigint,
  p_lease_expires_at timestamptz
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select jsonb_build_object(
    'authorityTenantId', run.tenant_id,
    'actorUserId', run.actor_user_id,
    'authorityFingerprint', run.authority_fingerprint,
    'threadId', run.thread_id,
    'runId', run.id,
    'runNo', run.run_no,
    'runStatus', run.status,
    'replayed', p_replayed,
    'leaseToken', p_lease_token,
    'fenceToken', p_fence_token,
    'leaseExpiresAt', p_lease_expires_at,
    'nextProviderAttemptNo', coalesce((
      select max(attempt.attempt_no) + 1
      from public.assistant_provider_attempts attempt
      where attempt.run_id = run.id
    ), 1),
    'nextToolOrdinal', coalesce((
      select max(receipt.ordinal) + 1
      from public.assistant_tool_receipts receipt
      where receipt.run_id = run.id
    ), 1),
    'canonicalSummary', thread.canonical_summary,
    'canonicalMessages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'messageId', visible.id,
        'sequenceNo', visible.sequence_no,
        'role', visible.role,
        'content', visible.content,
        'cards', visible.cards,
        'createdAt', visible.created_at
      ) order by visible.sequence_no)
      from (
        select message.id, message.sequence_no, message.role, message.content,
          message.cards, message.created_at
        from public.assistant_messages message
        where message.thread_id = run.thread_id
          and message.expires_at > statement_timestamp()
          and message.role in ('user', 'assistant')
          and not exists (
            select 1
            from public.assistant_runs terminal_run
            where terminal_run.request_message_id = message.id
              and terminal_run.status in ('failed', 'cancelled', 'timed_out')
          )
        order by message.sequence_no desc
        limit 20
      ) visible
    ), '[]'::jsonb),
    'response', case when response.id is null then null else jsonb_build_object(
      'messageId', response.id,
      'sequenceNo', response.sequence_no,
      'content', response.content,
      'cards', response.cards,
      'createdAt', response.created_at
    ) end
  )
  from public.assistant_runs run
  join public.assistant_threads thread on thread.id = run.thread_id
    and thread.state = 'active'
    and thread.authority_fingerprint = run.authority_fingerprint
    and thread.transcript_expires_at > statement_timestamp()
  left join public.assistant_messages response on response.id = run.response_message_id
    and response.expires_at > statement_timestamp()
  where run.id = p_run_id
    and run.expires_at > statement_timestamp()
$$;

revoke all on function public.assistant_run_snapshot_internal_v1(
  uuid, boolean, uuid, bigint, timestamptz
) from public, anon, authenticated, service_role;

create or replace function public.assistant_begin_run_v1(
  p_client_request_id uuid,
  p_request_hash text,
  p_user_content text,
  p_model_role text,
  p_thread_id uuid default null,
  p_turn_budget integer default 5,
  p_tool_call_budget integer default 8,
  p_max_output_tokens integer default 2048,
  p_lease_owner text default 'ai-agent-gateway-v1',
  p_lease_ttl_seconds integer default 110
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  v_authority record;
  v_existing public.assistant_runs%rowtype;
  v_thread public.assistant_threads%rowtype;
  v_run_id uuid;
  v_request_message_id uuid;
  v_run_no integer;
  v_sequence_no integer;
  v_lease_token uuid;
  v_fence_token bigint;
  v_lease_expires_at timestamptz;
  v_admitted boolean;
  v_live_count integer;
begin
  select * into strict v_authority
  from public.assistant_current_authority_internal_v1();

  if p_client_request_id is null
     or coalesce(p_request_hash, '') !~ '^[0-9a-f]{64}$'
     or octet_length(coalesce(p_user_content, '')) not between 1 and 8192
     or p_model_role not in ('fast', 'deep', 'vision')
     or p_turn_budget <> 5
     or p_tool_call_budget <> 8
     or p_max_output_tokens not between 64 and 8192
     or p_lease_owner <> 'ai-agent-gateway-v1'
     or p_lease_ttl_seconds <> 110 then
    raise exception 'Invalid assistant run request' using errcode = '22023';
  end if;

  -- Serialize identical client request ids before the replay lookup.  Without
  -- this lock two first requests can both miss and race on the unique index.
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:request:' || v_authority.actor_user_id::text || ':'
      || p_client_request_id::text, 0
  ));
  -- Every admission/replay/reclaim follows request -> tenant -> user advisory
  -- order before touching ledger rows. This also makes concurrency admission
  -- deterministic under a duplicate request race.
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:tenant:' || v_authority.tenant_id::text, 0
  ));
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:user:' || v_authority.actor_user_id::text, 0
  ));

  select * into v_existing
  from public.assistant_runs run
  where run.tenant_id = v_authority.tenant_id
    and run.actor_user_id = v_authority.actor_user_id
    and run.client_request_id = p_client_request_id
  for update;

  if found then
    if v_existing.request_hash <> p_request_hash then
      raise exception 'Client request id was already used with different content'
        using errcode = '22023';
    end if;
    if v_existing.authority_fingerprint <> v_authority.authority_fingerprint then
      raise exception 'Assistant authority changed; start a new thread'
        using errcode = '42501';
    end if;
    if v_existing.expires_at <= statement_timestamp() then
      raise exception 'Assistant run is unavailable' using errcode = '42501';
    end if;
    if not exists (
      select 1 from public.assistant_threads thread
      where thread.id = v_existing.thread_id
        and thread.state = 'active'
        and thread.authority_fingerprint = v_authority.authority_fingerprint
        and thread.transcript_expires_at > statement_timestamp()
        and thread.ledger_expires_at > statement_timestamp()
    ) then
      raise exception 'Assistant thread is unavailable' using errcode = '42501';
    end if;
    if v_existing.status = 'succeeded' and not exists (
      select 1 from public.assistant_messages response
      where response.id = v_existing.response_message_id
        and response.thread_id = v_existing.thread_id
        and response.role = 'assistant'
        and response.expires_at > statement_timestamp()
    ) then
      raise exception 'Assistant terminal response is unavailable'
        using errcode = '42501';
    end if;

    if v_existing.status in ('queued', 'running', 'waiting_tool') then
      select lease.lease_token, lease.fence_token, lease.lease_expires_at
      into v_lease_token, v_fence_token, v_lease_expires_at
      from public.assistant_run_leases lease
      where lease.run_id = v_existing.id
      for update;

      if not found or v_lease_expires_at <= statement_timestamp() then
        select count(*) into v_live_count
        from public.assistant_runs run
        join public.assistant_run_leases lease on lease.run_id = run.id
        where run.tenant_id = v_authority.tenant_id
          and run.id <> v_existing.id
          and run.status in ('queued', 'running', 'waiting_tool')
          and lease.lease_expires_at > statement_timestamp();
        if v_live_count >= 4 then
          raise exception 'Assistant tenant concurrency limit reached' using errcode = 'P0001';
        end if;
        select count(*) into v_live_count
        from public.assistant_runs run
        join public.assistant_run_leases lease on lease.run_id = run.id
        where run.tenant_id = v_authority.tenant_id
          and run.actor_user_id = v_authority.actor_user_id
          and run.id <> v_existing.id
          and run.status in ('queued', 'running', 'waiting_tool')
          and lease.lease_expires_at > statement_timestamp();
        if v_live_count >= 2 then
          raise exception 'Assistant user concurrency limit reached' using errcode = 'P0001';
        end if;
        v_lease_token := gen_random_uuid();
        v_lease_expires_at := statement_timestamp()
          + make_interval(secs => p_lease_ttl_seconds);
        insert into public.assistant_run_leases (
          run_id, tenant_id, actor_user_id, lease_token, fence_token,
          lease_owner, acquired_at, heartbeat_at, lease_expires_at
        ) values (
          v_existing.id, v_authority.tenant_id, v_authority.actor_user_id,
          v_lease_token, coalesce(v_fence_token, 0) + 1, p_lease_owner,
          statement_timestamp(), statement_timestamp(), v_lease_expires_at
        )
        on conflict (run_id) do update set
          lease_token = excluded.lease_token,
          fence_token = public.assistant_run_leases.fence_token + 1,
          lease_owner = excluded.lease_owner,
          acquired_at = excluded.acquired_at,
          heartbeat_at = excluded.heartbeat_at,
          lease_expires_at = excluded.lease_expires_at
        returning fence_token into v_fence_token;
        update public.assistant_runs set heartbeat_at = statement_timestamp()
        where id = v_existing.id;
      else
        return public.assistant_run_snapshot_internal_v1(
          v_existing.id, true, null, null, null
        ) || jsonb_build_object(
          'runDisposition', 'in_progress', 'terminalErrorCode', null
        );
      end if;
    else
      v_lease_token := null;
      v_fence_token := null;
      v_lease_expires_at := null;
    end if;

    return public.assistant_run_snapshot_internal_v1(
      v_existing.id, true, v_lease_token, v_fence_token, v_lease_expires_at
    ) || jsonb_build_object(
      'runDisposition', case when v_lease_token is null then 'terminal' else 'claimed' end,
      'terminalErrorCode', v_existing.error_code
    );
  end if;

  -- Serialize admission for this tenant and operator.  The counts include only
  -- live, non-expired worker leases; an abandoned run becomes reclaimable.
  select count(*) into v_live_count
  from public.assistant_runs run
  join public.assistant_run_leases lease on lease.run_id = run.id
  where run.tenant_id = v_authority.tenant_id
    and run.status in ('queued', 'running', 'waiting_tool')
    and lease.lease_expires_at > statement_timestamp();
  if v_live_count >= 4 then
    raise exception 'Assistant tenant concurrency limit reached' using errcode = 'P0001';
  end if;
  select count(*) into v_live_count
  from public.assistant_runs run
  join public.assistant_run_leases lease on lease.run_id = run.id
  where run.tenant_id = v_authority.tenant_id
    and run.actor_user_id = v_authority.actor_user_id
    and run.status in ('queued', 'running', 'waiting_tool')
    and lease.lease_expires_at > statement_timestamp();
  if v_live_count >= 2 then
    raise exception 'Assistant user concurrency limit reached' using errcode = 'P0001';
  end if;

  insert into public.assistant_quota_buckets (
    tenant_id, scope, scope_id, period, window_started_at, request_count
  ) values (
    v_authority.tenant_id, 'user', v_authority.actor_user_id,
    'five_minutes', date_bin('5 minutes', statement_timestamp(),
      '2000-01-01 00:00:00+00'::timestamptz), 1
  )
  on conflict (tenant_id, scope, scope_id, period, window_started_at) do update set
    request_count = public.assistant_quota_buckets.request_count + 1,
    updated_at = statement_timestamp()
  where public.assistant_quota_buckets.request_count < 10
  returning true into v_admitted;
  if coalesce(v_admitted, false) is not true then
    raise exception 'Assistant request quota exceeded' using errcode = 'P0001';
  end if;
  v_admitted := null;
  insert into public.assistant_quota_buckets (
    tenant_id, scope, scope_id, period, window_started_at, request_count
  ) values (
    v_authority.tenant_id, 'tenant', v_authority.tenant_id,
    'five_minutes', date_bin('5 minutes', statement_timestamp(),
      '2000-01-01 00:00:00+00'::timestamptz), 1
  )
  on conflict (tenant_id, scope, scope_id, period, window_started_at) do update set
    request_count = public.assistant_quota_buckets.request_count + 1,
    updated_at = statement_timestamp()
  where public.assistant_quota_buckets.request_count < 30
  returning true into v_admitted;
  if coalesce(v_admitted, false) is not true then
    raise exception 'Assistant tenant quota exceeded' using errcode = 'P0001';
  end if;
  v_admitted := null;
  insert into public.assistant_quota_buckets (
    tenant_id, scope, scope_id, period, window_started_at, request_count
  ) values
    (v_authority.tenant_id, 'user', v_authority.actor_user_id, 'day',
      date_trunc('day', statement_timestamp()), 1),
    (v_authority.tenant_id, 'tenant', v_authority.tenant_id, 'day',
      date_trunc('day', statement_timestamp()), 1)
  on conflict (tenant_id, scope, scope_id, period, window_started_at) do update set
    request_count = public.assistant_quota_buckets.request_count + 1,
    updated_at = statement_timestamp();
  -- Five-minute buckets above are hard admission controls (10/user,
  -- 30/tenant). Day buckets are accounting telemetry for capacity review;
  -- they intentionally do not claim to be an enforced daily quota.

  if p_thread_id is null then
    insert into public.assistant_threads (
      tenant_id, actor_user_id, authority_role, authority_fingerprint
    ) values (
      v_authority.tenant_id, v_authority.actor_user_id,
      v_authority.authority_role, v_authority.authority_fingerprint
    ) returning * into v_thread;
  else
    select * into v_thread
    from public.assistant_threads thread
    where thread.id = p_thread_id
      and thread.tenant_id = v_authority.tenant_id
      and thread.actor_user_id = v_authority.actor_user_id
      and thread.state = 'active'
      and thread.authority_fingerprint = v_authority.authority_fingerprint
      and thread.transcript_expires_at > statement_timestamp()
      and thread.ledger_expires_at > statement_timestamp()
    for update;
    if not found then
      raise exception 'Assistant thread is unavailable' using errcode = '42501';
    end if;
  end if;

  select coalesce(max(run.run_no), 0) + 1 into v_run_no
  from public.assistant_runs run where run.thread_id = v_thread.id;
  select coalesce(max(message.sequence_no), 0) + 1 into v_sequence_no
  from public.assistant_messages message where message.thread_id = v_thread.id;

  insert into public.assistant_messages (
    tenant_id, actor_user_id, thread_id, sequence_no, role, content
  ) values (
    v_authority.tenant_id, v_authority.actor_user_id, v_thread.id,
    v_sequence_no, 'user', p_user_content
  ) returning id into v_request_message_id;

  insert into public.assistant_runs (
    tenant_id, actor_user_id, thread_id, run_no, client_request_id,
    request_hash, request_message_id, model_role, status, authority_role,
    authority_fingerprint, turn_budget, provider_attempt_budget,
    tool_call_budget, max_output_tokens
  ) values (
    v_authority.tenant_id, v_authority.actor_user_id, v_thread.id, v_run_no,
    p_client_request_id, p_request_hash, v_request_message_id, p_model_role,
    'running', v_authority.authority_role, v_authority.authority_fingerprint,
    p_turn_budget, 2 * (p_turn_budget + 1), p_tool_call_budget, p_max_output_tokens
  ) returning id into v_run_id;

  update public.assistant_messages set run_id = v_run_id
  where id = v_request_message_id;
  update public.assistant_threads set
    updated_at = statement_timestamp(),
    last_activity_at = statement_timestamp(),
    transcript_expires_at = greatest(
      transcript_expires_at, statement_timestamp() + interval '90 days'
    ),
    ledger_expires_at = greatest(
      ledger_expires_at, statement_timestamp() + interval '365 days'
    )
  where id = v_thread.id;

  v_lease_token := gen_random_uuid();
  v_fence_token := 1;
  v_lease_expires_at := statement_timestamp()
    + make_interval(secs => p_lease_ttl_seconds);
  insert into public.assistant_run_leases (
    run_id, tenant_id, actor_user_id, lease_token, fence_token,
    lease_owner, lease_expires_at
  ) values (
    v_run_id, v_authority.tenant_id, v_authority.actor_user_id,
    v_lease_token, v_fence_token, p_lease_owner, v_lease_expires_at
  );

  return public.assistant_run_snapshot_internal_v1(
    v_run_id, false, v_lease_token, v_fence_token, v_lease_expires_at
  ) || jsonb_build_object('runDisposition', 'claimed', 'terminalErrorCode', null);
end;
$$;

create or replace function public.assistant_assert_live_lease_internal_v1(
  p_tenant_id uuid,
  p_actor_user_id uuid,
  p_authority_fingerprint text,
  p_run_id uuid,
  p_lease_token uuid,
  p_fence_token bigint
)
returns public.assistant_runs
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_authority record;
  v_preflight public.assistant_runs%rowtype;
  v_run public.assistant_runs%rowtype;
begin
  select * into strict v_authority
  from public.assistant_server_authority_internal_v1(
    p_tenant_id, p_actor_user_id, p_authority_fingerprint
  );
  select run.* into v_preflight
  from public.assistant_runs run
  where run.id = p_run_id
    and run.tenant_id = v_authority.tenant_id
    and run.actor_user_id = v_authority.actor_user_id
    and run.authority_fingerprint = v_authority.authority_fingerprint;
  if not found then
    raise exception 'Assistant run lease is stale or unavailable'
      using errcode = '42501';
  end if;
  perform 1 from public.assistant_threads thread
  where thread.id = v_preflight.thread_id for update;
  select run.* into v_run
  from public.assistant_runs run
  join public.assistant_run_leases lease on lease.run_id = run.id
  where run.id = p_run_id
    and run.tenant_id = v_authority.tenant_id
    and run.actor_user_id = v_authority.actor_user_id
    and run.authority_fingerprint = v_authority.authority_fingerprint
    and run.status in ('queued', 'running', 'waiting_tool')
    and lease.lease_token = p_lease_token
    and lease.fence_token = p_fence_token
    and lease.lease_expires_at > statement_timestamp()
  for update of run, lease;
  if not found then
    raise exception 'Assistant run lease is stale or unavailable'
      using errcode = '42501';
  end if;
  return v_run;
end;
$$;

revoke all on function public.assistant_assert_live_lease_internal_v1(
  uuid, uuid, text, uuid, uuid, bigint
) from public, anon, authenticated, service_role;

create or replace function assistant_runtime.assistant_heartbeat_run_v1(
  p_tenant_id uuid,
  p_actor_user_id uuid,
  p_authority_fingerprint text,
  p_run_id uuid,
  p_lease_token uuid,
  p_fence_token bigint,
  p_lease_ttl_seconds integer default 110
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_authority record;
  v_run public.assistant_runs%rowtype;
  v_expires timestamptz;
begin
  if p_lease_ttl_seconds <> 110 then
    raise exception 'Invalid assistant lease TTL' using errcode = '22023';
  end if;
  select * into strict v_authority
  from public.assistant_server_authority_internal_v1(
    p_tenant_id, p_actor_user_id, p_authority_fingerprint
  );
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:tenant:' || v_authority.tenant_id::text, 0
  ));
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:user:' || v_authority.actor_user_id::text, 0
  ));
  v_run := public.assistant_assert_live_lease_internal_v1(
    p_tenant_id, p_actor_user_id, p_authority_fingerprint,
    p_run_id, p_lease_token, p_fence_token
  );
  v_expires := statement_timestamp() + make_interval(secs => p_lease_ttl_seconds);
  update public.assistant_run_leases set
    heartbeat_at = statement_timestamp(), lease_expires_at = v_expires
  where run_id = p_run_id and lease_token = p_lease_token
    and fence_token = p_fence_token;
  update public.assistant_runs set heartbeat_at = statement_timestamp()
  where id = p_run_id;
  return jsonb_build_object(
    'authorityTenantId', v_run.tenant_id,
    'runId', v_run.id,
    'runStatus', v_run.status,
    'fenceToken', p_fence_token,
    'leaseExpiresAt', v_expires,
    'cancelRequested', v_run.cancel_requested_at is not null
  );
end;
$$;

create or replace function assistant_runtime.assistant_record_provider_attempt_v1(
  p_tenant_id uuid,
  p_actor_user_id uuid,
  p_authority_fingerprint text,
  p_run_id uuid,
  p_lease_token uuid,
  p_fence_token bigint,
  p_attempt_no integer,
  p_provider text,
  p_model text,
  p_model_role text,
  p_status text,
  p_finish_reason text default null,
  p_input_tokens bigint default 0,
  p_output_tokens bigint default 0,
  p_estimated_cost_microusd bigint default 0,
  p_provider_request_hash text default null,
  p_response_hash text default null,
  p_error_code text default null,
  p_started_at timestamptz default statement_timestamp(),
  p_completed_at timestamptz default statement_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_authority record;
  v_run public.assistant_runs%rowtype;
  v_attempt public.assistant_provider_attempts%rowtype;
begin
  select * into strict v_authority
  from public.assistant_server_authority_internal_v1(
    p_tenant_id, p_actor_user_id, p_authority_fingerprint
  );
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:tenant:' || v_authority.tenant_id::text, 0
  ));
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:user:' || v_authority.actor_user_id::text, 0
  ));
  v_run := public.assistant_assert_live_lease_internal_v1(
    p_tenant_id, p_actor_user_id, p_authority_fingerprint,
    p_run_id, p_lease_token, p_fence_token
  );
  if p_attempt_no <> coalesce((
       select max(attempt.attempt_no) + 1
       from public.assistant_provider_attempts attempt
       where attempt.run_id = p_run_id
     ), 1)
     or p_attempt_no > v_run.provider_attempt_budget
     or p_model_role <> v_run.model_role
     or p_input_tokens not between 0 and 2000000
     or p_output_tokens not between 0 and v_run.max_output_tokens
     or p_estimated_cost_microusd not between 0 and 1000000000000
     or p_status not in ('succeeded', 'failed', 'timed_out', 'cancelled')
     or (p_status = 'succeeded' and
       (p_finish_reason is null or p_error_code is not null
        or p_provider_request_hash is null or p_response_hash is null))
     or (p_status <> 'succeeded' and
       (p_finish_reason is not null or p_error_code is null
        or p_provider_request_hash is null or p_response_hash is not null))
     or p_started_at is null or p_completed_at is null
     or p_started_at < statement_timestamp() - interval '10 minutes'
     or p_started_at > statement_timestamp() + interval '1 minute'
     or p_completed_at < p_started_at
     or p_completed_at > statement_timestamp() + interval '1 minute' then
    raise exception 'Invalid provider attempt counters' using errcode = '22023';
  end if;

  insert into public.assistant_provider_attempts (
    tenant_id, actor_user_id, run_id, attempt_no, provider, model,
    model_role, status, finish_reason, provider_request_hash, response_hash,
    input_tokens, output_tokens, estimated_cost_microusd, error_code,
    started_at, completed_at
  ) values (
    v_run.tenant_id, v_run.actor_user_id, v_run.id, p_attempt_no, p_provider,
    p_model, p_model_role, p_status, p_finish_reason, p_provider_request_hash,
    p_response_hash, p_input_tokens, p_output_tokens,
    p_estimated_cost_microusd, p_error_code, p_started_at, p_completed_at
  ) returning * into v_attempt;

  update public.assistant_runs set
    input_tokens = input_tokens + p_input_tokens,
    output_tokens = output_tokens + p_output_tokens,
    estimated_cost_microusd = estimated_cost_microusd + p_estimated_cost_microusd,
    heartbeat_at = statement_timestamp()
  where id = p_run_id;

  -- Usage may land after the admission window rolled over. Upsert the current
  -- accounting buckets so incurred cost is never silently lost at a boundary.
  insert into public.assistant_quota_buckets (
    tenant_id, scope, scope_id, period, window_started_at,
    provider_attempt_count, input_tokens, output_tokens,
    estimated_cost_microusd
  ) values
    (v_run.tenant_id, 'user', v_run.actor_user_id, 'five_minutes',
      date_bin('5 minutes', statement_timestamp(),
        '2000-01-01 00:00:00+00'::timestamptz),
      1, p_input_tokens, p_output_tokens, p_estimated_cost_microusd),
    (v_run.tenant_id, 'tenant', v_run.tenant_id, 'five_minutes',
      date_bin('5 minutes', statement_timestamp(),
        '2000-01-01 00:00:00+00'::timestamptz),
      1, p_input_tokens, p_output_tokens, p_estimated_cost_microusd),
    (v_run.tenant_id, 'user', v_run.actor_user_id, 'day',
      date_trunc('day', statement_timestamp()),
      1, p_input_tokens, p_output_tokens, p_estimated_cost_microusd),
    (v_run.tenant_id, 'tenant', v_run.tenant_id, 'day',
      date_trunc('day', statement_timestamp()),
      1, p_input_tokens, p_output_tokens, p_estimated_cost_microusd)
  on conflict (tenant_id, scope, scope_id, period, window_started_at) do update set
    provider_attempt_count = public.assistant_quota_buckets.provider_attempt_count + 1,
    input_tokens = public.assistant_quota_buckets.input_tokens + excluded.input_tokens,
    output_tokens = public.assistant_quota_buckets.output_tokens + excluded.output_tokens,
    estimated_cost_microusd = public.assistant_quota_buckets.estimated_cost_microusd
      + excluded.estimated_cost_microusd,
    updated_at = statement_timestamp();

  return jsonb_build_object(
    'authorityTenantId', v_run.tenant_id,
    'runId', v_run.id,
    'attemptId', v_attempt.id,
    'attemptNo', v_attempt.attempt_no,
    'status', v_attempt.status,
    'inputTokens', v_attempt.input_tokens,
    'outputTokens', v_attempt.output_tokens,
    'totalTokens', v_attempt.input_tokens + v_attempt.output_tokens,
    'estimatedCostMicrousd', v_attempt.estimated_cost_microusd
  );
end;
$$;

create or replace function assistant_runtime.assistant_record_tool_receipt_v1(
  p_tenant_id uuid,
  p_actor_user_id uuid,
  p_authority_fingerprint text,
  p_run_id uuid,
  p_lease_token uuid,
  p_fence_token bigint,
  p_ordinal integer,
  p_provider_attempt_no integer,
  p_provider_call_hash text,
  p_tool_name text,
  p_tool_version text,
  p_risk text,
  p_policy_decision text,
  p_status text,
  p_arguments_hash text,
  p_output_hash text default null,
  p_result_count integer default 0,
  p_output_bytes integer default 0,
  p_approval_used boolean default false,
  p_read_back_verified boolean default false,
  p_failure_code text default null,
  p_started_at timestamptz default statement_timestamp(),
  p_completed_at timestamptz default statement_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_authority record;
  v_run public.assistant_runs%rowtype;
  v_attempt_id uuid;
  v_receipt_id uuid;
  v_prior_output_bytes bigint;
begin
  select * into strict v_authority
  from public.assistant_server_authority_internal_v1(
    p_tenant_id, p_actor_user_id, p_authority_fingerprint
  );
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:tenant:' || v_authority.tenant_id::text, 0
  ));
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:user:' || v_authority.actor_user_id::text, 0
  ));
  v_run := public.assistant_assert_live_lease_internal_v1(
    p_tenant_id, p_actor_user_id, p_authority_fingerprint,
    p_run_id, p_lease_token, p_fence_token
  );
  -- A tool may finish concurrently with cancellation. Its already-incurred
  -- receipt remains canonical accounting; the gateway heartbeat prevents the
  -- next tool/provider effect and completion must resolve as cancelled.
  select attempt.id into v_attempt_id
  from public.assistant_provider_attempts attempt
  where attempt.run_id = p_run_id
    and attempt.attempt_no = p_provider_attempt_no
    and attempt.status = 'succeeded'
    and attempt.finish_reason = 'tool_calls';
  if v_attempt_id is null then
    raise exception 'Provider attempt is unavailable for tool receipt'
      using errcode = '22023';
  end if;
  select coalesce(sum(receipt.output_bytes), 0)
  into v_prior_output_bytes
  from public.assistant_tool_receipts receipt
  where receipt.run_id = p_run_id;
  if p_ordinal <> coalesce((
       select max(receipt.ordinal) + 1
       from public.assistant_tool_receipts receipt
       where receipt.run_id = p_run_id
     ), 1)
     or p_ordinal > v_run.tool_call_budget
     or p_result_count not between 0 and 10
     or p_output_bytes not between 0 and 49152
     -- Preserve one already-incurred receipt that crosses the 96 KiB run
     -- budget. Edge marks it failed and terminalizes; a further receipt is
     -- rejected because the prior total is already over budget. The absolute
     -- ceiling is 96 KiB plus one maximum 48 KiB receipt.
     or v_prior_output_bytes > 98304
     or v_prior_output_bytes + p_output_bytes > 147456
     or (v_prior_output_bytes + p_output_bytes > 98304 and (
       p_status <> 'failed'
       or p_failure_code <> 'run_tool_output_budget_exhausted'
       or p_read_back_verified is not false
     ))
     or p_tool_name not in (
       'search_inventory', 'list_attention_items', 'get_business_snapshot',
       'search_workshop_jobs',
       'search_tasks', 'search_customers', 'search_suppliers',
       'search_sales_invoices', 'search_purchase_invoices',
       'find_inventory_risks', 'list_recent_expenses',
       'analyze_cash_and_receivables', 'search_conversations',
       'research_public_web', 'prepare_task'
     )
     or p_tool_version <> 'v1'
     or not (
       (p_tool_name = 'research_public_web'
         and p_risk = 'public_research' and p_policy_decision = 'allowed')
       or (p_tool_name = 'prepare_task'
         and p_risk = 'draft' and p_policy_decision = 'approval_required')
       or (p_tool_name not in ('research_public_web', 'prepare_task')
         and p_risk = 'read' and p_policy_decision = 'allowed')
     )
     or p_approval_used is not false
     or p_status not in ('succeeded', 'rejected', 'failed', 'timed_out', 'cancelled')
     or (p_status = 'succeeded' and
       (p_failure_code is not null or p_output_hash is null
        or p_read_back_verified is not true))
     or (p_status <> 'succeeded' and p_failure_code is null)
     or p_started_at is null or p_completed_at is null
     or p_started_at < statement_timestamp() - interval '10 minutes'
     or p_started_at > statement_timestamp() + interval '1 minute'
     or p_completed_at < p_started_at
     or p_completed_at > statement_timestamp() + interval '1 minute' then
    raise exception 'Invalid tool receipt counters' using errcode = '22023';
  end if;

  insert into public.assistant_tool_receipts (
    tenant_id, actor_user_id, run_id, provider_attempt_id, ordinal,
    provider_call_hash, tool_name, tool_version, risk, policy_decision,
    status, arguments_hash, output_hash, result_count, output_bytes,
    approval_used, read_back_verified, failure_code, started_at, completed_at
  ) values (
    v_run.tenant_id, v_run.actor_user_id, v_run.id, v_attempt_id, p_ordinal,
    p_provider_call_hash, p_tool_name, p_tool_version, p_risk,
    p_policy_decision, p_status, p_arguments_hash, p_output_hash,
    p_result_count, p_output_bytes, p_approval_used, p_read_back_verified,
    p_failure_code, p_started_at, p_completed_at
  ) returning id into v_receipt_id;

  insert into public.assistant_quota_buckets (
    tenant_id, scope, scope_id, period, window_started_at, tool_call_count
  ) values
    (v_run.tenant_id, 'user', v_run.actor_user_id, 'five_minutes',
      date_bin('5 minutes', statement_timestamp(),
        '2000-01-01 00:00:00+00'::timestamptz), 1),
    (v_run.tenant_id, 'tenant', v_run.tenant_id, 'five_minutes',
      date_bin('5 minutes', statement_timestamp(),
        '2000-01-01 00:00:00+00'::timestamptz), 1),
    (v_run.tenant_id, 'user', v_run.actor_user_id, 'day',
      date_trunc('day', statement_timestamp()), 1),
    (v_run.tenant_id, 'tenant', v_run.tenant_id, 'day',
      date_trunc('day', statement_timestamp()), 1)
  on conflict (tenant_id, scope, scope_id, period, window_started_at) do update set
    tool_call_count = public.assistant_quota_buckets.tool_call_count + 1,
    updated_at = statement_timestamp();

  return jsonb_build_object(
    'authorityTenantId', v_run.tenant_id,
    'runId', v_run.id,
    'receiptId', v_receipt_id,
    'ordinal', p_ordinal,
    'status', p_status
  );
end;
$$;

create or replace function assistant_runtime.assistant_complete_run_v1(
  p_tenant_id uuid,
  p_actor_user_id uuid,
  p_authority_fingerprint text,
  p_run_id uuid,
  p_lease_token uuid,
  p_fence_token bigint,
  p_status text,
  p_assistant_content text default null,
  p_final_cards jsonb default '[]'::jsonb,
  p_error_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_authority record;
  v_run public.assistant_runs%rowtype;
  v_preflight public.assistant_runs%rowtype;
  v_sequence_no integer;
  v_message_id uuid;
  v_completed_at timestamptz := statement_timestamp();
  v_effective_status text := p_status;
  v_effective_assistant_content text := p_assistant_content;
  v_effective_final_cards jsonb := p_final_cards;
  v_effective_error_code text := p_error_code;
begin
  -- Global order is tenant advisory -> user advisory -> thread -> run -> lease.
  select * into strict v_authority
  from public.assistant_server_authority_internal_v1(
    p_tenant_id, p_actor_user_id, p_authority_fingerprint
  );
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:tenant:' || v_authority.tenant_id::text, 0
  ));
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:user:' || v_authority.actor_user_id::text, 0
  ));
  select run.* into v_preflight
  from public.assistant_runs run
  where run.id = p_run_id
    and run.tenant_id = v_authority.tenant_id
    and run.actor_user_id = v_authority.actor_user_id
    and run.authority_fingerprint = v_authority.authority_fingerprint;
  if not found then
    raise exception 'Assistant run lease is stale or unavailable'
      using errcode = '42501';
  end if;
  perform 1 from public.assistant_threads thread
  where thread.id = v_preflight.thread_id for update;
  v_run := public.assistant_assert_live_lease_internal_v1(
    p_tenant_id, p_actor_user_id, p_authority_fingerprint,
    p_run_id, p_lease_token, p_fence_token
  );
  -- Cancellation wins atomically even when it races with a provider success
  -- or error after the worker's last heartbeat. Discard any response payload;
  -- the cancelled request remains terminal with no assistant message.
  if v_run.cancel_requested_at is not null then
    v_effective_status := 'cancelled';
    v_effective_assistant_content := null;
    v_effective_final_cards := '[]'::jsonb;
    v_effective_error_code := 'run_cancelled';
  end if;
  if v_effective_status not in ('succeeded', 'failed', 'cancelled', 'timed_out')
     or (v_effective_status = 'succeeded' and
       octet_length(coalesce(v_effective_assistant_content, '')) not between 1 and 65536)
     or (v_effective_status <> 'succeeded' and v_effective_assistant_content is not null)
     or v_effective_final_cards is null
     or not public.assistant_cards_valid_v1(v_effective_final_cards)
     or (v_effective_error_code is not null and
       v_effective_error_code !~ '^[a-z][a-z0-9_]{0,63}$')
     or (v_effective_status = 'succeeded' and v_effective_error_code is not null)
     or (v_effective_status <> 'succeeded' and v_effective_error_code is null)
     or (v_effective_status <> 'succeeded' and v_effective_final_cards <> '[]'::jsonb) then
    raise exception 'Invalid assistant terminal response' using errcode = '22023';
  end if;

  if v_effective_status = 'succeeded' then
    select coalesce(max(message.sequence_no), 0) + 1 into v_sequence_no
    from public.assistant_messages message where message.thread_id = v_run.thread_id;
    insert into public.assistant_messages (
      tenant_id, actor_user_id, thread_id, sequence_no, role, content,
      cards, run_id
    ) values (
      v_run.tenant_id, v_run.actor_user_id, v_run.thread_id, v_sequence_no,
      'assistant', v_effective_assistant_content,
      coalesce(v_effective_final_cards, '[]'::jsonb),
      v_run.id
    ) returning id into v_message_id;
  end if;

  update public.assistant_runs set
    status = v_effective_status,
    response_message_id = v_message_id,
    error_code = case when v_effective_status = 'succeeded' then null
      else v_effective_error_code end,
    completed_at = v_completed_at,
    heartbeat_at = v_completed_at
  where id = v_run.id;
  update public.assistant_threads set
    updated_at = v_completed_at,
    last_activity_at = v_completed_at
  where id = v_run.thread_id;
  delete from public.assistant_run_leases
  where run_id = v_run.id and lease_token = p_lease_token
    and fence_token = p_fence_token;

  return public.assistant_run_snapshot_internal_v1(
    v_run.id, false, null, null, null
  ) || jsonb_build_object(
    'completedAt', v_completed_at,
    'terminalErrorCode', case when v_effective_status = 'succeeded' then null
      else v_effective_error_code end
  );
end;
$$;

create or replace function assistant_runtime.assistant_heartbeat_run_v2(
  p_envelope text,
  p_body text,
  p_mac_hex text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, assistant_runtime, pg_temp
as $$
declare
  v_attestation jsonb;
  v_body jsonb := p_body::jsonb;
  v_response jsonb;
begin
  if not assistant_runtime.assistant_json_has_exact_keys_internal_v1(v_body, array[
    'p_actor_user_id', 'p_authority_fingerprint', 'p_fence_token',
    'p_lease_token', 'p_lease_ttl_seconds', 'p_run_id', 'p_tenant_id'
  ]) then
    raise exception 'Invalid heartbeat attestation body' using errcode = '22023';
  end if;
  v_attestation := assistant_runtime.assistant_verify_attestation_internal_v1(
    'assistant_heartbeat_run_v2', p_envelope, p_body, p_mac_hex
  );
  if (v_attestation ->> 'replayed')::boolean then return v_attestation -> 'response'; end if;
  v_response := assistant_runtime.assistant_heartbeat_run_v1(
    (v_body ->> 'p_tenant_id')::uuid,
    (v_body ->> 'p_actor_user_id')::uuid,
    v_body ->> 'p_authority_fingerprint',
    (v_body ->> 'p_run_id')::uuid,
    (v_body ->> 'p_lease_token')::uuid,
    (v_body ->> 'p_fence_token')::bigint,
    (v_body ->> 'p_lease_ttl_seconds')::integer
  );
  return assistant_runtime.assistant_store_attestation_response_internal_v1(
    v_attestation, v_response
  );
end;
$$;

create or replace function assistant_runtime.assistant_record_provider_attempt_v2(
  p_envelope text,
  p_body text,
  p_mac_hex text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, assistant_runtime, pg_temp
as $$
declare
  v_attestation jsonb;
  v_body jsonb := p_body::jsonb;
  v_response jsonb;
begin
  if not assistant_runtime.assistant_json_has_exact_keys_internal_v1(v_body, array[
    'p_actor_user_id', 'p_attempt_no', 'p_authority_fingerprint',
    'p_completed_at', 'p_error_code', 'p_estimated_cost_microusd',
    'p_fence_token', 'p_finish_reason', 'p_input_tokens', 'p_lease_token',
    'p_model', 'p_model_role', 'p_output_tokens', 'p_provider',
    'p_provider_request_hash', 'p_response_hash', 'p_run_id', 'p_started_at',
    'p_status', 'p_tenant_id'
  ]) then
    raise exception 'Invalid provider attestation body' using errcode = '22023';
  end if;
  v_attestation := assistant_runtime.assistant_verify_attestation_internal_v1(
    'assistant_record_provider_attempt_v2', p_envelope, p_body, p_mac_hex
  );
  if (v_attestation ->> 'replayed')::boolean then return v_attestation -> 'response'; end if;
  v_response := assistant_runtime.assistant_record_provider_attempt_v1(
    (v_body ->> 'p_tenant_id')::uuid,
    (v_body ->> 'p_actor_user_id')::uuid,
    v_body ->> 'p_authority_fingerprint',
    (v_body ->> 'p_run_id')::uuid,
    (v_body ->> 'p_lease_token')::uuid,
    (v_body ->> 'p_fence_token')::bigint,
    (v_body ->> 'p_attempt_no')::integer,
    v_body ->> 'p_provider',
    v_body ->> 'p_model',
    v_body ->> 'p_model_role',
    v_body ->> 'p_status',
    v_body ->> 'p_finish_reason',
    (v_body ->> 'p_input_tokens')::bigint,
    (v_body ->> 'p_output_tokens')::bigint,
    (v_body ->> 'p_estimated_cost_microusd')::bigint,
    v_body ->> 'p_provider_request_hash',
    v_body ->> 'p_response_hash',
    v_body ->> 'p_error_code',
    (v_body ->> 'p_started_at')::timestamptz,
    (v_body ->> 'p_completed_at')::timestamptz
  );
  return assistant_runtime.assistant_store_attestation_response_internal_v1(
    v_attestation, v_response
  );
end;
$$;

create or replace function assistant_runtime.assistant_record_tool_receipt_v2(
  p_envelope text,
  p_body text,
  p_mac_hex text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, assistant_runtime, pg_temp
as $$
declare
  v_attestation jsonb;
  v_body jsonb := p_body::jsonb;
  v_response jsonb;
begin
  if not assistant_runtime.assistant_json_has_exact_keys_internal_v1(v_body, array[
    'p_actor_user_id', 'p_approval_used', 'p_arguments_hash',
    'p_authority_fingerprint', 'p_completed_at', 'p_failure_code',
    'p_fence_token', 'p_lease_token', 'p_ordinal', 'p_output_bytes',
    'p_output_hash', 'p_policy_decision', 'p_provider_attempt_no',
    'p_provider_call_hash', 'p_read_back_verified', 'p_result_count', 'p_risk',
    'p_run_id', 'p_started_at', 'p_status', 'p_tenant_id', 'p_tool_name',
    'p_tool_version'
  ]) then
    raise exception 'Invalid tool attestation body' using errcode = '22023';
  end if;
  v_attestation := assistant_runtime.assistant_verify_attestation_internal_v1(
    'assistant_record_tool_receipt_v2', p_envelope, p_body, p_mac_hex
  );
  if (v_attestation ->> 'replayed')::boolean then return v_attestation -> 'response'; end if;
  v_response := assistant_runtime.assistant_record_tool_receipt_v1(
    (v_body ->> 'p_tenant_id')::uuid,
    (v_body ->> 'p_actor_user_id')::uuid,
    v_body ->> 'p_authority_fingerprint',
    (v_body ->> 'p_run_id')::uuid,
    (v_body ->> 'p_lease_token')::uuid,
    (v_body ->> 'p_fence_token')::bigint,
    (v_body ->> 'p_ordinal')::integer,
    (v_body ->> 'p_provider_attempt_no')::integer,
    v_body ->> 'p_provider_call_hash',
    v_body ->> 'p_tool_name',
    v_body ->> 'p_tool_version',
    v_body ->> 'p_risk',
    v_body ->> 'p_policy_decision',
    v_body ->> 'p_status',
    v_body ->> 'p_arguments_hash',
    v_body ->> 'p_output_hash',
    (v_body ->> 'p_result_count')::integer,
    (v_body ->> 'p_output_bytes')::integer,
    (v_body ->> 'p_approval_used')::boolean,
    (v_body ->> 'p_read_back_verified')::boolean,
    v_body ->> 'p_failure_code',
    (v_body ->> 'p_started_at')::timestamptz,
    (v_body ->> 'p_completed_at')::timestamptz
  );
  return assistant_runtime.assistant_store_attestation_response_internal_v1(
    v_attestation, v_response
  );
end;
$$;

create or replace function assistant_runtime.assistant_complete_run_v2(
  p_envelope text,
  p_body text,
  p_mac_hex text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, assistant_runtime, pg_temp
as $$
declare
  v_attestation jsonb;
  v_body jsonb := p_body::jsonb;
  v_response jsonb;
begin
  if not assistant_runtime.assistant_json_has_exact_keys_internal_v1(v_body, array[
    'p_actor_user_id', 'p_assistant_content', 'p_authority_fingerprint',
    'p_error_code', 'p_fence_token', 'p_final_cards', 'p_lease_token',
    'p_run_id', 'p_status', 'p_tenant_id'
  ]) then
    raise exception 'Invalid completion attestation body' using errcode = '22023';
  end if;
  v_attestation := assistant_runtime.assistant_verify_attestation_internal_v1(
    'assistant_complete_run_v2', p_envelope, p_body, p_mac_hex
  );
  if (v_attestation ->> 'replayed')::boolean then return v_attestation -> 'response'; end if;
  v_response := assistant_runtime.assistant_complete_run_v1(
    (v_body ->> 'p_tenant_id')::uuid,
    (v_body ->> 'p_actor_user_id')::uuid,
    v_body ->> 'p_authority_fingerprint',
    (v_body ->> 'p_run_id')::uuid,
    (v_body ->> 'p_lease_token')::uuid,
    (v_body ->> 'p_fence_token')::bigint,
    v_body ->> 'p_status',
    v_body ->> 'p_assistant_content',
    v_body -> 'p_final_cards',
    v_body ->> 'p_error_code'
  );
  return assistant_runtime.assistant_store_attestation_response_internal_v1(
    v_attestation, v_response
  );
end;
$$;

create or replace function public.assistant_request_run_cancel_v1(p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_authority record;
  v_run public.assistant_runs%rowtype;
begin
  select * into strict v_authority
  from public.assistant_current_authority_internal_v1();
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:tenant:' || v_authority.tenant_id::text, 0
  ));
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:user:' || v_authority.actor_user_id::text, 0
  ));
  update public.assistant_runs run set cancel_requested_at = coalesce(
    run.cancel_requested_at, statement_timestamp()
  )
  where run.id = p_run_id
    and run.tenant_id = v_authority.tenant_id
    and run.actor_user_id = v_authority.actor_user_id
    and run.status in ('queued', 'running', 'waiting_tool')
  returning run.* into v_run;
  if not found then
    raise exception 'Assistant run is unavailable' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'authorityTenantId', v_run.tenant_id,
    'runId', v_run.id,
    'runStatus', v_run.status,
    'cancelRequested', true,
    'cancelRequestedAt', v_run.cancel_requested_at
  );
end;
$$;

create or replace function public.assistant_delete_thread_v1(p_thread_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_authority record;
  v_thread public.assistant_threads%rowtype;
  v_deleted_messages integer;
begin
  select * into strict v_authority
  from public.assistant_current_authority_internal_v1();
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:tenant:' || v_authority.tenant_id::text, 0
  ));
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:user:' || v_authority.actor_user_id::text, 0
  ));
  select thread.* into v_thread
  from public.assistant_threads thread
  where thread.id = p_thread_id
    and thread.tenant_id = v_authority.tenant_id
    and thread.actor_user_id = v_authority.actor_user_id
  for update;
  if not found then
    raise exception 'Assistant thread is unavailable' using errcode = '42501';
  end if;
  update public.assistant_runs run set
    status = 'cancelled', cancel_requested_at = coalesce(
      run.cancel_requested_at, statement_timestamp()
    ), completed_at = statement_timestamp(), heartbeat_at = statement_timestamp(),
    error_code = 'thread_deleted'
  where run.thread_id = p_thread_id
    and run.status in ('queued', 'running', 'waiting_tool');
  delete from public.assistant_run_leases lease
  where lease.run_id in (
    select run.id from public.assistant_runs run where run.thread_id = p_thread_id
  );
  delete from public.assistant_messages message
  where message.thread_id = p_thread_id;
  get diagnostics v_deleted_messages = row_count;
  update public.assistant_threads set
    state = 'deleted', title = null, canonical_summary = null,
    updated_at = statement_timestamp(), last_activity_at = statement_timestamp(),
    transcript_expires_at = statement_timestamp()
  where id = p_thread_id;
  return jsonb_build_object(
    'authorityTenantId', v_authority.tenant_id,
    'threadId', p_thread_id, 'state', 'deleted',
    'deletedMessages', v_deleted_messages,
    'deletedAt', statement_timestamp()
  );
end;
$$;

create or replace function assistant_runtime.assistant_purge_expired_runtime_v1(
  p_limit integer default 1000
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_runs integer := 0; v_messages integer := 0; v_threads integer := 0;
  v_quotas integer := 0; v_leases integer := 0; v_scrubbed integer := 0;
  v_attestation_nonces integer := 0;
  v_changed integer := 0;
  v_candidate record;
begin
  if p_limit is null or p_limit not between 1 and 10000 then
    raise exception 'Invalid assistant purge limit' using errcode = '22023';
  end if;
  -- Retention uses the same thread -> run -> lease/message order as explicit
  -- deletion and terminal completion. Expired transcripts are real erasure,
  -- not merely timestamps left for a future cleanup implementation.
  for v_candidate in
    select thread.id
    from public.assistant_threads thread
    where thread.transcript_expires_at <= statement_timestamp()
      and (thread.state <> 'deleted' or exists (
        select 1 from public.assistant_messages message
        where message.thread_id = thread.id
      ) or exists (
        select 1 from public.assistant_runs run
        where run.thread_id = thread.id
          and run.status in ('queued', 'running', 'waiting_tool')
      ))
    order by thread.transcript_expires_at
    limit p_limit
    for update skip locked
  loop
    update public.assistant_runs run set
      status = 'cancelled',
      cancel_requested_at = coalesce(run.cancel_requested_at, statement_timestamp()),
      completed_at = statement_timestamp(), heartbeat_at = statement_timestamp(),
      error_code = 'thread_expired'
    where run.thread_id = v_candidate.id
      and run.status in ('queued', 'running', 'waiting_tool');
    delete from public.assistant_run_leases lease
    where lease.run_id in (
      select run.id from public.assistant_runs run
      where run.thread_id = v_candidate.id
    );
    get diagnostics v_changed = row_count;
    v_leases := v_leases + v_changed;
    delete from public.assistant_messages message
    where message.thread_id = v_candidate.id;
    get diagnostics v_changed = row_count;
    v_messages := v_messages + v_changed;
    update public.assistant_threads set
      title = null, canonical_summary = null, state = 'deleted',
      updated_at = statement_timestamp(), last_activity_at = statement_timestamp(),
      transcript_expires_at = least(transcript_expires_at, statement_timestamp())
    where id = v_candidate.id;
    v_scrubbed := v_scrubbed + 1;
  end loop;

  -- A ledger-expired thread without remaining runs can be removed immediately.
  -- Threads whose expired runs are deleted below are picked up next bounded pass.
  for v_candidate in
    select thread.id
    from public.assistant_threads thread
    where thread.ledger_expires_at <= statement_timestamp()
      and not exists (
        select 1 from public.assistant_runs run where run.thread_id = thread.id
      )
    order by thread.ledger_expires_at
    limit p_limit
    for update skip locked
  loop
    delete from public.assistant_threads where id = v_candidate.id;
    v_threads := v_threads + 1;
  end loop;

  delete from public.assistant_runs run where run.id in (
    select candidate.id from public.assistant_runs candidate
    where candidate.expires_at <= statement_timestamp()
    order by candidate.expires_at limit p_limit for update skip locked
  );
  get diagnostics v_runs = row_count;
  delete from public.assistant_messages message where message.id in (
    select candidate.id from public.assistant_messages candidate
    where candidate.expires_at <= statement_timestamp()
    order by candidate.expires_at limit p_limit for update skip locked
  );
  get diagnostics v_changed = row_count;
  v_messages := v_messages + v_changed;

  -- Terminal runs should not retain leases; this repair is last so purge never
  -- holds a lease row and later asks for a thread lock.
  delete from public.assistant_run_leases lease
  where lease.run_id in (
    select candidate.run_id
    from public.assistant_run_leases candidate
    join public.assistant_runs run on run.id = candidate.run_id
    where run.status in ('succeeded', 'failed', 'cancelled', 'timed_out')
    order by run.completed_at nulls first
    limit p_limit
    for update of candidate skip locked
  );
  get diagnostics v_changed = row_count;
  v_leases := v_leases + v_changed;
  delete from public.assistant_quota_buckets quota
  where (quota.tenant_id, quota.scope, quota.scope_id, quota.period, quota.window_started_at) in (
    select candidate.tenant_id, candidate.scope, candidate.scope_id, candidate.period,
      candidate.window_started_at
    from public.assistant_quota_buckets candidate
    where candidate.window_started_at < statement_timestamp() - interval '31 days'
    order by candidate.window_started_at limit p_limit for update skip locked
  );
  get diagnostics v_quotas = row_count;
  delete from assistant_runtime.attestation_nonces receipt
  where receipt.nonce in (
    select candidate.nonce
    from assistant_runtime.attestation_nonces candidate
    where candidate.expires_at <= statement_timestamp()
    order by candidate.expires_at
    limit p_limit
    for update skip locked
  );
  get diagnostics v_attestation_nonces = row_count;
  return jsonb_build_object(
    'purgedRuns', v_runs, 'purgedMessages', v_messages,
    'scrubbedThreads', v_scrubbed, 'purgedThreads', v_threads,
    'purgedQuotaBuckets', v_quotas,
    'purgedAttestationNonces', v_attestation_nonces,
    'purgedTerminalLeases', v_leases, 'asOf', statement_timestamp()
  );
end;
$$;

do $$
declare
  v_job record;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    raise notice 'pg_cron unavailable; AI runtime retention schedule was not installed';
    return;
  end if;
  for v_job in
    select jobid from cron.job where jobname = 'ai-assistant-runtime-retention'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
  perform cron.schedule(
    'ai-assistant-runtime-retention',
    '17 3 * * *',
    'select assistant_runtime.assistant_purge_expired_runtime_v1(1000)'
  );
end
$$;

revoke all on function public.assistant_get_authority_v1()
from public, anon, authenticated, service_role;
revoke all on function public.assistant_begin_run_v1(
  uuid, text, text, text, uuid, integer, integer, integer, text, integer
) from public, anon, authenticated, service_role;
revoke all on function assistant_runtime.assistant_heartbeat_run_v1(
  uuid, uuid, text, uuid, uuid, bigint, integer
)
from public, anon, authenticated, service_role;
revoke all on function assistant_runtime.assistant_record_provider_attempt_v1(
  uuid, uuid, text, uuid, uuid, bigint, integer, text, text, text, text, text,
  bigint, bigint, bigint, text, text, text, timestamptz, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function assistant_runtime.assistant_record_tool_receipt_v1(
  uuid, uuid, text, uuid, uuid, bigint, integer, integer, text, text, text, text, text,
  text, text, text, integer, integer, boolean, boolean, text,
  timestamptz, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function assistant_runtime.assistant_complete_run_v1(
  uuid, uuid, text, uuid, uuid, bigint, text, text, jsonb, text
) from public, anon, authenticated, service_role;
revoke all on function assistant_runtime.assistant_heartbeat_run_v2(text, text, text),
  assistant_runtime.assistant_record_provider_attempt_v2(text, text, text),
  assistant_runtime.assistant_record_tool_receipt_v2(text, text, text),
  assistant_runtime.assistant_complete_run_v2(text, text, text)
from public, anon, authenticated, service_role;
revoke all on function public.assistant_request_run_cancel_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.assistant_delete_thread_v1(uuid)
from public, anon, authenticated, service_role;
revoke all on function assistant_runtime.assistant_purge_expired_runtime_v1(integer)
from public, anon, authenticated, service_role;

grant execute on function public.assistant_get_authority_v1() to authenticated;
grant execute on function public.assistant_begin_run_v1(
  uuid, text, text, text, uuid, integer, integer, integer, text, integer
) to authenticated;
grant execute on function assistant_runtime.assistant_heartbeat_run_v2(text, text, text),
  assistant_runtime.assistant_record_provider_attempt_v2(text, text, text),
  assistant_runtime.assistant_record_tool_receipt_v2(text, text, text),
  assistant_runtime.assistant_complete_run_v2(text, text, text)
to authenticated;
grant execute on function public.assistant_request_run_cancel_v1(uuid)
to authenticated;
grant execute on function public.assistant_delete_thread_v1(uuid)
to authenticated;

comment on table public.assistant_runs is
  'Durable canonical AI run metadata. No provider continuation, reasoning, raw prompt, raw tool payload or exception text is persisted.';
comment on table public.assistant_tool_receipts is
  'Hash-only tool execution evidence; arguments and outputs stay request-local.';
comment on table assistant_runtime.attestation_keys is
  'Non-secret key metadata. Key bytes exist only in Vault and the matching Edge secret.';
comment on table assistant_runtime.attestation_nonces is
  'At-most-15-minute exact-replay receipts for caller-bound, lease-bound runtime HMAC attestations.';

commit;
