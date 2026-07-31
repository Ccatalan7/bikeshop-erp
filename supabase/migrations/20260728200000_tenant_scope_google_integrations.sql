-- Deployment status: PENDING.
--
-- Additive Google integration cutover.
--
-- The legacy google_oauth_connections table has a global integration_key
-- primary key and therefore cannot represent more than one tenant. It remains
-- untouched as the compatibility surface for the previously deployed Edge
-- Functions. New code uses the tenant-owned v2 tables created here, so two
-- tenants can coexist immediately without waiting for a destructive PK swap.
--
-- Safe rollout:
--   1. apply this migration;
--   2. configure the explicit legacy Search Console site owner and Merchant
--      tenant owner;
--   3. publish google-oauth-callback and google-product-diagnostics together;
--   4. observe OAuth start/callback, refresh and Merchant lease receipts;
--   5. only in a later release remove the legacy tables/columns and bridge
--      triggers after no old function invocation remains.
--
-- The final cleanup is deliberately not included in this migration. Applying
-- cleanup in the same db push would recreate an incompatible rollout window.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '90s';

do $$
begin
  if to_regclass('public.google_oauth_connections') is null
     or to_regclass('public.google_oauth_states') is null
     or to_regclass('public.user_profiles') is null
     or to_regclass('public.tenants') is null
     or to_regclass('public.website_settings') is null then
    raise exception
      'Google OAuth, user profile, tenant, and website settings foundations are required';
  end if;
end;
$$;

-- Keep the legacy writer readable by the new callback during the deployment
-- window. No legacy key, token or state row is renamed or removed here.
alter table public.google_oauth_connections
  add column if not exists tenant_id uuid,
  add column if not exists site_url text;

alter table public.google_oauth_states
  add column if not exists state_hash text,
  add column if not exists tenant_id uuid,
  add column if not exists site_url text,
  add column if not exists consumed_at timestamptz,
  add column if not exists invalidated_at timestamptz;

-- Resolve the canonical public-store hostname from the tenant-owned setting.
-- `store_url` is preferred over its legacy alias. Conflicting aliases fail
-- closed, and custom_domain is only a fallback for tenants not yet migrated to
-- the canonical setting.
create or replace function public.google_oauth_tenant_store_host(
  p_tenant_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_store_url text;
  v_legacy_store_url text;
  v_custom_domain text;
  v_candidate text;
begin
  select
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'store_url'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'seo_canonical_url')
  into v_store_url, v_legacy_store_url
  from public.website_settings setting
  where setting.tenant_id = p_tenant_id
    and setting.key in ('store_url', 'seo_canonical_url');

  if v_store_url is not null
     and v_legacy_store_url is not null
     and lower(rtrim(v_store_url, '/')) <>
       lower(rtrim(v_legacy_store_url, '/')) then
    return null;
  end if;

  select nullif(btrim(tenant.custom_domain), '')
  into v_custom_domain
  from public.tenants tenant
  where tenant.id = p_tenant_id
    and tenant.is_active is true;

  if not found then
    return null;
  end if;

  v_candidate := coalesce(v_store_url, v_legacy_store_url);
  if v_candidate is not null then
    v_candidate := lower(v_candidate);
    if v_candidate !~
      '^https://([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}/?$' then
      return null;
    end if;
    return regexp_replace(
      regexp_replace(v_candidate, '^https://', ''),
      '/$',
      ''
    );
  end if;

  if v_custom_domain is null then
    return null;
  end if;
  v_candidate := lower(v_custom_domain);
  if v_candidate !~
    '^(https://)?([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}/?$' then
    return null;
  end if;
  return regexp_replace(
    regexp_replace(v_candidate, '^https://', ''),
    '/$',
    ''
  );
end;
$$;

create or replace function public.google_oauth_site_matches_tenant(
  p_tenant_id uuid,
  p_site_url text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_store_host text;
  v_site_url text := lower(btrim(coalesce(p_site_url, '')));
  v_site_host text;
begin
  v_store_host := public.google_oauth_tenant_store_host(p_tenant_id);
  if v_store_host is null then
    return false;
  end if;

  if v_site_url ~
    '^sc-domain:([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$' then
    v_site_host := substring(v_site_url from length('sc-domain:') + 1);
  elsif v_site_url ~
    '^https://([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}/?$' then
    v_site_host := regexp_replace(
      regexp_replace(v_site_url, '^https://', ''),
      '/$',
      ''
    );
  else
    return false;
  end if;

  return v_site_host = v_store_host;
end;
$$;

-- Backfill only deterministic ownership. Ambiguous legacy rows remain intact
-- and unowned; the new functions fail closed instead of guessing.
with connection_actor_tenants as (
  select
    connection.integration_key,
    min(profile.tenant_id::text)::uuid as tenant_id
  from public.google_oauth_connections connection
  join public.user_profiles profile
    on profile.user_id = connection.updated_by
   and profile.is_active is true
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where connection.tenant_id is null
    and (
      profile.role = 'admin'
      or profile.permissions @> '{"edit_settings": true}'::jsonb
    )
    and (
      select count(*)
      from public.user_profiles active_profile
      join public.tenants active_tenant
        on active_tenant.id = active_profile.tenant_id
       and active_tenant.is_active is true
      where active_profile.user_id = connection.updated_by
        and active_profile.is_active is true
    ) = 1
  group by connection.integration_key
  having count(*) = 1
)
update public.google_oauth_connections connection
set tenant_id = candidate.tenant_id
from connection_actor_tenants candidate
where connection.integration_key = candidate.integration_key
  and connection.tenant_id is null;

with state_actor_tenants as (
  select
    state.state,
    min(profile.tenant_id::text)::uuid as tenant_id
  from public.google_oauth_states state
  join public.user_profiles profile
    on profile.user_id = state.created_by
   and profile.is_active is true
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where state.tenant_id is null
    and (
      profile.role = 'admin'
      or profile.permissions @> '{"edit_settings": true}'::jsonb
    )
    and (
      select count(*)
      from public.user_profiles active_profile
      join public.tenants active_tenant
        on active_tenant.id = active_profile.tenant_id
       and active_tenant.is_active is true
      where active_profile.user_id = state.created_by
        and active_profile.is_active is true
    ) = 1
  group by state.state
  having count(*) = 1
)
update public.google_oauth_states state
set tenant_id = candidate.tenant_id
from state_actor_tenants candidate
where state.state = candidate.state
  and state.tenant_id is null;

update public.google_oauth_connections connection
set site_url = 'sc-domain:' ||
  public.google_oauth_tenant_store_host(connection.tenant_id)
where connection.tenant_id is not null
  and connection.site_url is null
  and public.google_oauth_tenant_store_host(connection.tenant_id) is not null
  and exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = connection.updated_by
      and profile.tenant_id = connection.tenant_id
      and profile.is_active is true
      and (
        profile.role = 'admin'
        or profile.permissions @> '{"edit_settings": true}'::jsonb
      )
      and (
        select count(*)
        from public.user_profiles active_profile
        join public.tenants active_tenant
          on active_tenant.id = active_profile.tenant_id
         and active_tenant.is_active is true
        where active_profile.user_id = connection.updated_by
          and active_profile.is_active is true
      ) = 1
  );

update public.google_oauth_states state
set site_url = 'sc-domain:' ||
  public.google_oauth_tenant_store_host(state.tenant_id)
where state.tenant_id is not null
  and state.site_url is null
  and public.google_oauth_tenant_store_host(state.tenant_id) is not null
  and exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = state.created_by
      and profile.tenant_id = state.tenant_id
      and profile.is_active is true
      and (
        profile.role = 'admin'
        or profile.permissions @> '{"edit_settings": true}'::jsonb
      )
      and (
        select count(*)
        from public.user_profiles active_profile
        join public.tenants active_tenant
          on active_tenant.id = active_profile.tenant_id
         and active_tenant.is_active is true
        where active_profile.user_id = state.created_by
          and active_profile.is_active is true
      ) = 1
  );

update public.google_oauth_states
set state_hash = encode(
  extensions.digest(convert_to(state, 'UTF8'), 'sha256'),
  'hex'
)
where state_hash is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.google_oauth_connections'::regclass
      and conname = 'google_oauth_connections_tenant_id_fkey'
  ) then
    alter table public.google_oauth_connections
      add constraint google_oauth_connections_tenant_id_fkey
      foreign key (tenant_id) references public.tenants(id) on delete cascade;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.google_oauth_states'::regclass
      and conname = 'google_oauth_states_tenant_id_fkey'
  ) then
    alter table public.google_oauth_states
      add constraint google_oauth_states_tenant_id_fkey
      foreign key (tenant_id) references public.tenants(id) on delete cascade;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.google_oauth_states'::regclass
      and conname = 'google_oauth_states_state_hash_key'
  ) then
    alter table public.google_oauth_states
      add constraint google_oauth_states_state_hash_key unique (state_hash);
  end if;
end;
$$;

alter table public.google_oauth_connections
  drop constraint if exists google_oauth_connections_site_url_check;
alter table public.google_oauth_connections
  add constraint google_oauth_connections_site_url_check check (
    site_url is null
    or (
      length(site_url) between 4 and 2048
      and site_url ~ '^(sc-domain:[a-z0-9.-]+|https://[^[:space:]]+)$'
    )
  );

alter table public.google_oauth_states
  drop constraint if exists google_oauth_states_state_hash_check;
alter table public.google_oauth_states
  add constraint google_oauth_states_state_hash_check check (
    state_hash is null or state_hash ~ '^[0-9a-f]{64}$'
  );

alter table public.google_oauth_states
  drop constraint if exists google_oauth_states_site_url_check;
alter table public.google_oauth_states
  add constraint google_oauth_states_site_url_check check (
    site_url is null
    or (
      length(site_url) between 4 and 2048
      and site_url ~ '^(sc-domain:[a-z0-9.-]+|https://[^[:space:]]+)$'
    )
  );

create index if not exists idx_google_oauth_states_expiry
  on public.google_oauth_states(expires_at)
  where consumed_at is null;

create index if not exists idx_google_oauth_connections_integration
  on public.google_oauth_connections(integration_key, tenant_id);

comment on column public.google_oauth_states.state_hash is
  'Legacy bridge SHA-256 verifier. New OAuth nonces live only in google_oauth_tenant_states.';
comment on column public.google_oauth_connections.tenant_id is
  'Best-effort legacy owner used only for an additive cutover into tenant storage.';
comment on column public.google_oauth_states.site_url is
  'Exact Search Console property selected when a tenant-scoped legacy state was created.';

-- Canonical multi-tenant storage. The legacy global PK is not used by any new
-- writer or reader.
create table if not exists public.google_oauth_generation_heads (
  tenant_id uuid not null
    references public.tenants(id) on delete cascade,
  integration_key text not null,
  current_generation bigint not null default 0,
  updated_at timestamptz not null default clock_timestamp(),
  constraint google_oauth_generation_heads_pkey
    primary key (tenant_id, integration_key),
  constraint google_oauth_generation_heads_key_check check (
    integration_key ~ '^[a-z0-9][a-z0-9_:-]{0,63}$'
  ),
  constraint google_oauth_generation_heads_generation_check check (
    current_generation >= 0
  )
);

create table if not exists public.google_oauth_tenant_connections (
  id uuid primary key default extensions.gen_random_uuid(),
  tenant_id uuid not null
    references public.tenants(id) on delete cascade,
  integration_key text not null,
  site_url text not null,
  generation bigint not null,
  credential_version bigint not null default 0,
  provider text not null default 'google',
  account_email text,
  access_token text not null,
  refresh_token text,
  token_type text,
  scope text,
  expires_at timestamptz,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint google_oauth_tenant_connections_owner_key
    unique (tenant_id, integration_key),
  constraint google_oauth_tenant_connections_key_check check (
    integration_key ~ '^[a-z0-9][a-z0-9_:-]{0,63}$'
  ),
  constraint google_oauth_tenant_connections_generation_check check (
    generation >= 0
  ),
  constraint google_oauth_tenant_connections_version_check check (
    credential_version >= 0
  ),
  constraint google_oauth_tenant_connections_site_check check (
    length(site_url) between 4 and 2048
    and site_url ~ '^(sc-domain:[a-z0-9.-]+|https://[^[:space:]]+)$'
  )
);

create table if not exists public.google_oauth_tenant_states (
  state_hash text primary key,
  tenant_id uuid not null,
  integration_key text not null,
  site_url text not null,
  generation bigint not null,
  created_by uuid not null
    references auth.users(id) on delete cascade,
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  invalidated_at timestamptz,
  committed_at timestamptz,
  constraint google_oauth_tenant_states_head_fkey
    foreign key (tenant_id, integration_key)
    references public.google_oauth_generation_heads(
      tenant_id,
      integration_key
    )
    on delete cascade,
  constraint google_oauth_tenant_states_generation_key
    unique (tenant_id, integration_key, generation),
  constraint google_oauth_tenant_states_hash_check check (
    state_hash ~ '^[0-9a-f]{64}$'
  ),
  constraint google_oauth_tenant_states_generation_check check (
    generation > 0
  ),
  constraint google_oauth_tenant_states_site_check check (
    length(site_url) between 4 and 2048
    and site_url ~ '^(sc-domain:[a-z0-9.-]+|https://[^[:space:]]+)$'
  )
);

create table if not exists public.google_merchant_operation_leases (
  tenant_id uuid not null
    references public.tenants(id) on delete cascade,
  operation_key text not null,
  lease_token uuid,
  lease_fence bigint not null default 0,
  lease_expires_at timestamptz,
  window_started_at timestamptz not null default clock_timestamp(),
  window_count integer not null default 0,
  updated_at timestamptz not null default clock_timestamp(),
  constraint google_merchant_operation_leases_pkey
    primary key (tenant_id, operation_key),
  constraint google_merchant_operation_leases_key_check check (
    operation_key ~ '^[a-z0-9][a-z0-9_:-]{0,63}$'
  ),
  constraint google_merchant_operation_leases_count_check check (
    window_count between 0 and 3
  ),
  constraint google_merchant_operation_leases_fence_check check (
    lease_fence >= 0
  ),
  constraint google_merchant_operation_leases_pair_check check (
    (lease_token is null and lease_expires_at is null)
    or (lease_token is not null and lease_expires_at is not null)
  )
);

alter table public.google_oauth_generation_heads enable row level security;
alter table public.google_oauth_tenant_connections enable row level security;
alter table public.google_oauth_tenant_states enable row level security;
alter table public.google_merchant_operation_leases enable row level security;

create index if not exists idx_google_oauth_tenant_states_expiry
  on public.google_oauth_tenant_states(expires_at)
  where consumed_at is null and invalidated_at is null;

create index if not exists idx_google_oauth_tenant_connections_site
  on public.google_oauth_tenant_connections(tenant_id, site_url);

create index if not exists idx_google_merchant_operation_leases_expiry
  on public.google_merchant_operation_leases(lease_expires_at)
  where lease_token is not null;

comment on table public.google_oauth_tenant_connections is
  'Canonical tenant-owned Google credential store. Legacy global-key storage is bridge-only.';
comment on column public.google_oauth_tenant_connections.generation is
  'Authorization generation committed by an exact consumed OAuth state.';
comment on column public.google_oauth_tenant_connections.credential_version is
  'CAS version incremented by every credential commit or access-token refresh.';
comment on table public.google_merchant_operation_leases is
  'Durable per-tenant operation lease and fixed-window rate receipt shared by all Edge isolates.';

-- Copy only deterministic legacy credentials. Tokens are preserved byte for
-- byte, and unresolved rows remain solely in the legacy table.
insert into public.google_oauth_generation_heads (
  tenant_id,
  integration_key,
  current_generation
)
select
  connection.tenant_id,
  connection.integration_key,
  0
from public.google_oauth_connections connection
where connection.tenant_id is not null
  and connection.site_url is not null
  and public.google_oauth_site_matches_tenant(
    connection.tenant_id,
    connection.site_url
  )
  and exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = connection.updated_by
      and profile.tenant_id = connection.tenant_id
      and profile.is_active is true
      and (
        profile.role = 'admin'
        or profile.permissions @> '{"edit_settings": true}'::jsonb
      )
      and (
        select count(*)
        from public.user_profiles active_profile
        join public.tenants active_tenant
          on active_tenant.id = active_profile.tenant_id
         and active_tenant.is_active is true
        where active_profile.user_id = connection.updated_by
          and active_profile.is_active is true
      ) = 1
  )
on conflict (tenant_id, integration_key) do nothing;

insert into public.google_oauth_tenant_connections (
  tenant_id,
  integration_key,
  site_url,
  generation,
  credential_version,
  provider,
  account_email,
  access_token,
  refresh_token,
  token_type,
  scope,
  expires_at,
  updated_by,
  created_at,
  updated_at
)
select
  connection.tenant_id,
  connection.integration_key,
  connection.site_url,
  0,
  0,
  connection.provider,
  connection.account_email,
  connection.access_token,
  connection.refresh_token,
  connection.token_type,
  connection.scope,
  connection.expires_at,
  connection.updated_by,
  connection.created_at,
  connection.updated_at
from public.google_oauth_connections connection
where connection.tenant_id is not null
  and connection.site_url is not null
  and public.google_oauth_site_matches_tenant(
    connection.tenant_id,
    connection.site_url
  )
  and exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = connection.updated_by
      and profile.tenant_id = connection.tenant_id
      and profile.is_active is true
      and (
        profile.role = 'admin'
        or profile.permissions @> '{"edit_settings": true}'::jsonb
      )
      and (
        select count(*)
        from public.user_profiles active_profile
        join public.tenants active_tenant
          on active_tenant.id = active_profile.tenant_id
         and active_tenant.is_active is true
        where active_profile.user_id = connection.updated_by
          and active_profile.is_active is true
      ) = 1
  )
on conflict (tenant_id, integration_key) do nothing;

create or replace function public.prepare_google_oauth_state_transition()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_tenant_id uuid;
  v_site_url text;
  v_store_host text;
begin
  if new.state_hash is null then
    new.state_hash := encode(
      extensions.digest(convert_to(new.state, 'UTF8'), 'sha256'),
      'hex'
    );
  end if;

  if new.created_by is null then
    new.tenant_id := null;
    new.site_url := null;
    return new;
  end if;

  select
    profile.tenant_id,
    public.google_oauth_tenant_store_host(profile.tenant_id)
  into v_tenant_id, v_store_host
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = new.created_by
    and profile.is_active is true
    and (
      profile.role = 'admin'
      or profile.permissions @> '{"edit_settings": true}'::jsonb
    )
    and (
      select count(*)
      from public.user_profiles active_profile
      join public.tenants active_tenant
        on active_tenant.id = active_profile.tenant_id
       and active_tenant.is_active is true
      where active_profile.user_id = new.created_by
        and active_profile.is_active is true
    ) = 1;

  v_site_url := case
    when v_store_host is null then null
    else 'sc-domain:' || v_store_host
  end;

  if v_tenant_id is null
     or v_site_url is null
     or (new.tenant_id is not null and new.tenant_id <> v_tenant_id)
     or (
       new.site_url is not null
       and not public.google_oauth_site_matches_tenant(
         v_tenant_id,
         new.site_url
       )
     ) then
    -- Preserve the legacy row for forensics/retry, but make it ineligible for
    -- canonical promotion.
    new.tenant_id := null;
    new.site_url := null;
    return new;
  end if;

  if new.site_url is not null then
    v_site_url := btrim(new.site_url);
  end if;
  new.tenant_id := v_tenant_id;
  new.site_url := v_site_url;
  return new;
end;
$$;

drop trigger if exists trg_prepare_google_oauth_state_transition
  on public.google_oauth_states;
create trigger trg_prepare_google_oauth_state_transition
  before insert on public.google_oauth_states
  for each row
  execute function public.prepare_google_oauth_state_transition();

-- Mirror a legacy callback only while the canonical generation is still zero.
-- Once any v2 authorization starts, an old function can no longer overwrite
-- canonical credentials.
create or replace function public.mirror_google_oauth_connection_transition()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid;
  v_site_url text;
  v_store_host text;
  v_head_generation bigint;
begin
  if new.updated_by is null
     or coalesce(new.integration_key, '') !~
       '^[a-z0-9][a-z0-9_:-]{0,63}$' then
    return new;
  end if;

  select
    profile.tenant_id,
    public.google_oauth_tenant_store_host(profile.tenant_id)
  into v_tenant_id, v_store_host
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = new.updated_by
    and profile.is_active is true
    and (
      profile.role = 'admin'
      or profile.permissions @> '{"edit_settings": true}'::jsonb
    )
    and (
      select count(*)
      from public.user_profiles active_profile
      join public.tenants active_tenant
        on active_tenant.id = active_profile.tenant_id
       and active_tenant.is_active is true
      where active_profile.user_id = new.updated_by
        and active_profile.is_active is true
    ) = 1;

  v_site_url := case
    when v_store_host is null then null
    else 'sc-domain:' || v_store_host
  end;

  if v_tenant_id is null
     or v_site_url is null
     or (new.tenant_id is not null and new.tenant_id <> v_tenant_id)
     or (
       new.site_url is not null
       and not public.google_oauth_site_matches_tenant(
         v_tenant_id,
         new.site_url
       )
     ) then
    return new;
  end if;

  if new.site_url is not null then
    v_site_url := btrim(new.site_url);
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended(
      'google_oauth_head:' ||
        v_tenant_id::text || ':' || new.integration_key,
      0
    )
  );

  insert into public.google_oauth_generation_heads (
    tenant_id,
    integration_key,
    current_generation
  ) values (
    v_tenant_id,
    new.integration_key,
    0
  )
  on conflict (tenant_id, integration_key) do nothing;

  select head.current_generation
  into v_head_generation
  from public.google_oauth_generation_heads head
  where head.tenant_id = v_tenant_id
    and head.integration_key = new.integration_key
  for update;

  if not found or v_head_generation <> 0 then
    return new;
  end if;

  insert into public.google_oauth_tenant_connections (
    tenant_id,
    integration_key,
    site_url,
    generation,
    credential_version,
    provider,
    account_email,
    access_token,
    refresh_token,
    token_type,
    scope,
    expires_at,
    updated_by,
    created_at,
    updated_at
  ) values (
    v_tenant_id,
    new.integration_key,
    v_site_url,
    0,
    0,
    new.provider,
    new.account_email,
    new.access_token,
    new.refresh_token,
    new.token_type,
    new.scope,
    new.expires_at,
    new.updated_by,
    new.created_at,
    new.updated_at
  )
  on conflict (tenant_id, integration_key) do update
  set site_url = excluded.site_url,
      provider = excluded.provider,
      account_email = excluded.account_email,
      access_token = excluded.access_token,
      refresh_token = excluded.refresh_token,
      credential_version =
        google_oauth_tenant_connections.credential_version + 1,
      token_type = excluded.token_type,
      scope = excluded.scope,
      expires_at = excluded.expires_at,
      updated_by = excluded.updated_by,
      updated_at = excluded.updated_at
  where google_oauth_tenant_connections.generation = 0;

  return new;
end;
$$;

drop trigger if exists trg_mirror_google_oauth_connection_transition
  on public.google_oauth_connections;
create trigger trg_mirror_google_oauth_connection_transition
  after insert or update on public.google_oauth_connections
  for each row
  execute function public.mirror_google_oauth_connection_transition();

create or replace function public.create_google_oauth_state(
  p_actor_id uuid,
  p_tenant_id uuid,
  p_integration_key text,
  p_state_hash text,
  p_site_url text,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_active_profile_count integer;
  v_generation bigint;
  v_now timestamptz := clock_timestamp();
begin
  if v_role <> 'service_role' then
    raise exception 'Google OAuth state creation requires service role'
      using errcode = '42501';
  end if;

  if p_actor_id is null
     or p_tenant_id is null
     or coalesce(p_integration_key, '') !~
       '^[a-z0-9][a-z0-9_:-]{0,63}$'
     or coalesce(p_state_hash, '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_site_url, '') !~
       '^(sc-domain:[a-z0-9.-]+|https://[^[:space:]]+)$'
     or not public.google_oauth_site_matches_tenant(
       p_tenant_id,
       p_site_url
     )
     or p_expires_at <= v_now
     or p_expires_at > v_now + interval '15 minutes' then
    raise exception 'Invalid Google OAuth state request'
      using errcode = '22023';
  end if;

  select count(*)
  into v_active_profile_count
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = p_actor_id
    and profile.is_active is true;

  if v_active_profile_count <> 1 or not exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = p_actor_id
      and profile.tenant_id = p_tenant_id
      and profile.is_active is true
      and (
        profile.role = 'admin'
        or profile.permissions @> '{"edit_settings": true}'::jsonb
      )
  ) then
    raise exception
      'Google OAuth requires exactly one active authorized tenant profile'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'google_oauth_head:' ||
        p_tenant_id::text || ':' || p_integration_key,
      0
    )
  );

  insert into public.google_oauth_generation_heads (
    tenant_id,
    integration_key,
    current_generation,
    updated_at
  ) values (
    p_tenant_id,
    p_integration_key,
    1,
    v_now
  )
  on conflict (tenant_id, integration_key) do update
  set current_generation =
        google_oauth_generation_heads.current_generation + 1,
      updated_at = excluded.updated_at
  returning current_generation into v_generation;

  update public.google_oauth_tenant_states state
  set invalidated_at = v_now
  where state.tenant_id = p_tenant_id
    and state.integration_key = p_integration_key
    and state.consumed_at is null
    and state.invalidated_at is null;

  -- The legacy callback ignores invalidated_at, so removing older owned bridge
  -- states is the only reliable cross-version invalidation.
  if p_integration_key = 'search_console' then
    delete from public.google_oauth_states state
    where state.tenant_id = p_tenant_id
      and state.consumed_at is null;
  end if;

  with stale as (
    select state.state_hash
    from public.google_oauth_tenant_states state
    where state.expires_at < v_now - interval '30 days'
       or state.consumed_at < v_now - interval '30 days'
       or state.invalidated_at < v_now - interval '30 days'
    order by state.expires_at
    limit 200
  )
  delete from public.google_oauth_tenant_states state
  using stale
  where state.state_hash = stale.state_hash;

  with stale as (
    select state.state
    from public.google_oauth_states state
    where state.expires_at < v_now - interval '30 days'
       or state.consumed_at < v_now - interval '30 days'
       or state.invalidated_at < v_now - interval '30 days'
    order by state.expires_at
    limit 200
  )
  delete from public.google_oauth_states state
  using stale
  where state.state = stale.state;

  insert into public.google_oauth_tenant_states (
    state_hash,
    tenant_id,
    integration_key,
    site_url,
    generation,
    created_by,
    expires_at
  ) values (
    p_state_hash,
    p_tenant_id,
    p_integration_key,
    btrim(p_site_url),
    v_generation,
    p_actor_id,
    p_expires_at
  );

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'integration_key', p_integration_key,
    'site_url', btrim(p_site_url),
    'generation', v_generation,
    'expires_at', p_expires_at
  );
end;
$$;

create or replace function public.consume_google_oauth_state(
  p_state_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_tenant_id uuid;
  v_integration_key text;
  v_site_url text;
  v_generation bigint;
  v_created_by uuid;
  v_expires_at timestamptz;
  v_consumed_at timestamptz;
  v_invalidated_at timestamptz;
  v_head_generation bigint;
  v_legacy_state text;
  v_legacy_match_count integer;
  v_authorized_tenant_id uuid;
  v_authorized_store_host text;
  v_now timestamptz := clock_timestamp();
begin
  if v_role <> 'service_role' then
    raise exception 'Google OAuth state consumption requires service role'
      using errcode = '42501';
  end if;
  if coalesce(p_state_hash, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid Google OAuth state' using errcode = '22023';
  end if;

  select
    state.tenant_id,
    state.integration_key
  into
    v_tenant_id,
    v_integration_key
  from public.google_oauth_tenant_states state
  where state.state_hash = p_state_hash;

  if found then
    perform pg_advisory_xact_lock(
      hashtextextended(
        'google_oauth_head:' ||
          v_tenant_id::text || ':' || v_integration_key,
        0
      )
    );

    select
      state.site_url,
      state.generation,
      state.created_by,
      state.expires_at,
      state.consumed_at,
      state.invalidated_at
    into
      v_site_url,
      v_generation,
      v_created_by,
      v_expires_at,
      v_consumed_at,
      v_invalidated_at
    from public.google_oauth_tenant_states state
    where state.state_hash = p_state_hash
    for update;

    select head.current_generation
    into v_head_generation
    from public.google_oauth_generation_heads head
    where head.tenant_id = v_tenant_id
      and head.integration_key = v_integration_key
    for update;

    if v_consumed_at is not null
       or v_invalidated_at is not null
       or v_expires_at <= v_now
       or v_generation <> v_head_generation then
      raise exception
        'Google OAuth state is invalid, expired, superseded, or already consumed'
        using errcode = '22023';
    end if;

    update public.google_oauth_tenant_states
    set consumed_at = v_now
    where state_hash = p_state_hash;

    return jsonb_build_object(
      'tenant_id', v_tenant_id,
      'integration_key', v_integration_key,
      'actor_id', v_created_by,
      'site_url', v_site_url,
      'generation', v_generation
    );
  end if;

  -- A state created by the old function can cross the deployment boundary once,
  -- but only if no v2 generation has started for that tenant/integration.
  select count(*)
  into v_legacy_match_count
  from public.google_oauth_states state
  where state.state_hash = p_state_hash
     or (
       state.state_hash is null
       and encode(
         extensions.digest(convert_to(state.state, 'UTF8'), 'sha256'),
         'hex'
       ) = p_state_hash
     );

  if v_legacy_match_count <> 1 then
    raise exception
      'Google OAuth state is invalid, expired, superseded, or already consumed'
      using errcode = '22023';
  end if;

  select
    state.state,
    state.tenant_id,
    state.site_url,
    state.created_by,
    state.expires_at,
    state.consumed_at,
    state.invalidated_at
  into
    v_legacy_state,
    v_tenant_id,
    v_site_url,
    v_created_by,
    v_expires_at,
    v_consumed_at,
    v_invalidated_at
  from public.google_oauth_states state
  where state.state_hash = p_state_hash
     or (
       state.state_hash is null
       and encode(
         extensions.digest(convert_to(state.state, 'UTF8'), 'sha256'),
         'hex'
       ) = p_state_hash
     );

  if not found
     or v_tenant_id is null
     or v_site_url is null
     or v_created_by is null
     or v_consumed_at is not null
     or v_invalidated_at is not null
     or v_expires_at <= v_now then
    raise exception
      'Google OAuth state is invalid, expired, superseded, or already consumed'
      using errcode = '22023';
  end if;

  select
    profile.tenant_id,
    public.google_oauth_tenant_store_host(profile.tenant_id)
  into v_authorized_tenant_id, v_authorized_store_host
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = v_created_by
    and profile.is_active is true
    and (
      profile.role = 'admin'
      or profile.permissions @> '{"edit_settings": true}'::jsonb
    )
    and (
      select count(*)
      from public.user_profiles active_profile
      join public.tenants active_tenant
        on active_tenant.id = active_profile.tenant_id
       and active_tenant.is_active is true
      where active_profile.user_id = v_created_by
        and active_profile.is_active is true
    ) = 1;

  if v_authorized_tenant_id is null
     or v_authorized_store_host is null
     or v_tenant_id <> v_authorized_tenant_id
     or not public.google_oauth_site_matches_tenant(
       v_authorized_tenant_id,
       v_site_url
     ) then
    raise exception
      'Google OAuth state is invalid, expired, superseded, or already consumed'
      using errcode = '22023';
  end if;

  v_integration_key := 'search_console';
  perform pg_advisory_xact_lock(
    hashtextextended(
      'google_oauth_head:' ||
        v_tenant_id::text || ':' || v_integration_key,
      0
    )
  );

  select
    state.consumed_at,
    state.invalidated_at
  into
    v_consumed_at,
    v_invalidated_at
  from public.google_oauth_states state
  where state.state = v_legacy_state
  for update;

  if v_consumed_at is not null or v_invalidated_at is not null then
    raise exception
      'Google OAuth state is invalid, expired, superseded, or already consumed'
      using errcode = '22023';
  end if;

  insert into public.google_oauth_generation_heads (
    tenant_id,
    integration_key,
    current_generation,
    updated_at
  ) values (
    v_tenant_id,
    v_integration_key,
    1,
    v_now
  )
  on conflict (tenant_id, integration_key) do update
  set current_generation = 1,
      updated_at = excluded.updated_at
  where google_oauth_generation_heads.current_generation = 0
  returning current_generation into v_generation;

  if v_generation is null then
    raise exception
      'Google OAuth state is invalid, expired, superseded, or already consumed'
      using errcode = '22023';
  end if;

  insert into public.google_oauth_tenant_states (
    state_hash,
    tenant_id,
    integration_key,
    site_url,
    generation,
    created_by,
    expires_at,
    consumed_at
  ) values (
    p_state_hash,
    v_tenant_id,
    v_integration_key,
    v_site_url,
    v_generation,
    v_created_by,
    v_expires_at,
    v_now
  );

  update public.google_oauth_states
  set state_hash = p_state_hash,
      consumed_at = v_now
  where state = v_legacy_state;

  return jsonb_build_object(
    'tenant_id', v_tenant_id,
    'integration_key', v_integration_key,
    'actor_id', v_created_by,
    'site_url', v_site_url,
    'generation', v_generation
  );
end;
$$;

create or replace function public.commit_google_oauth_connection(
  p_state_hash text,
  p_tenant_id uuid,
  p_integration_key text,
  p_generation bigint,
  p_site_url text,
  p_provider text,
  p_account_email text,
  p_access_token text,
  p_refresh_token text,
  p_token_type text,
  p_scope text,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_state public.google_oauth_tenant_states%rowtype;
  v_state_found boolean;
  v_head_generation bigint;
  v_head_found boolean;
  v_active_profile_count integer;
  v_committed_generation bigint;
  v_now timestamptz := clock_timestamp();
begin
  if v_role <> 'service_role' then
    raise exception 'Google OAuth connection commit requires service role'
      using errcode = '42501';
  end if;
  if coalesce(p_state_hash, '') !~ '^[0-9a-f]{64}$'
     or p_tenant_id is null
     or coalesce(p_integration_key, '') !~
       '^[a-z0-9][a-z0-9_:-]{0,63}$'
     or p_generation is null
     or p_generation <= 0
     or coalesce(p_site_url, '') !~
       '^(sc-domain:[a-z0-9.-]+|https://[^[:space:]]+)$'
     or not public.google_oauth_site_matches_tenant(
       p_tenant_id,
       p_site_url
     )
     or nullif(btrim(p_access_token), '') is null
     or nullif(btrim(p_refresh_token), '') is null then
    raise exception 'Invalid Google OAuth connection commit'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'google_oauth_head:' ||
        p_tenant_id::text || ':' || p_integration_key,
      0
    )
  );

  select state.*
  into v_state
  from public.google_oauth_tenant_states state
  where state.state_hash = p_state_hash
  for update;
  v_state_found := found;

  select head.current_generation
  into v_head_generation
  from public.google_oauth_generation_heads head
  where head.tenant_id = p_tenant_id
    and head.integration_key = p_integration_key
  for update;
  v_head_found := found;

  if not v_state_found
     or not v_head_found
     or v_state.tenant_id <> p_tenant_id
     or v_state.integration_key <> p_integration_key
     or v_state.generation <> p_generation
     or v_state.site_url <> btrim(p_site_url)
     or v_state.consumed_at is null
     or v_state.invalidated_at is not null
     or v_state.committed_at is not null
     or v_head_generation <> p_generation then
    return jsonb_build_object(
      'committed', false,
      'reason', 'superseded'
    );
  end if;

  select count(*)
  into v_active_profile_count
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = v_state.created_by
    and profile.is_active is true;

  if v_active_profile_count <> 1 or not exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = v_state.created_by
      and profile.tenant_id = p_tenant_id
      and profile.is_active is true
      and (
        profile.role = 'admin'
        or profile.permissions @> '{"edit_settings": true}'::jsonb
      )
  ) then
    raise exception
      'Google OAuth actor lost tenant authority before commit'
      using errcode = '42501';
  end if;

  insert into public.google_oauth_tenant_connections (
    tenant_id,
    integration_key,
    site_url,
    generation,
    credential_version,
    provider,
    account_email,
    access_token,
    refresh_token,
    token_type,
    scope,
    expires_at,
    updated_by,
    updated_at
  ) values (
    p_tenant_id,
    p_integration_key,
    btrim(p_site_url),
    p_generation,
    1,
    coalesce(nullif(btrim(p_provider), ''), 'google'),
    nullif(btrim(p_account_email), ''),
    p_access_token,
    p_refresh_token,
    nullif(btrim(p_token_type), ''),
    nullif(btrim(p_scope), ''),
    p_expires_at,
    v_state.created_by,
    v_now
  )
  on conflict (tenant_id, integration_key) do update
  set site_url = excluded.site_url,
      generation = excluded.generation,
      credential_version =
        google_oauth_tenant_connections.credential_version + 1,
      provider = excluded.provider,
      account_email = excluded.account_email,
      access_token = excluded.access_token,
      refresh_token = excluded.refresh_token,
      token_type = excluded.token_type,
      scope = excluded.scope,
      expires_at = excluded.expires_at,
      updated_by = excluded.updated_by,
      updated_at = excluded.updated_at
  where google_oauth_tenant_connections.generation <
    excluded.generation
    and (
      google_oauth_tenant_connections.refresh_token is distinct from
        excluded.refresh_token
      or (
        google_oauth_tenant_connections.account_email is not null
        and excluded.account_email is not null
        and lower(btrim(google_oauth_tenant_connections.account_email)) =
          lower(btrim(excluded.account_email))
      )
    )
  returning generation into v_committed_generation;

  if v_committed_generation is null then
    return jsonb_build_object(
      'committed', false,
      'reason', 'superseded'
    );
  end if;

  update public.google_oauth_tenant_states
  set committed_at = v_now
  where state_hash = p_state_hash;

  return jsonb_build_object(
    'committed', true,
    'tenant_id', p_tenant_id,
    'integration_key', p_integration_key,
    'generation', p_generation
  );
end;
$$;

create or replace function public.refresh_google_oauth_access_token(
  p_tenant_id uuid,
  p_integration_key text,
  p_site_url text,
  p_generation bigint,
  p_expected_credential_version bigint,
  p_access_token text,
  p_token_type text,
  p_scope text,
  p_expires_at timestamptz
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
    raise exception 'Google OAuth token refresh requires service role'
      using errcode = '42501';
  end if;
  if p_tenant_id is null
     or coalesce(p_integration_key, '') !~
       '^[a-z0-9][a-z0-9_:-]{0,63}$'
     or p_generation is null
     or p_generation < 0
     or p_expected_credential_version is null
     or p_expected_credential_version < 0
     or nullif(btrim(p_access_token), '') is null then
    raise exception 'Invalid Google OAuth token refresh'
      using errcode = '22023';
  end if;

  update public.google_oauth_tenant_connections connection
  set access_token = p_access_token,
      token_type = coalesce(
        nullif(btrim(p_token_type), ''),
        connection.token_type
      ),
      scope = coalesce(nullif(btrim(p_scope), ''), connection.scope),
      expires_at = p_expires_at,
      credential_version = connection.credential_version + 1,
      updated_at = clock_timestamp()
  where connection.tenant_id = p_tenant_id
    and connection.integration_key = p_integration_key
    and connection.site_url = btrim(p_site_url)
    and connection.generation = p_generation
    and connection.credential_version = p_expected_credential_version;

  return found;
end;
$$;

create or replace function public.acquire_google_merchant_refresh_lease(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_now timestamptz := clock_timestamp();
  v_operation_key constant text := 'merchant_feed_refresh';
  v_lease public.google_merchant_operation_leases%rowtype;
  v_token uuid;
  v_fence bigint;
begin
  if v_role <> 'service_role' then
    raise exception 'Merchant refresh lease requires service role'
      using errcode = '42501';
  end if;
  if p_tenant_id is null or not exists (
    select 1
    from public.tenants tenant
    where tenant.id = p_tenant_id
      and tenant.is_active is true
  ) then
    raise exception 'Merchant refresh tenant is not active'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'google_merchant_lease:' ||
        p_tenant_id::text || ':' || v_operation_key,
      0
    )
  );

  insert into public.google_merchant_operation_leases (
    tenant_id,
    operation_key,
    window_started_at,
    window_count,
    updated_at
  ) values (
    p_tenant_id,
    v_operation_key,
    v_now,
    0,
    v_now
  )
  on conflict (tenant_id, operation_key) do nothing;

  select lease.*
  into v_lease
  from public.google_merchant_operation_leases lease
  where lease.tenant_id = p_tenant_id
    and lease.operation_key = v_operation_key
  for update;

  if v_lease.window_started_at <= v_now - interval '1 minute' then
    v_lease.window_started_at := v_now;
    v_lease.window_count := 0;
  end if;

  if v_lease.lease_token is not null
     and v_lease.lease_expires_at > v_now then
    return jsonb_build_object(
      'acquired', false,
      'reason', 'active',
      'retry_after_seconds',
        greatest(
          1,
          ceil(extract(epoch from (v_lease.lease_expires_at - v_now)))
        )::integer
    );
  end if;

  if v_lease.window_count >= 3 then
    return jsonb_build_object(
      'acquired', false,
      'reason', 'rate_limited',
      'retry_after_seconds',
        greatest(
          1,
          ceil(
            extract(
              epoch from (
                v_lease.window_started_at + interval '1 minute' - v_now
              )
            )
          )
        )::integer
    );
  end if;

  v_token := extensions.gen_random_uuid();
  v_fence := v_lease.lease_fence + 1;
  update public.google_merchant_operation_leases
  set lease_token = v_token,
      lease_fence = v_fence,
      -- The Edge operation has a 25-second hard deadline. A 60-second lease
      -- leaves shutdown/network margin, while renewal keeps one long-running
      -- owner fenced from replacement.
      lease_expires_at = v_now + interval '60 seconds',
      window_started_at = v_lease.window_started_at,
      window_count = v_lease.window_count + 1,
      updated_at = v_now
  where tenant_id = p_tenant_id
    and operation_key = v_operation_key;

  return jsonb_build_object(
    'acquired', true,
    'lease_token', v_token,
    'lease_fence', v_fence,
    'lease_expires_at', v_now + interval '60 seconds',
    'window_count', v_lease.window_count + 1
  );
end;
$$;

create or replace function public.renew_google_merchant_refresh_lease(
  p_tenant_id uuid,
  p_lease_token uuid,
  p_lease_fence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_now timestamptz := clock_timestamp();
  v_expires_at timestamptz;
begin
  if v_role <> 'service_role' then
    raise exception 'Merchant refresh lease renewal requires service role'
      using errcode = '42501';
  end if;
  if p_tenant_id is null
     or p_lease_token is null
     or p_lease_fence is null
     or p_lease_fence <= 0 then
    return jsonb_build_object('renewed', false, 'reason', 'invalid');
  end if;

  update public.google_merchant_operation_leases
  set lease_expires_at = v_now + interval '60 seconds',
      updated_at = v_now
  where tenant_id = p_tenant_id
    and operation_key = 'merchant_feed_refresh'
    and lease_token = p_lease_token
    and lease_fence = p_lease_fence
    and lease_expires_at > v_now
  returning lease_expires_at into v_expires_at;

  if v_expires_at is null then
    return jsonb_build_object('renewed', false, 'reason', 'lost');
  end if;

  return jsonb_build_object(
    'renewed', true,
    'lease_token', p_lease_token,
    'lease_fence', p_lease_fence,
    'lease_expires_at', v_expires_at
  );
end;
$$;

create or replace function public.release_google_merchant_refresh_lease(
  p_tenant_id uuid,
  p_lease_token uuid,
  p_lease_fence bigint
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
    raise exception 'Merchant refresh lease release requires service role'
      using errcode = '42501';
  end if;
  if p_tenant_id is null
     or p_lease_token is null
     or p_lease_fence is null
     or p_lease_fence <= 0 then
    return false;
  end if;

  update public.google_merchant_operation_leases
  set lease_token = null,
      lease_expires_at = null,
      updated_at = clock_timestamp()
  where tenant_id = p_tenant_id
    and operation_key = 'merchant_feed_refresh'
    and lease_token = p_lease_token
    and lease_fence = p_lease_fence;

  return found;
end;
$$;

revoke all on table public.google_oauth_connections
  from anon, authenticated;
revoke all on table public.google_oauth_states
  from anon, authenticated;
revoke all on table public.google_oauth_generation_heads
  from anon, authenticated;
revoke all on table public.google_oauth_tenant_connections
  from anon, authenticated;
revoke all on table public.google_oauth_tenant_states
  from anon, authenticated;
revoke all on table public.google_merchant_operation_leases
  from anon, authenticated;

grant select, insert, update, delete
  on table public.google_oauth_connections to service_role;
grant select, insert, update, delete
  on table public.google_oauth_states to service_role;
grant select, insert, update, delete
  on table public.google_oauth_generation_heads to service_role;
grant select, insert, update, delete
  on table public.google_oauth_tenant_connections to service_role;
grant select, insert, update, delete
  on table public.google_oauth_tenant_states to service_role;
grant select, insert, update, delete
  on table public.google_merchant_operation_leases to service_role;

revoke all on function public.prepare_google_oauth_state_transition()
  from public, anon, authenticated, service_role;
revoke all on function public.mirror_google_oauth_connection_transition()
  from public, anon, authenticated, service_role;
revoke all on function public.google_oauth_tenant_store_host(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.google_oauth_site_matches_tenant(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.create_google_oauth_state(
  uuid, uuid, text, text, text, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public.consume_google_oauth_state(text)
  from public, anon, authenticated, service_role;
revoke all on function public.commit_google_oauth_connection(
  text, uuid, text, bigint, text, text, text, text, text, text, text,
  timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public.refresh_google_oauth_access_token(
  uuid, text, text, bigint, bigint, text, text, text, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public.acquire_google_merchant_refresh_lease(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.renew_google_merchant_refresh_lease(
  uuid, uuid, bigint
) from public, anon, authenticated, service_role;
revoke all on function public.release_google_merchant_refresh_lease(
  uuid, uuid, bigint
)
  from public, anon, authenticated, service_role;

grant execute on function public.create_google_oauth_state(
  uuid, uuid, text, text, text, timestamptz
) to service_role;
grant execute on function public.consume_google_oauth_state(text)
  to service_role;
grant execute on function public.commit_google_oauth_connection(
  text, uuid, text, bigint, text, text, text, text, text, text, text,
  timestamptz
) to service_role;
grant execute on function public.refresh_google_oauth_access_token(
  uuid, text, text, bigint, bigint, text, text, text, timestamptz
) to service_role;
grant execute on function public.acquire_google_merchant_refresh_lease(uuid)
  to service_role;
grant execute on function public.renew_google_merchant_refresh_lease(
  uuid,
  uuid,
  bigint
) to service_role;
grant execute on function public.release_google_merchant_refresh_lease(
  uuid,
  uuid,
  bigint
) to service_role;

commit;
