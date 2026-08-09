-- Supplier / external-party foundation.
-- Deployment status: pending review; do not deploy from this task.
--
-- Forward behavior:
--   * preserves every legacy supplier id and foreign key;
--   * backfills one external party per existing supplier;
--   * copies legacy portal passwords into Supabase Vault without clearing the
--     legacy column (the client cutover and plaintext cleanup are a separate
--     reviewed migration);
--   * normalizes legacy purchase invoice JSON lines without guessing missing
--     line classifications;
--   * repairs only unambiguous purchase-invoice journal provenance.
--
-- Rollout behavior: this migration is the additive/copy-first stage. Existing
-- supplier column grants remain unchanged until the separately reviewed
-- 20260808211000 credential ACL cutover is applied after every supported app
-- version has stopped using suppliers.* and legacy portal fields. Vault secrets
-- created here must not be deleted until that cutover is explicitly reversed.
-- Lock risk: short ACCESS EXCLUSIVE locks while adding nullable columns and
-- small unique constraints; current production cardinalities are low.

begin;

-- ---------------------------------------------------------------------------
-- Tenant-scoped credential authority
-- ---------------------------------------------------------------------------

update public.user_profiles profile
set permissions = coalesce(profile.permissions, '{}'::jsonb)
  || '{"can_manage_supplier_credentials": true}'::jsonb
where not (
    coalesce(profile.permissions, '{}'::jsonb)
      @> '{"can_manage_supplier_credentials": true}'::jsonb
  )
  and profile.role in ('admin', 'manager');

update public.job_roles role
set default_permissions = coalesce(role.default_permissions, '{}'::jsonb)
  || '{"can_manage_supplier_credentials": true}'::jsonb,
    updated_at = clock_timestamp()
where role.system_role in ('admin', 'manager')
  and not (
    coalesce(role.default_permissions, '{}'::jsonb)
      @> '{"can_manage_supplier_credentials": true}'::jsonb
  );

create or replace function public.ensure_supplier_credential_job_role_default()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.system_role in ('admin', 'manager') then
    new.default_permissions := coalesce(new.default_permissions, '{}'::jsonb)
      || '{"can_manage_supplier_credentials": true}'::jsonb;
  end if;
  return new;
end;
$$;

revoke all on function public.ensure_supplier_credential_job_role_default()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_supplier_credential_job_role_default
  on public.job_roles;
create trigger trg_supplier_credential_job_role_default
  before insert or update of system_role, default_permissions
  on public.job_roles
  for each row
  execute function public.ensure_supplier_credential_job_role_default();

create or replace function public.can_manage_supplier_credentials(
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = auth.uid()
      and profile.tenant_id = p_tenant_id
      and profile.is_active is true
      and coalesce(profile.permissions, '{}'::jsonb)
        @> '{"can_manage_supplier_credentials": true}'::jsonb
  )
$$;

revoke all on function public.can_manage_supplier_credentials(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.can_manage_supplier_credentials(uuid)
  to authenticated, service_role;

create or replace function public.tenant_business_date(
  p_tenant_id uuid,
  p_at timestamptz default statement_timestamp()
)
returns date
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_timezone text;
begin
  if p_tenant_id is null then
    raise exception 'Tenant id is required for business date'
      using errcode = '22023';
  end if;

  if v_role <> 'service_role'
     and not (
       v_role = ''
       and session_user in ('postgres', 'supabase_admin')
     )
     and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required'
      using errcode = '42501';
  end if;

  select coalesce(
    nullif(btrim(tenant.timezone), ''),
    'America/Santiago'
  )
  into v_timezone
  from public.tenants tenant
  where tenant.id = p_tenant_id;

  if not found then
    raise exception 'Tenant not found for business date'
      using errcode = 'P0002';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_timezone_names timezone_row
    where timezone_row.name = v_timezone
  ) then
    raise exception 'Tenant timezone is invalid'
      using errcode = '22023';
  end if;

  return (coalesce(p_at, statement_timestamp()) at time zone v_timezone)::date;
end;
$$;

comment on function public.tenant_business_date(uuid, timestamptz) is
  'Single server-owned effective-date boundary for tenant business rules. It resolves statement time in the tenant IANA timezone, defaults null/blank legacy values to America/Santiago, and fails closed for invalid configured zones.';

revoke all on function public.tenant_business_date(uuid, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.tenant_business_date(uuid, timestamptz)
  to authenticated, service_role;

create or replace function public.jsonb_contains_sensitive_key(
  p_value jsonb
)
returns boolean
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select case jsonb_typeof(coalesce(p_value, 'null'::jsonb))
    when 'object' then exists (
      select 1
      from jsonb_each(p_value) item
      where lower(regexp_replace(item.key, '[^a-zA-Z0-9]', '', 'g'))
        ~ '(password|secret|token|apikey|privatekey|passcode|authorization|bearer|credential)'
         or public.jsonb_contains_sensitive_key(item.value)
    )
    when 'array' then exists (
      select 1
      from jsonb_array_elements(p_value) item
      where public.jsonb_contains_sensitive_key(item)
    )
    else false
  end
$$;

revoke all on function public.jsonb_contains_sensitive_key(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.jsonb_contains_sensitive_key(jsonb)
  to authenticated, service_role;

create or replace function public.canonical_https_origin(
  p_value text
)
returns text
language plpgsql
immutable
strict
set search_path = pg_catalog, pg_temp
as $$
declare
  v_value text := lower(btrim(p_value));
  v_match text[];
  v_host text;
  v_port integer;
begin
  -- An origin has only scheme + host + optional effective non-default port.
  -- Userinfo, paths, query strings, and fragments are intentionally rejected.
  v_match := regexp_match(
    v_value,
    '^https://(\[[0-9a-f:.]+\]|[a-z0-9]([a-z0-9.-]*[a-z0-9])?)(:([0-9]{1,5}))?$'
  );

  if v_match is null then
    return null;
  end if;

  v_host := v_match[1];
  if position('..' in v_host) > 0 then
    return null;
  end if;

  if nullif(v_match[4], '') is not null then
    v_port := v_match[4]::integer;
    if v_port < 1 or v_port > 65535 then
      return null;
    end if;
  end if;

  return 'https://' || v_host || case
    when v_port is null or v_port = 443 then ''
    else ':' || v_port::text
  end;
end;
$$;

revoke all on function public.canonical_https_origin(text)
  from public, anon, authenticated, service_role;
grant execute on function public.canonical_https_origin(text)
  to authenticated, service_role;

create or replace function public.is_safe_https_portal_url(
  p_value text
)
returns boolean
language sql
immutable
strict
set search_path = pg_catalog, public, pg_temp
as $$
  select btrim(p_value)
      ~ '^https://[^/?#[:space:]]+(/[^?#[:space:]]*)?$'
    and public.canonical_https_origin(
      regexp_replace(
        btrim(p_value),
        '^(https://[^/]+).*$','\1'
      )
    ) is not null
$$;

revoke all on function public.is_safe_https_portal_url(text)
  from public, anon, authenticated, service_role;
grant execute on function public.is_safe_https_portal_url(text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- External identity anchor
-- ---------------------------------------------------------------------------

create table if not exists public.external_parties (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  party_kind text not null default 'other'
    check (party_kind in (
      'organization', 'person', 'government_entity', 'other'
    )),
  display_name text not null check (btrim(display_name) <> ''),
  legal_name text,
  trade_name text,
  country_code text check (
    country_code is null or country_code ~ '^[A-Z]{2}$'
  ),
  is_active boolean not null default true,
  notes text,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id)
);

create table if not exists public.external_party_identifiers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  party_id uuid not null,
  identifier_kind text not null check (identifier_kind in (
    'tax_id', 'national_id', 'registration', 'domain', 'other'
  )),
  country_code text check (
    country_code is null or country_code ~ '^[A-Z]{2}$'
  ),
  normalized_value text not null check (btrim(normalized_value) <> ''),
  display_value text,
  is_primary boolean not null default false,
  valid_from date not null,
  valid_to date,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  foreign key (tenant_id, party_id)
    references public.external_parties(tenant_id, id) on delete cascade,
  check (identifier_kind <> 'tax_id' or country_code is not null),
  check (valid_to is null or valid_to >= valid_from)
);

alter table public.external_party_identifiers
  alter column valid_from drop default;

create or replace function public.set_supplier_business_valid_from()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.valid_from is null then
    new.valid_from := public.tenant_business_date(new.tenant_id);
  end if;
  return new;
end;
$$;

comment on function public.set_supplier_business_valid_from() is
  'Fills omitted supplier temporal valid_from values from the tenant business date rather than the database session timezone.';

revoke all on function public.set_supplier_business_valid_from()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_00_supplier_business_valid_from
  on public.external_party_identifiers;
create trigger trg_00_supplier_business_valid_from
  before insert on public.external_party_identifiers
  for each row
  execute function public.set_supplier_business_valid_from();

create or replace function public.normalize_external_party_identifier()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_raw_value text;
begin
  new.identifier_kind := lower(btrim(new.identifier_kind));
  new.country_code := nullif(upper(btrim(new.country_code)), '');
  v_raw_value := coalesce(
    nullif(btrim(new.normalized_value), ''),
    nullif(btrim(new.display_value), '')
  );
  new.display_value := coalesce(
    nullif(btrim(new.display_value), ''),
    v_raw_value
  );

  if new.identifier_kind = 'tax_id' then
    new.normalized_value := lower(regexp_replace(
      coalesce(v_raw_value, ''),
      '[^0-9A-Za-z]',
      '',
      'g'
    ));
  elsif new.identifier_kind = 'domain' then
    new.normalized_value := lower(regexp_replace(
      btrim(coalesce(v_raw_value, '')),
      '[.]$',
      ''
    ));
  else
    new.normalized_value := lower(btrim(coalesce(v_raw_value, '')));
  end if;

  if new.normalized_value = '' then
    raise exception 'External party identifier value is required'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'external_party_identifier:' || new.tenant_id::text || ':' ||
      new.identifier_kind || ':' || coalesce(new.country_code, '') || ':' ||
      new.normalized_value,
    0
  ));

  if exists (
    select 1
    from public.external_party_identifiers identifier
    where identifier.tenant_id = new.tenant_id
      and identifier.identifier_kind = new.identifier_kind
      and coalesce(identifier.country_code, '') =
        coalesce(new.country_code, '')
      and identifier.normalized_value = new.normalized_value
      and identifier.id is distinct from new.id
      and daterange(
        identifier.valid_from,
        coalesce(identifier.valid_to, 'infinity'::date),
        '[]'
      ) && daterange(
        new.valid_from,
        coalesce(new.valid_to, 'infinity'::date),
        '[]'
      )
  ) then
    raise exception 'External party identifier validity overlaps an existing assignment'
      using errcode = '23505';
  end if;

  return new;
end;
$$;

revoke all on function public.normalize_external_party_identifier()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_normalize_external_party_identifier
  on public.external_party_identifiers;
create trigger trg_normalize_external_party_identifier
  before insert or update of
    tenant_id, party_id, identifier_kind, country_code,
    normalized_value, display_value, valid_from, valid_to
  on public.external_party_identifiers
  for each row
  execute function public.normalize_external_party_identifier();

drop index if exists public.external_party_identifiers_namespace_key;
create unique index external_party_identifiers_namespace_key
  on public.external_party_identifiers(
    tenant_id,
    identifier_kind,
    coalesce(country_code, ''),
    normalized_value
  ) where valid_to is null;

create unique index if not exists external_party_identifiers_current_primary_key
  on public.external_party_identifiers(tenant_id, party_id, identifier_kind)
  where is_primary and valid_to is null;
create index if not exists idx_external_parties_tenant_name
  on public.external_parties(tenant_id, lower(display_name));
create index if not exists idx_external_party_identifiers_party
  on public.external_party_identifiers(tenant_id, party_id);

-- Existing supplier ids remain the relationship ids. A deterministic party id
-- equal to the legacy supplier id makes the copy replay-safe without encoding a
-- supplier reference into the identity model.
alter table public.suppliers add column if not exists party_id uuid;

insert into public.external_parties (
  id,
  tenant_id,
  party_kind,
  display_name,
  legal_name,
  trade_name,
  is_active,
  notes,
  metadata,
  created_at,
  updated_at
)
select
  supplier.id,
  supplier.tenant_id,
  'other',
  supplier.name,
  nullif(btrim(supplier.legal_name), ''),
  nullif(btrim(supplier.trade_name), ''),
  supplier.is_active,
  null,
  jsonb_build_object('migration_source', 'legacy_supplier'),
  supplier.created_at,
  supplier.updated_at
from public.suppliers supplier
where supplier.tenant_id is not null
on conflict (id) do nothing;

update public.suppliers supplier
set party_id = supplier.id
where supplier.party_id is null
  and supplier.tenant_id is not null
  and exists (
    select 1
    from public.external_parties party
    where party.tenant_id = supplier.tenant_id
      and party.id = supplier.id
  );

insert into public.external_party_identifiers (
  tenant_id,
  party_id,
  identifier_kind,
  country_code,
  normalized_value,
  display_value,
  is_primary,
  valid_from,
  metadata
)
select
  supplier.tenant_id,
  supplier.party_id,
  'tax_id',
  'CL',
  lower(regexp_replace(supplier.rut, '[^0-9kK]', '', 'g')),
  supplier.rut,
  true,
  public.tenant_business_date(
    supplier.tenant_id,
    coalesce(supplier.created_at, statement_timestamp())
  ),
  jsonb_build_object('migration_source', 'legacy_supplier_rut')
from public.suppliers supplier
where supplier.party_id is not null
  and nullif(btrim(supplier.rut), '') is not null
  and nullif(
    lower(regexp_replace(supplier.rut, '[^0-9kK]', '', 'g')),
    ''
  ) is not null
on conflict do nothing;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.suppliers'::regclass
      and conname = 'suppliers_tenant_id_id_key'
  ) then
    alter table public.suppliers
      add constraint suppliers_tenant_id_id_key unique (tenant_id, id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.suppliers'::regclass
      and conname = 'suppliers_party_tenant_fkey'
  ) then
    alter table public.suppliers
      add constraint suppliers_party_tenant_fkey
      foreign key (tenant_id, party_id)
      references public.external_parties(tenant_id, id)
      on delete restrict;
  end if;
end
$$;

create unique index if not exists suppliers_tenant_party_key
  on public.suppliers(tenant_id, party_id)
  where party_id is not null;
create index if not exists idx_suppliers_party_id
  on public.suppliers(tenant_id, party_id);

create or replace function public.prepare_supplier_external_party()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_guard text := coalesce(
    current_setting('app.supplier_party_sync_guard', true),
    ''
  );
  v_expected_guard text := txid_current()::text || ':' || new.id::text;
  v_sync_tax_identifier boolean := false;
  v_tax_value text;
  v_tax_normalized text;
  v_identifier_id uuid;
  v_identifier_party_id uuid;
  v_business_date date;
begin
  if new.party_id is not null and new.party_id is distinct from new.id then
    raise exception 'Supplier party_id is immutable and must equal supplier id'
      using errcode = '23514';
  end if;

  if tg_op = 'UPDATE'
     and old.party_id is not null
     and new.party_id is distinct from old.party_id then
    raise exception 'Supplier party_id cannot be rebound'
      using errcode = '23514';
  end if;

  if new.party_id is null and new.tenant_id is not null then
    new.party_id := new.id;

    insert into public.external_parties (
      id,
      tenant_id,
      party_kind,
      display_name,
      legal_name,
      trade_name,
      is_active,
      metadata,
      created_at,
      updated_at
    ) values (
      new.id,
      new.tenant_id,
      'other',
      new.name,
      nullif(btrim(new.legal_name), ''),
      nullif(btrim(new.trade_name), ''),
      new.is_active,
      jsonb_build_object('source', 'supplier_compatibility_trigger'),
      coalesce(new.created_at, clock_timestamp()),
      coalesce(new.updated_at, clock_timestamp())
    ) on conflict (id) do nothing;
  elsif new.party_id = new.id
     and new.tenant_id is not null
     and v_guard <> v_expected_guard then
    update public.external_parties
    set display_name = new.name,
        legal_name = nullif(btrim(new.legal_name), ''),
        trade_name = nullif(btrim(new.trade_name), ''),
        is_active = new.is_active,
        updated_at = clock_timestamp()
    where tenant_id = new.tenant_id
      and id = new.party_id;
  end if;

  if tg_op = 'INSERT' then
    v_sync_tax_identifier := true;
  elsif tg_op = 'UPDATE' then
    v_sync_tax_identifier := new.rut is distinct from old.rut;
  end if;

  if v_guard <> v_expected_guard and v_sync_tax_identifier then
    v_business_date := public.tenant_business_date(new.tenant_id);
    v_tax_value := nullif(btrim(new.rut), '');

    if v_tax_value is null then
      delete from public.external_party_identifiers identifier
      where identifier.tenant_id = new.tenant_id
        and identifier.party_id = new.party_id
        and identifier.identifier_kind = 'tax_id'
        and identifier.valid_to is null
        and identifier.valid_from = v_business_date;

      update public.external_party_identifiers identifier
      set valid_to = v_business_date - 1,
          is_primary = false,
          updated_at = clock_timestamp()
      where identifier.tenant_id = new.tenant_id
        and identifier.party_id = new.party_id
        and identifier.identifier_kind = 'tax_id'
        and identifier.valid_to is null
        and identifier.valid_from < v_business_date;
    else
      v_tax_normalized := lower(regexp_replace(
        v_tax_value,
        '[^0-9A-Za-z]',
        '',
        'g'
      ));

      select identifier.id, identifier.party_id
      into v_identifier_id, v_identifier_party_id
      from public.external_party_identifiers identifier
      where identifier.tenant_id = new.tenant_id
        and identifier.identifier_kind = 'tax_id'
        and identifier.country_code = 'CL'
        and identifier.normalized_value = v_tax_normalized
        and identifier.valid_to is null
      limit 1;

      if v_identifier_id is not null
         and v_identifier_party_id is distinct from new.party_id then
        raise exception 'Tax identifier already belongs to another party'
          using errcode = '23505';
      end if;

      delete from public.external_party_identifiers identifier
      where identifier.tenant_id = new.tenant_id
        and identifier.party_id = new.party_id
        and identifier.identifier_kind = 'tax_id'
        and identifier.valid_to is null
        and identifier.valid_from = v_business_date
        and identifier.id is distinct from v_identifier_id;

      update public.external_party_identifiers identifier
      set valid_to = v_business_date - 1,
          is_primary = false,
          updated_at = clock_timestamp()
      where identifier.tenant_id = new.tenant_id
        and identifier.party_id = new.party_id
        and identifier.identifier_kind = 'tax_id'
        and identifier.valid_to is null
        and identifier.valid_from < v_business_date
        and identifier.id is distinct from v_identifier_id;

      if v_identifier_id is null then
        insert into public.external_party_identifiers (
          tenant_id,
          party_id,
          identifier_kind,
          country_code,
          normalized_value,
          display_value,
          is_primary,
          valid_from,
          metadata
        ) values (
          new.tenant_id,
          new.party_id,
          'tax_id',
          'CL',
          v_tax_normalized,
          v_tax_value,
          true,
          v_business_date,
          jsonb_build_object('source', 'supplier_legacy_bridge')
        );
      else
        update public.external_party_identifiers identifier
        set display_value = v_tax_value,
            is_primary = true,
            valid_to = null,
            updated_at = clock_timestamp()
        where identifier.id = v_identifier_id;
      end if;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.prepare_supplier_external_party() is
  'Transitional legacy bridge: direct writes to supplier identity columns flow to external_parties. The aggregate profile command owns canonical writes and sets a transaction-local guard so stale legacy columns cannot overwrite party identity.';

revoke all on function public.prepare_supplier_external_party()
  from public, anon, authenticated;

drop trigger if exists trg_prepare_supplier_external_party
  on public.suppliers;
create trigger trg_prepare_supplier_external_party
  before insert or update of
    party_id, tenant_id, name, legal_name, trade_name, rut, is_active
  on public.suppliers
  for each row
  execute function public.prepare_supplier_external_party();

-- ---------------------------------------------------------------------------
-- Relationship classifications, sites, and versioned engagements
-- ---------------------------------------------------------------------------

create table if not exists public.business_sites (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null check (btrim(code) <> ''),
  name text not null check (btrim(name) <> ''),
  site_kind text not null default 'other'
    check (site_kind in ('store', 'workshop', 'warehouse', 'office', 'other')),
  address text,
  city text,
  region text,
  comuna text,
  country_code text check (
    country_code is null or country_code ~ '^[A-Z]{2}$'
  ),
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, code)
);

create table if not exists public.supplier_role_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null check (code ~ '^[a-z][a-z0-9_]*$'),
  label text not null check (btrim(label) <> ''),
  description text,
  aliases text[] not null default '{}'::text[],
  is_active boolean not null default true,
  is_system boolean not null default false,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, code)
);

create table if not exists public.supplier_capability_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null check (code ~ '^[a-z][a-z0-9_]*$'),
  label text not null check (btrim(label) <> ''),
  description text,
  aliases text[] not null default '{}'::text[],
  is_active boolean not null default true,
  is_system boolean not null default false,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, code)
);

create table if not exists public.supplier_tag_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null check (code ~ '^[a-z][a-z0-9_]*$'),
  label text not null check (btrim(label) <> ''),
  description text,
  aliases text[] not null default '{}'::text[],
  is_active boolean not null default true,
  is_system boolean not null default false,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, code)
);

create table if not exists public.operational_nature_definitions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null check (code ~ '^[a-z][a-z0-9_]*$'),
  label text not null check (btrim(label) <> ''),
  nature_group text not null check (nature_group in (
    'inventory', 'operating_expense', 'service', 'tax', 'asset', 'other'
  )),
  description text,
  aliases text[] not null default '{}'::text[],
  is_active boolean not null default true,
  is_system boolean not null default false,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, code)
);

create or replace function public.seed_supplier_classification_definitions(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  insert into public.supplier_role_definitions (
    tenant_id, code, label, description, is_system
  ) values
    (p_tenant_id, 'goods_vendor', 'Proveedor de bienes',
      'Suministra bienes físicos para inventario u operación.', true),
    (p_tenant_id, 'service_provider', 'Proveedor de servicios',
      'Presta servicios operativos o profesionales.', true),
    (p_tenant_id, 'logistics_provider', 'Transporte y logística',
      'Mueve o entrega bienes.', true),
    (p_tenant_id, 'utility_provider', 'Servicios básicos',
      'Suministra servicios básicos del local.', true),
    (p_tenant_id, 'landlord', 'Arrendador',
      'Contraparte de arriendo o uso de inmueble.', true),
    (p_tenant_id, 'government_authority', 'Organismo público',
      'Autoridad, impuesto, tasa u obligación pública.', true),
    (p_tenant_id, 'digital_platform', 'Plataforma digital',
      'Servicio de red, dominio, publicidad o software.', true)
  on conflict (tenant_id, code) do update
  set label = excluded.label,
      description = excluded.description,
      is_system = true,
      updated_at = clock_timestamp();

  insert into public.supplier_capability_definitions (
    tenant_id, code, label, description, is_system
  ) values
    (p_tenant_id, 'purchase_invoices', 'Emite documentos de compra',
      'Puede originar facturas u otros documentos de compra.', true),
    (p_tenant_id, 'inventory_goods', 'Bienes de inventario',
      'Suministra bienes destinados a inventario y reventa.', true),
    (p_tenant_id, 'workshop_consumables', 'Insumos de taller',
      'Suministra consumibles utilizados en servicios de taller.', true),
    (p_tenant_id, 'freight_transport', 'Flete o transporte',
      'Presta transporte, despacho o última milla.', true),
    (p_tenant_id, 'digital_services', 'Servicios digitales',
      'Presta software, dominio, red, publicidad o plataforma.', true),
    (p_tenant_id, 'utilities', 'Suministros básicos',
      'Presta electricidad, agua u otro suministro básico.', true),
    (p_tenant_id, 'rent_lease', 'Arriendo',
      'Origina obligaciones de arriendo.', true),
    (p_tenant_id, 'tax_payments', 'Impuestos y tasas',
      'Recibe impuestos, tasas u obligaciones públicas.', true),
    (p_tenant_id, 'credential_portal', 'Portal o credencial',
      'Mantiene un portal, cuenta o credencial operativa.', true)
  on conflict (tenant_id, code) do update
  set label = excluded.label,
      description = excluded.description,
      is_system = true,
      updated_at = clock_timestamp();

  insert into public.supplier_tag_definitions (
    tenant_id, code, label, description, is_system
  ) values
    (p_tenant_id, 'bike_industry', 'Rubro bicicleta',
      'Contraparte directamente vinculada al rubro bicicleta.', true),
    (p_tenant_id, 'recurring', 'Recurrente',
      'Relación con recurrencia operativa o contractual.', true),
    (p_tenant_id, 'essential_service', 'Servicio esencial',
      'Servicio necesario para operar el local.', true),
    (p_tenant_id, 'government', 'Gobierno',
      'Contraparte perteneciente al sector público.', true),
    (p_tenant_id, 'digital', 'Digital',
      'Relación principalmente digital.', true),
    (p_tenant_id, 'facility', 'Infraestructura del local',
      'Relación vinculada al inmueble o infraestructura.', true),
    (p_tenant_id, 'transport', 'Transporte',
      'Relación vinculada a transporte o logística.', true)
  on conflict (tenant_id, code) do update
  set label = excluded.label,
      description = excluded.description,
      is_system = true,
      updated_at = clock_timestamp();

  insert into public.operational_nature_definitions (
    tenant_id, code, label, nature_group, description, is_system
  ) values
    (p_tenant_id, 'inventory_goods', 'Bienes para inventario', 'inventory',
      'Bienes destinados a inventario o reventa.', true),
    (p_tenant_id, 'workshop_consumables', 'Insumos de taller', 'inventory',
      'Consumibles incorporados a servicios de taller.', true),
    (p_tenant_id, 'freight_logistics', 'Flete y logística', 'service',
      'Transporte, despacho y logística.', true),
    (p_tenant_id, 'digital_services', 'Servicios digitales', 'service',
      'Software, dominios, redes, publicidad y plataformas.', true),
    (p_tenant_id, 'utilities', 'Servicios básicos', 'operating_expense',
      'Electricidad, agua y suministros básicos.', true),
    (p_tenant_id, 'rent_lease', 'Arriendo', 'operating_expense',
      'Arriendo de inmueble o activo operativo.', true),
    (p_tenant_id, 'taxes_fees', 'Impuestos y tasas', 'tax',
      'Impuestos, tasas y obligaciones públicas.', true),
    (p_tenant_id, 'professional_services', 'Servicios profesionales', 'service',
      'Servicios profesionales o especializados.', true),
    (p_tenant_id, 'capital_assets', 'Activo de capital', 'asset',
      'Adquisición capitalizable.', true),
    (p_tenant_id, 'other_operating_expense', 'Otro gasto operacional',
      'other', 'Clasificación explícita para otros gastos operativos.', true)
  on conflict (tenant_id, code) do update
  set label = excluded.label,
      nature_group = excluded.nature_group,
      description = excluded.description,
      is_system = true,
      updated_at = clock_timestamp();
end;
$$;

revoke all on function public.seed_supplier_classification_definitions(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.seed_supplier_classification_definitions(uuid)
  to service_role;

select public.seed_supplier_classification_definitions(tenant.id)
from public.tenants tenant;

create or replace function public.seed_supplier_classification_on_tenant()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform public.seed_supplier_classification_definitions(new.id);
  return new;
end;
$$;

revoke all on function public.seed_supplier_classification_on_tenant()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_seed_supplier_classification_on_tenant
  on public.tenants;
create trigger trg_seed_supplier_classification_on_tenant
  after insert on public.tenants
  for each row
  execute function public.seed_supplier_classification_on_tenant();

create table if not exists public.supplier_relationship_roles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  role_code text not null check (btrim(role_code) <> ''),
  valid_from date not null,
  valid_to date,
  assignment_source text not null default 'manual'
    check (assignment_source in ('manual', 'migration', 'observed', 'rule')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, supplier_id, role_code, valid_from),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade,
  foreign key (tenant_id, role_code)
    references public.supplier_role_definitions(tenant_id, code)
    on delete restrict,
  check (valid_to is null or valid_to >= valid_from)
);

create table if not exists public.supplier_relationship_capabilities (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  capability_code text not null check (btrim(capability_code) <> ''),
  valid_from date not null,
  valid_to date,
  assignment_source text not null default 'manual'
    check (assignment_source in ('manual', 'migration', 'observed', 'rule')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, supplier_id, capability_code, valid_from),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade,
  foreign key (tenant_id, capability_code)
    references public.supplier_capability_definitions(tenant_id, code)
    on delete restrict,
  check (valid_to is null or valid_to >= valid_from)
);

create table if not exists public.supplier_relationship_tags (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  tag_code text not null check (btrim(tag_code) <> ''),
  label text not null check (btrim(label) <> ''),
  valid_from date not null,
  valid_to date,
  assignment_source text not null default 'manual'
    check (assignment_source in ('manual', 'migration', 'observed', 'rule')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, supplier_id, tag_code, valid_from),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade,
  foreign key (tenant_id, tag_code)
    references public.supplier_tag_definitions(tenant_id, code)
    on delete restrict,
  check (valid_to is null or valid_to >= valid_from)
);

alter table public.supplier_relationship_roles
  alter column valid_from drop default;
alter table public.supplier_relationship_capabilities
  alter column valid_from drop default;
alter table public.supplier_relationship_tags
  alter column valid_from drop default;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'supplier_relationship_roles',
    'supplier_relationship_capabilities',
    'supplier_relationship_tags'
  ]
  loop
    execute format(
      'drop trigger if exists trg_00_supplier_business_valid_from on public.%I',
      table_name
    );
    execute format(
      'create trigger trg_00_supplier_business_valid_from before insert on public.%I for each row execute function public.set_supplier_business_valid_from()',
      table_name
    );
  end loop;
end
$$;

create unique index if not exists supplier_relationship_roles_current_key
  on public.supplier_relationship_roles(tenant_id, supplier_id, role_code)
  where valid_to is null;
create unique index if not exists supplier_relationship_capabilities_current_key
  on public.supplier_relationship_capabilities(
    tenant_id, supplier_id, capability_code
  ) where valid_to is null;
create unique index if not exists supplier_relationship_tags_current_key
  on public.supplier_relationship_tags(tenant_id, supplier_id, tag_code)
  where valid_to is null;

create table if not exists public.supplier_engagements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  site_id uuid,
  engagement_kind text not null check (engagement_kind in (
    'contract', 'service_account', 'subscription', 'lease', 'utility',
    'tax_obligation', 'portal', 'other'
  )),
  code text not null check (btrim(code) <> ''),
  name text not null check (btrim(name) <> ''),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'suspended', 'ended')),
  starts_on date,
  ends_on date,
  operation_id uuid not null default gen_random_uuid(),
  request_fingerprint text not null default '',
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, operation_id),
  unique (tenant_id, id, supplier_id),
  unique (tenant_id, supplier_id, code),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade,
  foreign key (tenant_id, site_id)
    references public.business_sites(tenant_id, id) on delete restrict,
  check (ends_on is null or starts_on is null or ends_on >= starts_on)
);

create table if not exists public.supplier_engagement_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  engagement_id uuid not null,
  version_number integer not null check (version_number > 0),
  effective_from date not null,
  effective_to date,
  external_reference text,
  service_identifier text,
  billing_cycle text not null default 'none' check (billing_cycle in (
    'free', 'monthly', 'bimonthly', 'quarterly', 'semiannual', 'annual',
    'irregular', 'none'
  )),
  currency_code text not null default 'CLP'
    check (currency_code ~ '^[A-Z]{3}$'),
  expected_amount numeric(14,2)
    check (expected_amount is null or expected_amount >= 0),
  due_day integer check (due_day between 1 and 31),
  portal_url text check (
    portal_url is null or public.is_safe_https_portal_url(portal_url)
  ),
  operation_id uuid not null default gen_random_uuid(),
  request_fingerprint text not null default '',
  terms jsonb not null default '{}'::jsonb
    check (jsonb_typeof(terms) = 'object'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, operation_id),
  unique (tenant_id, engagement_id, version_number),
  foreign key (tenant_id, engagement_id)
    references public.supplier_engagements(tenant_id, id) on delete cascade,
  check (effective_to is null or effective_to >= effective_from)
);

create unique index if not exists supplier_engagement_versions_current_key
  on public.supplier_engagement_versions(tenant_id, engagement_id)
  where effective_to is null;
create unique index if not exists supplier_engagement_versions_effective_key
  on public.supplier_engagement_versions(
    tenant_id, engagement_id, effective_from
  );
create index if not exists idx_supplier_engagements_supplier
  on public.supplier_engagements(tenant_id, supplier_id, status);
create index if not exists idx_supplier_engagements_site
  on public.supplier_engagements(tenant_id, site_id)
  where site_id is not null;

comment on table public.supplier_engagement_versions is
  'Versioned contract/service-account facts and recurrence hints. Engagements do not allocate money and never auto-post accounting entries.';

-- ---------------------------------------------------------------------------
-- Versioned accounting posture, separate matching rules, immutable evidence
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.expense_categories'::regclass
      and conname = 'expense_categories_tenant_id_id_key'
  ) then
    alter table public.expense_categories
      add constraint expense_categories_tenant_id_id_key
      unique (tenant_id, id);
  end if;
end
$$;

create table if not exists public.supplier_accounting_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  engagement_id uuid,
  code text not null check (btrim(code) <> ''),
  name text not null check (btrim(name) <> ''),
  status text not null default 'draft'
    check (status in ('draft', 'active', 'retired')),
  priority integer not null default 100,
  allow_exact_autofill boolean not null default false,
  operation_id uuid not null default gen_random_uuid(),
  request_fingerprint text not null default '',
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, operation_id),
  unique (tenant_id, supplier_id, code),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade,
  foreign key (tenant_id, engagement_id)
    references public.supplier_engagements(tenant_id, id) on delete cascade,
  foreign key (tenant_id, engagement_id, supplier_id)
    references public.supplier_engagements(tenant_id, id, supplier_id)
    on delete cascade
);

comment on column public.supplier_accounting_policies.allow_exact_autofill is
  'Allows exact rules to populate a draft suggestion. It never approves or posts an accounting entry.';

create table if not exists public.supplier_accounting_policy_versions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  policy_id uuid not null,
  version_number integer not null check (version_number > 0),
  effective_from date not null,
  effective_to date,
  operational_nature_code text not null
    check (btrim(operational_nature_code) <> ''),
  legacy_expense_category_id uuid,
  debit_account_id uuid,
  liability_account_id uuid,
  tax_treatment text not null default 'not_applicable' check (
    tax_treatment in (
      'no_tax', 'tax_included', 'exempt', 'not_applicable'
    )
  ),
  expected_document_type text,
  currency_code text not null default 'CLP'
    check (currency_code ~ '^[A-Z]{3}$'),
  line_nature text check (line_nature is null or line_nature in (
    'inventory', 'workshop_consumable', 'operating_expense', 'service',
    'freight', 'capital_asset', 'tax', 'discount', 'other'
  )),
  operation_id uuid not null default gen_random_uuid(),
  request_fingerprint text not null default '',
  posture jsonb not null default '{}'::jsonb
    check (jsonb_typeof(posture) = 'object'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, operation_id),
  unique (tenant_id, policy_id, version_number),
  foreign key (tenant_id, policy_id)
    references public.supplier_accounting_policies(tenant_id, id)
    on delete cascade,
  foreign key (tenant_id, operational_nature_code)
    references public.operational_nature_definitions(tenant_id, code)
    on delete restrict,
  foreign key (tenant_id, legacy_expense_category_id)
    references public.expense_categories(tenant_id, id)
    on delete set null (legacy_expense_category_id),
  foreign key (tenant_id, debit_account_id)
    references public.accounts(tenant_id, id) on delete restrict,
  foreign key (tenant_id, liability_account_id)
    references public.accounts(tenant_id, id) on delete restrict,
  check (effective_to is null or effective_to >= effective_from)
);

comment on column
  public.supplier_accounting_policy_versions.legacy_expense_category_id is
  'Transition-only bridge to the legacy expense category. operational_nature_code is the canonical classification owner.';

create unique index if not exists supplier_accounting_policy_versions_current_key
  on public.supplier_accounting_policy_versions(tenant_id, policy_id)
  where effective_to is null;
create unique index if not exists supplier_accounting_policy_versions_effective_key
  on public.supplier_accounting_policy_versions(
    tenant_id, policy_id, effective_from
  );

create table if not exists public.supplier_accounting_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  policy_version_id uuid not null,
  rule_kind text not null check (rule_kind in (
    'document_type', 'issuer_identifier', 'description',
    'line_description', 'engagement', 'amount_range', 'manual'
  )),
  operator text not null check (operator in (
    'equals', 'contains', 'prefix', 'regex', 'between', 'present'
  )),
  operand jsonb not null default '{}'::jsonb,
  priority integer not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, id, policy_version_id),
  foreign key (tenant_id, policy_version_id)
    references public.supplier_accounting_policy_versions(tenant_id, id)
    on delete cascade
);

create index if not exists idx_supplier_accounting_rules_version_priority
  on public.supplier_accounting_rules(
    tenant_id, policy_version_id, is_active, priority
  );

create table if not exists public.supplier_accounting_evidence (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  policy_version_id uuid,
  rule_id uuid,
  source_type text not null check (source_type in (
    'purchase_invoice', 'purchase_invoice_line', 'expense', 'expense_line',
    'received_tax_document', 'manual'
  )),
  source_id uuid not null,
  source_line_id uuid,
  decision text not null check (decision in (
    'suggested', 'accepted', 'overridden', 'rejected', 'auto_filled'
  )),
  operational_nature_code text not null
    check (btrim(operational_nature_code) <> ''),
  operational_nature_label text not null
    check (btrim(operational_nature_label) <> ''),
  debit_account_id uuid,
  debit_account_code text,
  liability_account_id uuid,
  liability_account_code text,
  legacy_expense_category_id uuid,
  legacy_expense_category_name text,
  rationale text,
  evidence jsonb not null default '{}'::jsonb
    check (jsonb_typeof(evidence) = 'object'),
  operation_id uuid not null,
  request_fingerprint text not null
    check (btrim(request_fingerprint) <> ''),
  applied_by uuid references auth.users(id) on delete set null,
  applied_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, operation_id),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete restrict,
  foreign key (tenant_id, policy_version_id)
    references public.supplier_accounting_policy_versions(tenant_id, id)
    on delete restrict,
  foreign key (tenant_id, rule_id)
    references public.supplier_accounting_rules(tenant_id, id)
    on delete restrict,
  foreign key (tenant_id, rule_id, policy_version_id)
    references public.supplier_accounting_rules(
      tenant_id, id, policy_version_id
    ) on delete restrict,
  foreign key (tenant_id, operational_nature_code)
    references public.operational_nature_definitions(tenant_id, code)
    on delete restrict,
  foreign key (tenant_id, debit_account_id)
    references public.accounts(tenant_id, id) on delete restrict,
  foreign key (tenant_id, liability_account_id)
    references public.accounts(tenant_id, id) on delete restrict,
  foreign key (tenant_id, legacy_expense_category_id)
    references public.expense_categories(tenant_id, id)
    on delete set null (legacy_expense_category_id),
  check (rule_id is null or policy_version_id is not null)
);

create index if not exists idx_supplier_accounting_evidence_source
  on public.supplier_accounting_evidence(
    tenant_id, source_type, source_id, applied_at desc
  );
create index if not exists idx_supplier_accounting_evidence_supplier
  on public.supplier_accounting_evidence(
    tenant_id, supplier_id, applied_at desc
  );

comment on table public.supplier_accounting_evidence is
  'Append-only evidence of suggestions and human decisions. Rows snapshot operational nature and account/category labels; they do not allocate amounts or post journals.';

create table if not exists public.supplier_classification_candidates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid,
  source_kind text not null check (source_kind in (
    'legacy_supplier_type', 'legacy_expense_category', 'legacy_expense_tag'
  )),
  source_id uuid,
  source_value text not null check (btrim(source_value) <> ''),
  target_vocabulary text not null check (target_vocabulary in (
    'role', 'capability', 'tag', 'operational_nature'
  )),
  suggested_code text check (
    suggested_code is null or suggested_code ~ '^[a-z][a-z0-9_]*$'
  ),
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'rejected')),
  rationale text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade,
  check (
    (status = 'pending' and reviewed_by is null and reviewed_at is null)
    or (status in ('confirmed', 'rejected') and reviewed_at is not null)
  )
);

create unique index if not exists supplier_classification_candidates_source_key
  on public.supplier_classification_candidates(
    tenant_id,
    coalesce(supplier_id, '00000000-0000-0000-0000-000000000000'::uuid),
    source_kind,
    coalesce(source_id, '00000000-0000-0000-0000-000000000000'::uuid),
    source_value,
    target_vocabulary
  );

insert into public.supplier_classification_candidates (
  tenant_id,
  supplier_id,
  source_kind,
  source_id,
  source_value,
  target_vocabulary,
  metadata
)
select
  supplier.tenant_id,
  supplier.id,
  'legacy_supplier_type',
  supplier.id,
  supplier.type,
  'role',
  jsonb_build_object('migration_source', 'suppliers.type')
from public.suppliers supplier
where nullif(btrim(supplier.type), '') is not null
on conflict do nothing;

insert into public.supplier_classification_candidates (
  tenant_id,
  source_kind,
  source_id,
  source_value,
  target_vocabulary,
  metadata
)
select
  category.tenant_id,
  'legacy_expense_category',
  category.id,
  category.name,
  'operational_nature',
  jsonb_build_object('migration_source', 'expense_categories')
from public.expense_categories category
where category.tenant_id is not null
  and nullif(btrim(category.name), '') is not null
on conflict do nothing;

insert into public.supplier_classification_candidates (
  tenant_id,
  supplier_id,
  source_kind,
  source_value,
  target_vocabulary,
  metadata
)
select distinct
  expense.tenant_id,
  expense.supplier_id,
  'legacy_expense_tag',
  btrim(tag.value),
  'tag',
  jsonb_build_object('migration_source', 'expenses.tags')
from public.expenses expense
cross join lateral unnest(coalesce(expense.tags, '{}'::text[])) tag(value)
where expense.supplier_id is not null
  and nullif(btrim(tag.value), '') is not null
on conflict do nothing;

comment on table public.supplier_classification_candidates is
  'Human-review queue for legacy supplier types, expense categories, and expense tags. Migration never assigns a canonical classification by matching names.';

create or replace function public.append_supplier_accounting_evidence(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_policy_version_id uuid := nullif(
    p_payload->>'policy_version_id', ''
  )::uuid;
  v_rule_id uuid := nullif(p_payload->>'rule_id', '')::uuid;
  v_source_type text := lower(btrim(coalesce(
    p_payload->>'source_type', ''
  )));
  v_source_id uuid := nullif(p_payload->>'source_id', '')::uuid;
  v_source_line_id uuid := nullif(p_payload->>'source_line_id', '')::uuid;
  v_decision text := lower(btrim(coalesce(p_payload->>'decision', '')));
  v_nature_code text := lower(btrim(coalesce(
    p_payload->>'operational_nature_code', ''
  )));
  v_nature_label text;
  v_debit_account_id uuid := nullif(
    p_payload->>'debit_account_id', ''
  )::uuid;
  v_debit_account_code text;
  v_liability_account_id uuid := nullif(
    p_payload->>'liability_account_id', ''
  )::uuid;
  v_liability_account_code text;
  v_legacy_category_id uuid := nullif(
    p_payload->>'legacy_expense_category_id', ''
  )::uuid;
  v_legacy_category_name text;
  v_evidence public.supplier_accounting_evidence%rowtype;
  v_operation_id uuid := nullif(p_payload->>'operation_id', '')::uuid;
  v_request_fingerprint text;
begin
  if v_role <> 'service_role'
     and not public.can_manage_tenant_accounting(p_tenant_id) then
    raise exception 'Accounting authority required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.suppliers supplier
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id
  ) then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  if v_operation_id is null then
    raise exception 'Accounting evidence operation_id is required'
      using errcode = '22023';
  end if;

  v_request_fingerprint := md5(jsonb_build_object(
    'supplier_id', p_supplier_id,
    'payload', p_payload - 'operation_id' - 'applied_by' - 'applied_at'
  )::text);

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_accounting_evidence:' || p_tenant_id::text || ':' ||
      v_operation_id::text,
      0
    )
  );

  select evidence_row.*
  into v_evidence
  from public.supplier_accounting_evidence evidence_row
  where evidence_row.tenant_id = p_tenant_id
    and evidence_row.operation_id = v_operation_id;

  if found then
    if v_evidence.request_fingerprint <> v_request_fingerprint then
      raise exception 'Accounting evidence operation id was reused with different content'
        using errcode = '23505';
    end if;

    return to_jsonb(v_evidence)
      || jsonb_build_object('idempotent_replay', true);
  end if;

  select nature.label
  into v_nature_label
  from public.operational_nature_definitions nature
  where nature.tenant_id = p_tenant_id
    and nature.code = v_nature_code
    and nature.is_active is true;

  if not found then
    raise exception 'Active operational nature not found in tenant'
      using errcode = '23503';
  end if;

  if v_policy_version_id is not null
     and not exists (
       select 1
       from public.supplier_accounting_policy_versions version
       join public.supplier_accounting_policies policy
         on policy.tenant_id = version.tenant_id
        and policy.id = version.policy_id
       where version.tenant_id = p_tenant_id
         and version.id = v_policy_version_id
         and policy.supplier_id = p_supplier_id
     ) then
    raise exception 'Accounting policy version does not belong to supplier'
      using errcode = '23514';
  end if;

  if v_rule_id is not null
     and (
       v_policy_version_id is null
       or not exists (
         select 1
         from public.supplier_accounting_rules rule
         where rule.tenant_id = p_tenant_id
           and rule.id = v_rule_id
           and rule.policy_version_id = v_policy_version_id
       )
     ) then
    raise exception 'Accounting rule does not belong to policy version'
      using errcode = '23514';
  end if;

  if v_source_type = 'purchase_invoice' then
    if not exists (
      select 1 from public.purchase_invoices invoice
      where invoice.tenant_id = p_tenant_id
        and invoice.id = v_source_id
        and invoice.supplier_id = p_supplier_id
    ) then
      raise exception 'Purchase invoice evidence source mismatch'
        using errcode = '23514';
    end if;
  elsif v_source_type = 'purchase_invoice_line' then
    if v_source_line_id is null or not exists (
      select 1
      from public.purchase_invoice_lines line
      join public.purchase_invoices invoice
        on invoice.tenant_id = line.tenant_id
       and invoice.id = line.purchase_invoice_id
      where line.tenant_id = p_tenant_id
        and line.id = v_source_line_id
        and invoice.id = v_source_id
        and invoice.supplier_id = p_supplier_id
    ) then
      raise exception 'Purchase line evidence source mismatch'
        using errcode = '23514';
    end if;
  elsif v_source_type = 'expense' then
    if not exists (
      select 1 from public.expenses expense
      where expense.tenant_id = p_tenant_id
        and expense.id = v_source_id
        and expense.supplier_id = p_supplier_id
    ) then
      raise exception 'Expense evidence source mismatch'
        using errcode = '23514';
    end if;
  elsif v_source_type = 'expense_line' then
    if v_source_line_id is null or not exists (
      select 1
      from public.expense_lines line
      join public.expenses expense
        on expense.tenant_id = line.tenant_id
       and expense.id = line.expense_id
      where line.tenant_id = p_tenant_id
        and line.id = v_source_line_id
        and expense.id = v_source_id
        and expense.supplier_id = p_supplier_id
    ) then
      raise exception 'Expense line evidence source mismatch'
        using errcode = '23514';
    end if;
  elsif v_source_type = 'received_tax_document' then
    if not exists (
      select 1 from public.received_tax_documents document
      where document.tenant_id = p_tenant_id
        and document.id = v_source_id
        and document.supplier_id = p_supplier_id
    ) then
      raise exception 'Received document evidence source mismatch'
        using errcode = '23514';
    end if;
  elsif v_source_type <> 'manual' then
    raise exception 'Unsupported evidence source type'
      using errcode = '22023';
  end if;

  if v_source_id is null then
    raise exception 'Evidence source id is required' using errcode = '22023';
  end if;

  if v_decision not in (
    'suggested', 'accepted', 'overridden', 'rejected'
  ) then
    raise exception 'Unsupported evidence decision' using errcode = '22023';
  end if;

  if v_debit_account_id is not null then
    select account.code
    into v_debit_account_code
    from public.accounts account
    where account.tenant_id = p_tenant_id
      and account.id = v_debit_account_id;
    if not found then
      raise exception 'Debit account not found in tenant' using errcode = '23503';
    end if;
  end if;

  if v_liability_account_id is not null then
    select account.code
    into v_liability_account_code
    from public.accounts account
    where account.tenant_id = p_tenant_id
      and account.id = v_liability_account_id;
    if not found then
      raise exception 'Liability account not found in tenant'
        using errcode = '23503';
    end if;
  end if;

  if v_legacy_category_id is not null then
    select category.name
    into v_legacy_category_name
    from public.expense_categories category
    where category.tenant_id = p_tenant_id
      and category.id = v_legacy_category_id;
    if not found then
      raise exception 'Legacy expense category not found in tenant'
        using errcode = '23503';
    end if;
  end if;

  insert into public.supplier_accounting_evidence (
    tenant_id,
    supplier_id,
    policy_version_id,
    rule_id,
    source_type,
    source_id,
    source_line_id,
    decision,
    operational_nature_code,
    operational_nature_label,
    debit_account_id,
    debit_account_code,
    liability_account_id,
    liability_account_code,
    legacy_expense_category_id,
    legacy_expense_category_name,
    rationale,
    evidence,
    operation_id,
    request_fingerprint,
    applied_by,
    applied_at
  ) values (
    p_tenant_id,
    p_supplier_id,
    v_policy_version_id,
    v_rule_id,
    v_source_type,
    v_source_id,
    v_source_line_id,
    v_decision,
    v_nature_code,
    v_nature_label,
    v_debit_account_id,
    v_debit_account_code,
    v_liability_account_id,
    v_liability_account_code,
    v_legacy_category_id,
    v_legacy_category_name,
    nullif(btrim(p_payload->>'rationale'), ''),
    coalesce(p_payload->'evidence', '{}'::jsonb),
    v_operation_id,
    v_request_fingerprint,
    case when v_role = 'service_role' then null else auth.uid() end,
    clock_timestamp()
  ) returning * into v_evidence;

  return to_jsonb(v_evidence)
    || jsonb_build_object('idempotent_replay', false);
end;
$$;

revoke all on function public.append_supplier_accounting_evidence(
  uuid, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.append_supplier_accounting_evidence(
  uuid, uuid, jsonb
) to authenticated, service_role;

create table if not exists public.supplier_classification_definition_command_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_id uuid not null,
  vocabulary text not null check (vocabulary in (
    'role', 'capability', 'tag', 'operational_nature'
  )),
  definition_code text not null check (
    definition_code ~ '^[a-z][a-z0-9_]*$'
  ),
  command_kind text not null check (command_kind in ('create', 'update')),
  request_fingerprint text not null check (btrim(request_fingerprint) <> ''),
  expected_updated_at timestamptz,
  result jsonb not null check (jsonb_typeof(result) = 'object'),
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_id),
  unique (tenant_id, id)
);

comment on table public.supplier_classification_definition_command_receipts is
  'Private idempotency receipts for tenant classification master-data commands. Payloads are fingerprinted; no arbitrary metadata is copied into the receipt.';

alter table public.supplier_classification_definition_command_receipts
  enable row level security;
revoke all on table public.supplier_classification_definition_command_receipts
  from public, anon, authenticated;

create or replace function public.upsert_supplier_classification_definition(
  p_tenant_id uuid,
  p_vocabulary text,
  p_definition jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_vocabulary text := lower(btrim(coalesce(p_vocabulary, '')));
  v_code text := lower(btrim(coalesce(p_definition->>'code', '')));
  v_label text := btrim(coalesce(p_definition->>'label', ''));
  v_aliases text[] := case
    when jsonb_typeof(p_definition->'aliases') = 'array' then array(
      select btrim(value)
      from jsonb_array_elements_text(p_definition->'aliases') value
      where btrim(value) <> ''
    )
    else '{}'::text[]
  end;
  v_is_active boolean := coalesce(
    (p_definition->>'is_active')::boolean,
    true
  );
  v_metadata jsonb := coalesce(p_definition->'metadata', '{}'::jsonb);
  v_result jsonb;
  v_is_system boolean;
begin
  if v_role <> 'service_role' and (
    (v_vocabulary = 'operational_nature'
      and not public.can_manage_tenant_accounting(p_tenant_id))
    or (v_vocabulary <> 'operational_nature'
      and not public.can_edit_tenant_settings(p_tenant_id))
  ) then
    raise exception 'Supplier classification authority required'
      using errcode = '42501';
  end if;

  if v_vocabulary not in ('role', 'capability', 'tag', 'operational_nature')
     or v_code !~ '^[a-z][a-z0-9_]*$'
     or v_label = ''
     or jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'Valid vocabulary, code, label, and metadata are required'
      using errcode = '22023';
  end if;

  if v_vocabulary = 'role' then
    select definition.is_system
    into v_is_system
    from public.supplier_role_definitions definition
    where definition.tenant_id = p_tenant_id
      and definition.code = v_code;

    if coalesce(v_is_system, false) then
      raise exception 'System supplier classifications are immutable'
        using errcode = '42501';
    end if;

    insert into public.supplier_role_definitions (
      tenant_id, code, label, description, aliases, is_active, is_system,
      metadata
    ) values (
      p_tenant_id, v_code, v_label,
      nullif(btrim(p_definition->>'description'), ''),
      v_aliases, v_is_active, false, v_metadata
    )
    on conflict (tenant_id, code) do update
    set label = excluded.label,
        description = excluded.description,
        aliases = excluded.aliases,
        is_active = excluded.is_active,
        metadata = excluded.metadata,
        updated_at = clock_timestamp()
    returning to_jsonb(supplier_role_definitions.*) into v_result;
  elsif v_vocabulary = 'capability' then
    select definition.is_system
    into v_is_system
    from public.supplier_capability_definitions definition
    where definition.tenant_id = p_tenant_id
      and definition.code = v_code;

    if coalesce(v_is_system, false) then
      raise exception 'System supplier classifications are immutable'
        using errcode = '42501';
    end if;

    insert into public.supplier_capability_definitions (
      tenant_id, code, label, description, aliases, is_active, is_system,
      metadata
    ) values (
      p_tenant_id, v_code, v_label,
      nullif(btrim(p_definition->>'description'), ''),
      v_aliases, v_is_active, false, v_metadata
    )
    on conflict (tenant_id, code) do update
    set label = excluded.label,
        description = excluded.description,
        aliases = excluded.aliases,
        is_active = excluded.is_active,
        metadata = excluded.metadata,
        updated_at = clock_timestamp()
    returning to_jsonb(supplier_capability_definitions.*) into v_result;
  elsif v_vocabulary = 'tag' then
    select definition.is_system
    into v_is_system
    from public.supplier_tag_definitions definition
    where definition.tenant_id = p_tenant_id
      and definition.code = v_code;

    if coalesce(v_is_system, false) then
      raise exception 'System supplier classifications are immutable'
        using errcode = '42501';
    end if;

    insert into public.supplier_tag_definitions (
      tenant_id, code, label, description, aliases, is_active, is_system,
      metadata
    ) values (
      p_tenant_id, v_code, v_label,
      nullif(btrim(p_definition->>'description'), ''),
      v_aliases, v_is_active, false, v_metadata
    )
    on conflict (tenant_id, code) do update
    set label = excluded.label,
        description = excluded.description,
        aliases = excluded.aliases,
        is_active = excluded.is_active,
        metadata = excluded.metadata,
        updated_at = clock_timestamp()
    returning to_jsonb(supplier_tag_definitions.*) into v_result;
  else
    select definition.is_system
    into v_is_system
    from public.operational_nature_definitions definition
    where definition.tenant_id = p_tenant_id
      and definition.code = v_code;

    if coalesce(v_is_system, false) then
      raise exception 'System supplier classifications are immutable'
        using errcode = '42501';
    end if;

    if coalesce(p_definition->>'nature_group', '') not in (
      'inventory', 'operating_expense', 'service', 'tax', 'asset', 'other'
    ) then
      raise exception 'Valid operational nature group is required'
        using errcode = '22023';
    end if;

    insert into public.operational_nature_definitions (
      tenant_id, code, label, nature_group, description, aliases,
      is_active, is_system, metadata
    ) values (
      p_tenant_id, v_code, v_label, p_definition->>'nature_group',
      nullif(btrim(p_definition->>'description'), ''),
      v_aliases, v_is_active, false, v_metadata
    )
    on conflict (tenant_id, code) do update
    set label = excluded.label,
        nature_group = excluded.nature_group,
        description = excluded.description,
        aliases = excluded.aliases,
        is_active = excluded.is_active,
        metadata = excluded.metadata,
        updated_at = clock_timestamp()
    returning to_jsonb(operational_nature_definitions.*) into v_result;
  end if;

  return jsonb_build_object('vocabulary', v_vocabulary)
    || coalesce(v_result, '{}'::jsonb);
end;
$$;

revoke all on function public.upsert_supplier_classification_definition(
  uuid, text, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.upsert_supplier_classification_definition(
  uuid, text, jsonb
) to service_role;

create or replace function public.upsert_supplier_classification_definition_v2(
  p_tenant_id uuid,
  p_vocabulary text,
  p_definition jsonb,
  p_operation_id uuid,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_vocabulary text := lower(btrim(coalesce(p_vocabulary, '')));
  v_code text := lower(btrim(coalesce(p_definition->>'code', '')));
  v_request_fingerprint text;
  v_receipt public.supplier_classification_definition_command_receipts%rowtype;
  v_current jsonb;
  v_current_updated_at timestamptz;
  v_action text;
  v_applied jsonb;
  v_result jsonb;
begin
  if v_role <> 'service_role' and (
    (v_vocabulary = 'operational_nature'
      and not public.can_manage_tenant_accounting(p_tenant_id))
    or (v_vocabulary <> 'operational_nature'
      and not public.can_edit_tenant_settings(p_tenant_id))
  ) then
    raise exception 'Supplier classification authority required'
      using errcode = '42501';
  end if;

  if p_operation_id is null
     or v_vocabulary not in (
       'role', 'capability', 'tag', 'operational_nature'
     )
     or v_code !~ '^[a-z][a-z0-9_]*$' then
    raise exception 'Valid operation id, vocabulary, and code are required'
      using errcode = '22023';
  end if;

  v_request_fingerprint := encode(extensions.digest(
    jsonb_build_object(
      'vocabulary', v_vocabulary,
      'definition', p_definition,
      'expected_updated_at', p_expected_updated_at
    )::text,
    'sha256'
  ), 'hex');

  perform pg_advisory_xact_lock(hashtextextended(
    'supplier_classification_definition_operation:' ||
      p_tenant_id::text || ':' || p_operation_id::text,
    0
  ));

  select receipt.*
  into v_receipt
  from public.supplier_classification_definition_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.operation_id = p_operation_id;

  if found then
    if v_receipt.request_fingerprint is distinct from v_request_fingerprint then
      raise exception 'Classification definition operation id was reused with different content'
        using errcode = '23505';
    end if;

    if v_vocabulary = 'role' then
      select to_jsonb(definition.*) into v_current
      from public.supplier_role_definitions definition
      where definition.tenant_id = p_tenant_id
        and definition.code = v_code;
    elsif v_vocabulary = 'capability' then
      select to_jsonb(definition.*) into v_current
      from public.supplier_capability_definitions definition
      where definition.tenant_id = p_tenant_id
        and definition.code = v_code;
    elsif v_vocabulary = 'tag' then
      select to_jsonb(definition.*) into v_current
      from public.supplier_tag_definitions definition
      where definition.tenant_id = p_tenant_id
        and definition.code = v_code;
    else
      select to_jsonb(definition.*) into v_current
      from public.operational_nature_definitions definition
      where definition.tenant_id = p_tenant_id
        and definition.code = v_code;
    end if;

    return v_receipt.result || jsonb_build_object(
      'idempotent_replay', true,
      'current_definition', v_current
    );
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'supplier_classification_definition:' || p_tenant_id::text || ':' ||
      v_vocabulary || ':' || v_code,
    0
  ));

  if v_vocabulary = 'role' then
    select to_jsonb(definition.*), definition.updated_at
    into v_current, v_current_updated_at
    from public.supplier_role_definitions definition
    where definition.tenant_id = p_tenant_id
      and definition.code = v_code
    for update;
  elsif v_vocabulary = 'capability' then
    select to_jsonb(definition.*), definition.updated_at
    into v_current, v_current_updated_at
    from public.supplier_capability_definitions definition
    where definition.tenant_id = p_tenant_id
      and definition.code = v_code
    for update;
  elsif v_vocabulary = 'tag' then
    select to_jsonb(definition.*), definition.updated_at
    into v_current, v_current_updated_at
    from public.supplier_tag_definitions definition
    where definition.tenant_id = p_tenant_id
      and definition.code = v_code
    for update;
  else
    select to_jsonb(definition.*), definition.updated_at
    into v_current, v_current_updated_at
    from public.operational_nature_definitions definition
    where definition.tenant_id = p_tenant_id
      and definition.code = v_code
    for update;
  end if;

  if v_current is null then
    if p_expected_updated_at is not null then
      raise exception 'Classification definition changed concurrently'
        using errcode = '40001';
    end if;
    v_action := 'create';
  else
    if p_expected_updated_at is null
       or v_current_updated_at is distinct from p_expected_updated_at then
      raise exception 'Classification definition changed concurrently'
        using errcode = '40001';
    end if;
    v_action := 'update';
  end if;

  v_applied := public.upsert_supplier_classification_definition(
    p_tenant_id,
    v_vocabulary,
    p_definition
  ) - 'vocabulary';

  v_result := jsonb_build_object(
    'operation_id', p_operation_id,
    'idempotent_replay', false,
    'vocabulary', v_vocabulary,
    'action', v_action,
    'applied_definition', v_applied,
    'current_definition', v_applied
  );

  insert into public.supplier_classification_definition_command_receipts (
    tenant_id,
    operation_id,
    vocabulary,
    definition_code,
    command_kind,
    request_fingerprint,
    expected_updated_at,
    result,
    actor_id
  ) values (
    p_tenant_id,
    p_operation_id,
    v_vocabulary,
    v_code,
    v_action,
    v_request_fingerprint,
    p_expected_updated_at,
    v_result,
    case when v_role = 'service_role' then null else auth.uid() end
  );

  return v_result;
end;
$$;

revoke all on function public.upsert_supplier_classification_definition_v2(
  uuid, text, jsonb, uuid, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.upsert_supplier_classification_definition_v2(
  uuid, text, jsonb, uuid, timestamptz
) to authenticated, service_role;

create or replace function public.review_supplier_classification_candidate(
  p_tenant_id uuid,
  p_candidate_id uuid,
  p_decision text,
  p_canonical_code text,
  p_rationale text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_decision text := lower(btrim(coalesce(p_decision, '')));
  v_code text := nullif(lower(btrim(p_canonical_code)), '');
  v_rationale text := nullif(btrim(p_rationale), '');
  v_candidate public.supplier_classification_candidates%rowtype;
  v_business_date date;
  v_definition_label text;
  v_applied_assignment jsonb;
  v_assignment_metadata jsonb;
begin
  select candidate.*
  into v_candidate
  from public.supplier_classification_candidates candidate
  where candidate.tenant_id = p_tenant_id
    and candidate.id = p_candidate_id
  for update;

  if not found then
    raise exception 'Supplier classification candidate not found'
      using errcode = 'P0002';
  end if;

  if v_role <> 'service_role' and (
    (v_candidate.target_vocabulary = 'operational_nature'
      and not public.can_manage_tenant_accounting(p_tenant_id))
    or (v_candidate.target_vocabulary <> 'operational_nature'
      and not public.can_edit_tenant_settings(p_tenant_id))
  ) then
    raise exception 'Supplier classification authority required'
      using errcode = '42501';
  end if;

  if v_decision not in ('confirmed', 'rejected') then
    raise exception 'Candidate decision must be confirmed or rejected'
      using errcode = '22023';
  end if;

  if v_decision = 'rejected' then
    v_code := null;
  end if;

  if v_candidate.status <> 'pending' then
    if v_candidate.status = v_decision
       and v_candidate.suggested_code is not distinct from v_code
       and v_candidate.rationale is not distinct from v_rationale then
      return to_jsonb(v_candidate)
        || jsonb_build_object('idempotent_replay', true);
    end if;

    raise exception 'Supplier classification candidate was already reviewed'
      using errcode = '23514';
  end if;

  if v_decision = 'confirmed' then
    if v_code is null then
      raise exception 'Confirmed candidate requires a canonical code'
        using errcode = '22023';
    end if;

    if (
      v_candidate.target_vocabulary = 'role' and not exists (
        select 1 from public.supplier_role_definitions definition
        where definition.tenant_id = p_tenant_id
          and definition.code = v_code and definition.is_active
      )
    ) or (
      v_candidate.target_vocabulary = 'capability' and not exists (
        select 1 from public.supplier_capability_definitions definition
        where definition.tenant_id = p_tenant_id
          and definition.code = v_code and definition.is_active
      )
    ) or (
      v_candidate.target_vocabulary = 'tag' and not exists (
        select 1 from public.supplier_tag_definitions definition
        where definition.tenant_id = p_tenant_id
          and definition.code = v_code and definition.is_active
      )
    ) or (
      v_candidate.target_vocabulary = 'operational_nature' and not exists (
        select 1 from public.operational_nature_definitions definition
        where definition.tenant_id = p_tenant_id
          and definition.code = v_code and definition.is_active
      )
    ) then
      raise exception 'Active canonical classification not found in tenant'
        using errcode = '23503';
    end if;

    if v_candidate.supplier_id is not null
       and v_candidate.target_vocabulary in ('role', 'capability', 'tag') then
      v_business_date := public.tenant_business_date(p_tenant_id);
      v_assignment_metadata := jsonb_build_object(
        'classification_candidate_id', v_candidate.id,
        'candidate_source_kind', v_candidate.source_kind,
        'candidate_source_id', v_candidate.source_id,
        'candidate_source_value', v_candidate.source_value,
        'confirmed_at', clock_timestamp()
      );

      perform pg_advisory_xact_lock(hashtextextended(
        'supplier_profile:' || p_tenant_id::text || ':' ||
          v_candidate.supplier_id::text,
        0
      ));

      if v_candidate.target_vocabulary = 'role' then
        update public.supplier_relationship_roles assignment
        set assignment_source = 'manual',
            metadata = coalesce(assignment.metadata, '{}'::jsonb)
              || v_assignment_metadata
              || jsonb_build_object(
                'confirmed_from_assignment_source',
                assignment.assignment_source
              ),
            updated_at = clock_timestamp()
        where assignment.tenant_id = p_tenant_id
          and assignment.supplier_id = v_candidate.supplier_id
          and assignment.role_code = v_code
          and assignment.valid_to is null
        returning to_jsonb(assignment.*) into v_applied_assignment;

        if not found then
          insert into public.supplier_relationship_roles (
            tenant_id, supplier_id, role_code, valid_from,
            assignment_source, metadata
          ) values (
            p_tenant_id, v_candidate.supplier_id, v_code, v_business_date,
            'manual', v_assignment_metadata
          )
          on conflict (tenant_id, supplier_id, role_code, valid_from)
          do update set valid_to = null,
              assignment_source = 'manual',
              metadata = coalesce(
                supplier_relationship_roles.metadata,
                '{}'::jsonb
              ) || v_assignment_metadata || jsonb_build_object(
                'confirmed_from_assignment_source',
                supplier_relationship_roles.assignment_source
              ),
              updated_at = clock_timestamp()
          returning to_jsonb(supplier_relationship_roles.*)
          into v_applied_assignment;
        end if;
      elsif v_candidate.target_vocabulary = 'capability' then
        update public.supplier_relationship_capabilities assignment
        set assignment_source = 'manual',
            metadata = coalesce(assignment.metadata, '{}'::jsonb)
              || v_assignment_metadata
              || jsonb_build_object(
                'confirmed_from_assignment_source',
                assignment.assignment_source
              ),
            updated_at = clock_timestamp()
        where assignment.tenant_id = p_tenant_id
          and assignment.supplier_id = v_candidate.supplier_id
          and assignment.capability_code = v_code
          and assignment.valid_to is null
        returning to_jsonb(assignment.*) into v_applied_assignment;

        if not found then
          insert into public.supplier_relationship_capabilities (
            tenant_id, supplier_id, capability_code, valid_from,
            assignment_source, metadata
          ) values (
            p_tenant_id, v_candidate.supplier_id, v_code, v_business_date,
            'manual', v_assignment_metadata
          )
          on conflict (tenant_id, supplier_id, capability_code, valid_from)
          do update set valid_to = null,
              assignment_source = 'manual',
              metadata = coalesce(
                supplier_relationship_capabilities.metadata,
                '{}'::jsonb
              ) || v_assignment_metadata || jsonb_build_object(
                'confirmed_from_assignment_source',
                supplier_relationship_capabilities.assignment_source
              ),
              updated_at = clock_timestamp()
          returning to_jsonb(supplier_relationship_capabilities.*)
          into v_applied_assignment;
        end if;
      else
        select definition.label
        into strict v_definition_label
        from public.supplier_tag_definitions definition
        where definition.tenant_id = p_tenant_id
          and definition.code = v_code;

        update public.supplier_relationship_tags assignment
        set label = v_definition_label,
            assignment_source = 'manual',
            metadata = coalesce(assignment.metadata, '{}'::jsonb)
              || v_assignment_metadata
              || jsonb_build_object(
                'confirmed_from_assignment_source',
                assignment.assignment_source
              ),
            updated_at = clock_timestamp()
        where assignment.tenant_id = p_tenant_id
          and assignment.supplier_id = v_candidate.supplier_id
          and assignment.tag_code = v_code
          and assignment.valid_to is null
        returning to_jsonb(assignment.*) into v_applied_assignment;

        if not found then
          insert into public.supplier_relationship_tags (
            tenant_id, supplier_id, tag_code, label, valid_from,
            assignment_source, metadata
          ) values (
            p_tenant_id, v_candidate.supplier_id, v_code,
            v_definition_label, v_business_date, 'manual',
            v_assignment_metadata
          )
          on conflict (tenant_id, supplier_id, tag_code, valid_from)
          do update set valid_to = null,
              label = excluded.label,
              assignment_source = 'manual',
              metadata = coalesce(
                supplier_relationship_tags.metadata,
                '{}'::jsonb
              ) || v_assignment_metadata || jsonb_build_object(
                'confirmed_from_assignment_source',
                supplier_relationship_tags.assignment_source
              ),
              updated_at = clock_timestamp()
          returning to_jsonb(supplier_relationship_tags.*)
          into v_applied_assignment;
        end if;
      end if;
    end if;
  end if;

  update public.supplier_classification_candidates candidate
  set status = v_decision,
      suggested_code = v_code,
      rationale = v_rationale,
      reviewed_by = case when v_role = 'service_role'
        then null else auth.uid() end,
      reviewed_at = clock_timestamp(),
      metadata = candidate.metadata || case
        when v_applied_assignment is null then '{}'::jsonb
        else jsonb_build_object(
          'applied_assignment_id', v_applied_assignment->>'id'
        )
      end,
      updated_at = clock_timestamp()
  where candidate.id = v_candidate.id
  returning * into v_candidate;

  return to_jsonb(v_candidate)
    || jsonb_build_object(
      'idempotent_replay', false,
      'applied_assignment', v_applied_assignment
    );
end;
$$;

revoke all on function public.review_supplier_classification_candidate(
  uuid, uuid, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.review_supplier_classification_candidate(
  uuid, uuid, text, text, text
) to authenticated, service_role;

create or replace view public.supplier_classification_candidate_read_model
with (security_invoker = true)
as
select
  candidate.tenant_id,
  candidate.id as candidate_id,
  candidate.supplier_id,
  coalesce(party.display_name, supplier.name) as supplier_display_name,
  candidate.source_kind,
  candidate.source_id,
  candidate.source_value,
  candidate.target_vocabulary,
  candidate.suggested_code,
  case candidate.target_vocabulary
    when 'role' then (
      select definition.label
      from public.supplier_role_definitions definition
      where definition.tenant_id = candidate.tenant_id
        and definition.code = candidate.suggested_code
    )
    when 'capability' then (
      select definition.label
      from public.supplier_capability_definitions definition
      where definition.tenant_id = candidate.tenant_id
        and definition.code = candidate.suggested_code
    )
    when 'tag' then (
      select definition.label
      from public.supplier_tag_definitions definition
      where definition.tenant_id = candidate.tenant_id
        and definition.code = candidate.suggested_code
    )
    when 'operational_nature' then (
      select definition.label
      from public.operational_nature_definitions definition
      where definition.tenant_id = candidate.tenant_id
        and definition.code = candidate.suggested_code
    )
  end as suggested_label,
  candidate.status,
  candidate.rationale,
  candidate.reviewed_by,
  candidate.reviewed_at,
  candidate.metadata,
  candidate.created_at,
  candidate.updated_at
from public.supplier_classification_candidates candidate
left join public.suppliers supplier
  on supplier.tenant_id = candidate.tenant_id
 and supplier.id = candidate.supplier_id
left join public.external_parties party
  on party.tenant_id = supplier.tenant_id
 and party.id = supplier.party_id;

comment on view public.supplier_classification_candidate_read_model is
  'Tenant-scoped human review queue for legacy classification candidates. It never guesses or applies a canonical code.';

-- ---------------------------------------------------------------------------
-- Received tax-document identity and normalized purchase lines
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.purchase_invoices'::regclass
      and conname = 'purchase_invoices_tenant_id_id_key'
  ) then
    alter table public.purchase_invoices
      add constraint purchase_invoices_tenant_id_id_key
      unique (tenant_id, id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.products'::regclass
      and conname = 'products_tenant_id_id_key'
  ) then
    alter table public.products
      add constraint products_tenant_id_id_key unique (tenant_id, id);
  end if;
end
$$;

create table if not exists public.received_tax_documents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  issuer_party_id uuid not null,
  supplier_id uuid,
  purchase_invoice_id uuid,
  document_type_code text not null check (btrim(document_type_code) <> ''),
  normalized_folio text not null check (btrim(normalized_folio) <> ''),
  display_folio text,
  issued_on date,
  received_at timestamptz not null default clock_timestamp(),
  currency_code text not null default 'CLP'
    check (currency_code ~ '^[A-Z]{3}$'),
  net_amount numeric(14,2) not null default 0 check (net_amount >= 0),
  exempt_amount numeric(14,2) not null default 0 check (exempt_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  status text not null default 'captured'
    check (status in ('captured', 'validated', 'linked', 'voided')),
  source text not null default 'manual'
    check (source in ('manual', 'ocr', 'import', 'integration')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (
    tenant_id, issuer_party_id, document_type_code, normalized_folio
  ),
  foreign key (tenant_id, issuer_party_id)
    references public.external_parties(tenant_id, id) on delete restrict,
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete restrict,
  foreign key (tenant_id, purchase_invoice_id)
    references public.purchase_invoices(tenant_id, id) on delete restrict
);

create unique index if not exists received_tax_documents_purchase_invoice_key
  on public.received_tax_documents(tenant_id, purchase_invoice_id)
  where purchase_invoice_id is not null;
create index if not exists idx_received_tax_documents_supplier_issued
  on public.received_tax_documents(
    tenant_id, supplier_id, issued_on desc
  );

create or replace function public.normalize_received_tax_document()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_invoice_supplier_id uuid;
  v_invoice_document_id uuid;
begin
  new.document_type_code := lower(btrim(new.document_type_code));
  new.normalized_folio := upper(regexp_replace(
    coalesce(nullif(btrim(new.normalized_folio), ''), new.display_folio, ''),
    '[^0-9A-Za-z]',
    '',
    'g'
  ));

  if new.document_type_code = '' or new.normalized_folio = '' then
    raise exception 'Document type and folio are required'
      using errcode = '22023';
  end if;

  if new.purchase_invoice_id is not null then
    select invoice.supplier_id, invoice.received_tax_document_id
    into v_invoice_supplier_id, v_invoice_document_id
    from public.purchase_invoices invoice
    where invoice.tenant_id = new.tenant_id
      and invoice.id = new.purchase_invoice_id;

    if not found then
      raise exception 'Purchase invoice not found in received document tenant'
        using errcode = '23503';
    end if;

    if new.supplier_id is null then
      new.supplier_id := v_invoice_supplier_id;
    end if;

    if v_invoice_supplier_id is null
       or v_invoice_supplier_id is distinct from new.supplier_id then
      raise exception 'Received document supplier does not match purchase invoice'
        using errcode = '23514';
    end if;

    if v_invoice_document_id is not null
       and v_invoice_document_id is distinct from new.id then
      raise exception 'Purchase invoice is linked to another received document'
        using errcode = '23514';
    end if;
  end if;

  if new.supplier_id is not null and not exists (
    select 1
    from public.suppliers supplier
    where supplier.tenant_id = new.tenant_id
      and supplier.id = new.supplier_id
      and supplier.party_id = new.issuer_party_id
  ) then
    raise exception 'Received document issuer does not match supplier party'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function public.normalize_received_tax_document()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_normalize_received_tax_document
  on public.received_tax_documents;
create trigger trg_normalize_received_tax_document
  before insert or update of
    document_type_code, normalized_folio, display_folio,
    tenant_id, issuer_party_id, supplier_id, purchase_invoice_id
  on public.received_tax_documents
  for each row
  execute function public.normalize_received_tax_document();

alter table public.purchase_invoices
  add column if not exists received_tax_document_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.purchase_invoices'::regclass
      and conname = 'purchase_invoices_received_tax_document_fkey'
  ) then
    alter table public.purchase_invoices
      add constraint purchase_invoices_received_tax_document_fkey
      foreign key (tenant_id, received_tax_document_id)
      references public.received_tax_documents(tenant_id, id)
      on delete set null (received_tax_document_id);
  end if;
end
$$;

create unique index if not exists purchase_invoices_received_tax_document_key
  on public.purchase_invoices(tenant_id, received_tax_document_id)
  where received_tax_document_id is not null;

create or replace function public.validate_purchase_invoice_tax_document_link()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_document_supplier_id uuid;
  v_document_invoice_id uuid;
begin
  if new.received_tax_document_id is null then
    return new;
  end if;

  select document.supplier_id, document.purchase_invoice_id
  into v_document_supplier_id, v_document_invoice_id
  from public.received_tax_documents document
  where document.tenant_id = new.tenant_id
    and document.id = new.received_tax_document_id;

  if not found then
    raise exception 'Received tax document not found in purchase invoice tenant'
      using errcode = '23503';
  end if;

  if new.supplier_id is null
     or v_document_supplier_id is distinct from new.supplier_id then
    raise exception 'Purchase invoice supplier does not match received document'
      using errcode = '23514';
  end if;

  if v_document_invoice_id is not null
     and v_document_invoice_id is distinct from new.id then
    raise exception 'Received document is linked to another purchase invoice'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_purchase_invoice_tax_document_link()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_validate_purchase_invoice_tax_document_link
  on public.purchase_invoices;
create trigger trg_validate_purchase_invoice_tax_document_link
  before insert or update of
    tenant_id, supplier_id, received_tax_document_id
  on public.purchase_invoices
  for each row
  execute function public.validate_purchase_invoice_tax_document_link();

create or replace function public.sync_received_tax_document_invoice_link()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_guard text := coalesce(
    current_setting('app.tax_document_link_sync_guard', true),
    ''
  );
  v_expected_guard text := txid_current()::text;
begin
  if v_guard = v_expected_guard then
    return new;
  end if;

  perform set_config(
    'app.tax_document_link_sync_guard',
    v_expected_guard,
    true
  );

  if tg_op = 'UPDATE'
     and old.purchase_invoice_id is distinct from new.purchase_invoice_id
     and old.purchase_invoice_id is not null then
    update public.purchase_invoices invoice
    set received_tax_document_id = null,
        updated_at = clock_timestamp()
    where invoice.tenant_id = old.tenant_id
      and invoice.id = old.purchase_invoice_id
      and invoice.received_tax_document_id = old.id;
  end if;

  if new.purchase_invoice_id is not null then
    update public.purchase_invoices invoice
    set received_tax_document_id = new.id,
        updated_at = clock_timestamp()
    where invoice.tenant_id = new.tenant_id
      and invoice.id = new.purchase_invoice_id
      and invoice.received_tax_document_id is distinct from new.id;
  end if;

  perform set_config('app.tax_document_link_sync_guard', '', true);

  return new;
end;
$$;

revoke all on function public.sync_received_tax_document_invoice_link()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_sync_received_tax_document_invoice_link
  on public.received_tax_documents;
create trigger trg_sync_received_tax_document_invoice_link
  after insert or update of purchase_invoice_id, tenant_id
  on public.received_tax_documents
  for each row
  execute function public.sync_received_tax_document_invoice_link();

create or replace function public.sync_purchase_invoice_tax_document_link()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_guard text := coalesce(
    current_setting('app.tax_document_link_sync_guard', true),
    ''
  );
  v_expected_guard text := txid_current()::text;
begin
  if v_guard = v_expected_guard then
    return new;
  end if;

  perform set_config(
    'app.tax_document_link_sync_guard',
    v_expected_guard,
    true
  );

  if tg_op = 'UPDATE'
     and old.received_tax_document_id
       is distinct from new.received_tax_document_id
     and old.received_tax_document_id is not null then
    update public.received_tax_documents document
    set purchase_invoice_id = null,
        updated_at = clock_timestamp()
    where document.tenant_id = old.tenant_id
      and document.id = old.received_tax_document_id
      and document.purchase_invoice_id = old.id;
  end if;

  if new.received_tax_document_id is not null then
    update public.received_tax_documents document
    set purchase_invoice_id = new.id,
        updated_at = clock_timestamp()
    where document.tenant_id = new.tenant_id
      and document.id = new.received_tax_document_id
      and document.purchase_invoice_id is distinct from new.id;
  end if;

  perform set_config('app.tax_document_link_sync_guard', '', true);

  return new;
end;
$$;

revoke all on function public.sync_purchase_invoice_tax_document_link()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_sync_purchase_invoice_tax_document_link
  on public.purchase_invoices;
create trigger trg_sync_purchase_invoice_tax_document_link
  after insert or update of received_tax_document_id, tenant_id
  on public.purchase_invoices
  for each row
  execute function public.sync_purchase_invoice_tax_document_link();

-- PostgreSQL's composite FK action correctly nulls only
-- received_tax_document_id, but that internal UPDATE does not pass through the
-- inventory trace capture frame on every supported runtime. Unlink explicitly
-- while the document still exists so the ordinary, fully traced invoice UPDATE
-- owns the state change; the FK then has no row left to mutate.
create or replace function public.unlink_received_tax_document_before_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_guard text := txid_current()::text;
begin
  perform set_config(
    'app.tax_document_link_sync_guard',
    v_guard,
    true
  );

  update public.purchase_invoices invoice
  set received_tax_document_id = null,
      updated_at = clock_timestamp()
  where invoice.tenant_id = old.tenant_id
    and invoice.id = old.purchase_invoice_id
    and invoice.received_tax_document_id = old.id;

  perform set_config('app.tax_document_link_sync_guard', '', true);
  return old;
end;
$$;

revoke all on function public.unlink_received_tax_document_before_delete()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_unlink_received_tax_document_before_delete
  on public.received_tax_documents;
create trigger trg_unlink_received_tax_document_before_delete
  before delete on public.received_tax_documents
  for each row
  execute function public.unlink_received_tax_document_before_delete();

create table if not exists public.purchase_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_invoice_id uuid not null,
  line_number integer not null check (line_number > 0),
  source_line_index integer check (
    source_line_index is null or source_line_index >= 0
  ),
  line_kind text not null default 'item'
    check (line_kind in ('item', 'adjustment')),
  adjustment_kind text check (adjustment_kind is null or adjustment_kind in (
    'global_discount', 'additional_cost', 'document_reconciliation'
  )),
  product_id uuid,
  line_nature text not null default 'other' check (line_nature in (
    'inventory', 'workshop_consumable', 'operating_expense', 'service',
    'freight', 'capital_asset', 'tax', 'discount', 'other'
  )),
  classification_status text not null default 'needs_review'
    check (classification_status in ('classified', 'needs_review')),
  description text not null check (btrim(description) <> ''),
  product_name_snapshot text,
  product_sku_snapshot text,
  quantity numeric(14,4) not null default 1 check (quantity >= 0),
  unit_cost numeric(14,4) not null default 0 check (unit_cost >= 0),
  discount_amount numeric(14,2) not null default 0
    check (discount_amount >= 0),
  net_amount numeric(14,2) not null default 0,
  tax_rate numeric(7,4) not null default 0 check (tax_rate >= 0),
  tax_amount numeric(14,2) not null default 0,
  total_amount numeric(14,2) not null default 0,
  currency_code text not null default 'CLP'
    check (currency_code ~ '^[A-Z]{3}$'),
  source_kind text not null default 'native'
    check (source_kind in ('native', 'legacy_json', 'migration')),
  source_item jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, purchase_invoice_id, line_number),
  foreign key (tenant_id, purchase_invoice_id)
    references public.purchase_invoices(tenant_id, id) on delete cascade,
  foreign key (tenant_id, product_id)
    references public.products(tenant_id, id)
    on delete set null (product_id),
  check (
    (line_kind = 'item' and adjustment_kind is null
      and net_amount >= 0 and tax_amount >= 0 and total_amount >= 0)
    or (line_kind = 'adjustment' and adjustment_kind is not null
      and product_id is null and source_line_index is null)
  )
);

create index if not exists idx_purchase_invoice_lines_product
  on public.purchase_invoice_lines(tenant_id, product_id)
  where product_id is not null;
create index if not exists idx_purchase_invoice_lines_nature
  on public.purchase_invoice_lines(tenant_id, line_nature);
create unique index if not exists purchase_invoice_lines_source_index_key
  on public.purchase_invoice_lines(
    tenant_id, purchase_invoice_id, source_line_index
  ) where source_line_index is not null;

comment on column public.purchase_invoice_lines.source_item is
  'Replay/audit snapshot of the legacy JSON item. It is not the long-term write owner.';

comment on column public.purchase_invoice_lines.source_line_index is
  'Zero-based legacy JSON ordinal retained for receipt/credit-note compatibility. Normalization never reorders the legacy array.';

create or replace function public.sync_purchase_invoice_lines_from_legacy_json(
  p_purchase_invoice_id uuid,
  p_source_kind text default 'legacy_json'
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_invoice public.purchase_invoices%rowtype;
  v_item jsonb;
  v_ordinal bigint;
  v_product_id uuid;
  v_product_treatment text;
  v_explicit_treatment text;
  v_line_nature text;
  v_quantity numeric(14,4);
  v_unit_cost numeric(14,4);
  v_discount numeric(14,2);
  v_net numeric(14,2);
  v_tax_rate numeric(7,4);
  v_tax numeric(14,2);
  v_additional_cost jsonb;
  v_additional_ordinal bigint;
  v_adjustment_amount numeric(14,2);
  v_normalized_total numeric(14,2);
  v_reconciliation_amount numeric(14,2);
  v_count integer := 0;
begin
  if p_source_kind not in ('legacy_json', 'migration') then
    raise exception 'Invalid legacy line source kind'
      using errcode = '22023';
  end if;

  select invoice.*
  into v_invoice
  from public.purchase_invoices invoice
  where invoice.id = p_purchase_invoice_id
  for update;

  if not found then
    raise exception 'Purchase invoice not found' using errcode = 'P0002';
  end if;

  for v_item, v_ordinal in
    select item, ordinality
    from jsonb_array_elements(
      case
        when jsonb_typeof(v_invoice.items) = 'array' then v_invoice.items
        else '[]'::jsonb
      end
    ) with ordinality as legacy(item, ordinality)
  loop
    v_product_id := null;
    v_product_treatment := null;

    if coalesce(v_item->>'product_id', '')
       ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      select product.id, product.purchase_treatment
      into v_product_id, v_product_treatment
      from public.products product
      where product.tenant_id = v_invoice.tenant_id
        and product.id = (v_item->>'product_id')::uuid;
    end if;

    v_explicit_treatment := nullif(btrim(v_item->>'purchase_treatment'), '');
    v_line_nature := case
      when v_explicit_treatment in (
        'inventory', 'workshop_consumable', 'operating_expense', 'service',
        'freight', 'capital_asset', 'tax', 'discount', 'other'
      ) then v_explicit_treatment
      when v_product_treatment in ('inventory', 'workshop_consumable')
        then v_product_treatment
      else 'other'
    end;

    v_quantity := case
      when coalesce(v_item->>'quantity', '') ~ '^-?[0-9]+([.][0-9]+)?$'
        then greatest((v_item->>'quantity')::numeric, 0)
      else 0
    end;
    v_unit_cost := case
      when coalesce(v_item->>'unit_cost', '') ~ '^-?[0-9]+([.][0-9]+)?$'
        then greatest((v_item->>'unit_cost')::numeric, 0)
      else 0
    end;
    v_discount := case
      when coalesce(v_item->>'discount', '') ~ '^-?[0-9]+([.][0-9]+)?$'
        then greatest((v_item->>'discount')::numeric, 0)
      else 0
    end;
    v_net := greatest(round((v_quantity * v_unit_cost) - v_discount), 0);
    v_tax_rate := case
      when coalesce(v_item->>'iva_rate', '') ~ '^-?[0-9]+([.][0-9]+)?$'
        then greatest((v_item->>'iva_rate')::numeric, 0)
      else 0
    end;
    v_tax := case
      when v_invoice.tax_treatment = 'tax_included'
        then greatest(round(v_net * v_tax_rate), 0)
      else 0
    end;

    insert into public.purchase_invoice_lines (
      tenant_id,
      purchase_invoice_id,
      line_number,
      source_line_index,
      line_kind,
      adjustment_kind,
      product_id,
      line_nature,
      classification_status,
      description,
      product_name_snapshot,
      product_sku_snapshot,
      quantity,
      unit_cost,
      discount_amount,
      net_amount,
      tax_rate,
      tax_amount,
      total_amount,
      currency_code,
      source_kind,
      source_item
    ) values (
      v_invoice.tenant_id,
      v_invoice.id,
      v_ordinal::integer,
      (v_ordinal - 1)::integer,
      'item',
      null,
      v_product_id,
      v_line_nature,
      case when v_line_nature = 'other'
        then 'needs_review' else 'classified' end,
      coalesce(
        nullif(btrim(v_item->>'description'), ''),
        nullif(btrim(v_item->>'product_name'), ''),
        'Línea ' || v_ordinal::text
      ),
      nullif(btrim(v_item->>'product_name'), ''),
      nullif(btrim(v_item->>'product_sku'), ''),
      v_quantity,
      v_unit_cost,
      v_discount,
      v_net,
      v_tax_rate,
      v_tax,
      v_net + v_tax,
      'CLP',
      p_source_kind,
      v_item
    )
    on conflict (tenant_id, purchase_invoice_id, line_number)
    do update set
      source_line_index = excluded.source_line_index,
      line_kind = excluded.line_kind,
      adjustment_kind = excluded.adjustment_kind,
      product_id = excluded.product_id,
      line_nature = excluded.line_nature,
      classification_status = excluded.classification_status,
      description = excluded.description,
      product_name_snapshot = excluded.product_name_snapshot,
      product_sku_snapshot = excluded.product_sku_snapshot,
      quantity = excluded.quantity,
      unit_cost = excluded.unit_cost,
      discount_amount = excluded.discount_amount,
      net_amount = excluded.net_amount,
      tax_rate = excluded.tax_rate,
      tax_amount = excluded.tax_amount,
      total_amount = excluded.total_amount,
      source_kind = excluded.source_kind,
      source_item = excluded.source_item,
      updated_at = clock_timestamp()
    where public.purchase_invoice_lines.source_kind in (
      'legacy_json', 'migration'
    );

    v_count := v_count + 1;
  end loop;

  if coalesce(v_invoice.discount_amount, 0) > 0 then
    v_count := v_count + 1;
    v_adjustment_amount := round(v_invoice.discount_amount, 2);

    insert into public.purchase_invoice_lines (
      tenant_id,
      purchase_invoice_id,
      line_number,
      source_line_index,
      line_kind,
      adjustment_kind,
      product_id,
      line_nature,
      classification_status,
      description,
      quantity,
      unit_cost,
      discount_amount,
      net_amount,
      tax_rate,
      tax_amount,
      total_amount,
      currency_code,
      source_kind,
      source_item
    ) values (
      v_invoice.tenant_id,
      v_invoice.id,
      v_count,
      null,
      'adjustment',
      'global_discount',
      null,
      'discount',
      'classified',
      'Descuento global del documento',
      1,
      0,
      v_adjustment_amount,
      -v_adjustment_amount,
      0,
      0,
      -v_adjustment_amount,
      'CLP',
      p_source_kind,
      jsonb_build_object(
        'adjustment_kind', 'global_discount',
        'document_discount_amount', v_adjustment_amount
      )
    )
    on conflict (tenant_id, purchase_invoice_id, line_number)
    do update set
      source_line_index = null,
      line_kind = excluded.line_kind,
      adjustment_kind = excluded.adjustment_kind,
      product_id = null,
      line_nature = excluded.line_nature,
      classification_status = excluded.classification_status,
      description = excluded.description,
      product_name_snapshot = null,
      product_sku_snapshot = null,
      quantity = excluded.quantity,
      unit_cost = excluded.unit_cost,
      discount_amount = excluded.discount_amount,
      net_amount = excluded.net_amount,
      tax_rate = excluded.tax_rate,
      tax_amount = excluded.tax_amount,
      total_amount = excluded.total_amount,
      source_kind = excluded.source_kind,
      source_item = excluded.source_item,
      updated_at = clock_timestamp()
    where public.purchase_invoice_lines.source_kind in (
      'legacy_json', 'migration'
    );
  end if;

  for v_additional_cost, v_additional_ordinal in
    select item, ordinality
    from jsonb_array_elements(
      case
        when jsonb_typeof(v_invoice.additional_costs) = 'array'
          then v_invoice.additional_costs
        else '[]'::jsonb
      end
    ) with ordinality as cost(item, ordinality)
  loop
    v_adjustment_amount := case
      when coalesce(v_additional_cost->>'amount', '')
        ~ '^-?[0-9]+([.][0-9]+)?$'
        then greatest(round((v_additional_cost->>'amount')::numeric, 2), 0)
      else 0
    end;

    if v_adjustment_amount <= 0 then
      continue;
    end if;

    v_count := v_count + 1;

    insert into public.purchase_invoice_lines (
      tenant_id,
      purchase_invoice_id,
      line_number,
      source_line_index,
      line_kind,
      adjustment_kind,
      product_id,
      line_nature,
      classification_status,
      description,
      quantity,
      unit_cost,
      discount_amount,
      net_amount,
      tax_rate,
      tax_amount,
      total_amount,
      currency_code,
      source_kind,
      source_item
    ) values (
      v_invoice.tenant_id,
      v_invoice.id,
      v_count,
      null,
      'adjustment',
      'additional_cost',
      null,
      'other',
      'needs_review',
      coalesce(
        nullif(btrim(v_additional_cost->>'label'), ''),
        'Costo adicional ' || v_additional_ordinal::text
      ),
      1,
      0,
      0,
      v_adjustment_amount,
      0,
      0,
      v_adjustment_amount,
      'CLP',
      p_source_kind,
      v_additional_cost || jsonb_build_object(
        'adjustment_kind', 'additional_cost',
        'source_additional_cost_index', v_additional_ordinal - 1
      )
    )
    on conflict (tenant_id, purchase_invoice_id, line_number)
    do update set
      source_line_index = null,
      line_kind = excluded.line_kind,
      adjustment_kind = excluded.adjustment_kind,
      product_id = null,
      line_nature = excluded.line_nature,
      classification_status = excluded.classification_status,
      description = excluded.description,
      product_name_snapshot = null,
      product_sku_snapshot = null,
      quantity = excluded.quantity,
      unit_cost = excluded.unit_cost,
      discount_amount = excluded.discount_amount,
      net_amount = excluded.net_amount,
      tax_rate = excluded.tax_rate,
      tax_amount = excluded.tax_amount,
      total_amount = excluded.total_amount,
      source_kind = excluded.source_kind,
      source_item = excluded.source_item,
      updated_at = clock_timestamp()
    where public.purchase_invoice_lines.source_kind in (
      'legacy_json', 'migration'
    );
  end loop;

  select coalesce(sum(line.total_amount), 0)::numeric(14,2)
  into v_normalized_total
  from public.purchase_invoice_lines line
  where line.tenant_id = v_invoice.tenant_id
    and line.purchase_invoice_id = v_invoice.id
    and line.source_kind in ('legacy_json', 'migration')
    and line.line_number <= v_count;

  v_reconciliation_amount := round(
    v_invoice.total::numeric - v_normalized_total,
    2
  );

  if v_reconciliation_amount <> 0 then
    v_count := v_count + 1;

    insert into public.purchase_invoice_lines (
      tenant_id,
      purchase_invoice_id,
      line_number,
      source_line_index,
      line_kind,
      adjustment_kind,
      product_id,
      line_nature,
      classification_status,
      description,
      quantity,
      unit_cost,
      discount_amount,
      net_amount,
      tax_rate,
      tax_amount,
      total_amount,
      currency_code,
      source_kind,
      source_item
    ) values (
      v_invoice.tenant_id,
      v_invoice.id,
      v_count,
      null,
      'adjustment',
      'document_reconciliation',
      null,
      'other',
      'needs_review',
      'Ajuste de conciliación al total del documento',
      1,
      0,
      0,
      v_reconciliation_amount,
      0,
      0,
      v_reconciliation_amount,
      'CLP',
      p_source_kind,
      jsonb_build_object(
        'adjustment_kind', 'document_reconciliation',
        'document_total', v_invoice.total,
        'normalized_total_before_adjustment', v_normalized_total
      )
    )
    on conflict (tenant_id, purchase_invoice_id, line_number)
    do update set
      source_line_index = null,
      line_kind = excluded.line_kind,
      adjustment_kind = excluded.adjustment_kind,
      product_id = null,
      line_nature = excluded.line_nature,
      classification_status = excluded.classification_status,
      description = excluded.description,
      product_name_snapshot = null,
      product_sku_snapshot = null,
      quantity = excluded.quantity,
      unit_cost = excluded.unit_cost,
      discount_amount = excluded.discount_amount,
      net_amount = excluded.net_amount,
      tax_rate = excluded.tax_rate,
      tax_amount = excluded.tax_amount,
      total_amount = excluded.total_amount,
      source_kind = excluded.source_kind,
      source_item = excluded.source_item,
      updated_at = clock_timestamp()
    where public.purchase_invoice_lines.source_kind in (
      'legacy_json', 'migration'
    );
  end if;

  delete from public.purchase_invoice_lines line
  where line.tenant_id = v_invoice.tenant_id
    and line.purchase_invoice_id = v_invoice.id
    and line.source_kind in ('legacy_json', 'migration')
    and line.line_number > v_count;

  return v_count;
end;
$$;

revoke all on function public.sync_purchase_invoice_lines_from_legacy_json(
  uuid, text
) from public, anon, authenticated;
grant execute on function public.sync_purchase_invoice_lines_from_legacy_json(
  uuid, text
) to service_role;

do $$
declare
  invoice_row record;
begin
  for invoice_row in
    select id from public.purchase_invoices order by id
  loop
    perform public.sync_purchase_invoice_lines_from_legacy_json(
      invoice_row.id,
      'migration'
    );
  end loop;
end
$$;

create or replace function public.sync_changed_purchase_invoice_legacy_lines()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform public.sync_purchase_invoice_lines_from_legacy_json(
    new.id,
    'legacy_json'
  );
  return new;
end;
$$;

revoke all on function public.sync_changed_purchase_invoice_legacy_lines()
  from public, anon, authenticated;

drop trigger if exists trg_sync_purchase_invoice_legacy_lines
  on public.purchase_invoices;
create trigger trg_sync_purchase_invoice_legacy_lines
  after insert or update of
    items, additional_costs, discount_amount, total, tax, tax_treatment
  on public.purchase_invoices
  for each row
  execute function public.sync_changed_purchase_invoice_legacy_lines();

-- Correct the live drift where a camelCase default cannot satisfy the current
-- snake_case CHECK. Existing rows are not rewritten.
alter table public.suppliers
  alter column default_tax_treatment set default 'no_tax';

-- ---------------------------------------------------------------------------
-- Purchase journal provenance and typed counterparty dimension
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.journal_entries'::regclass
      and conname = 'journal_entries_tenant_id_id_key'
  ) then
    alter table public.journal_entries
      add constraint journal_entries_tenant_id_id_key unique (tenant_id, id);
  end if;
end
$$;

alter table public.journal_lines
  add column if not exists counterparty_party_id uuid,
  add column if not exists counterparty_context text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.journal_lines'::regclass
      and conname = 'journal_lines_counterparty_party_fkey'
  ) then
    alter table public.journal_lines
      add constraint journal_lines_counterparty_party_fkey
      foreign key (tenant_id, counterparty_party_id)
      references public.external_parties(tenant_id, id)
      on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.journal_lines'::regclass
      and conname = 'journal_lines_counterparty_context_check'
  ) then
    alter table public.journal_lines
      add constraint journal_lines_counterparty_context_check
      check (counterparty_context is null or counterparty_context in (
        'supplier', 'landlord', 'utility', 'tax_authority',
        'service_provider', 'carrier', 'other'
      ));
  end if;
end
$$;

create index if not exists idx_journal_lines_counterparty
  on public.journal_lines(
    tenant_id, counterparty_party_id, created_at desc
  ) where counterparty_party_id is not null;

with unique_matches as (
  select
    entry.id as journal_entry_id,
    min(invoice.id::text)::uuid as purchase_invoice_id
  from public.journal_entries entry
  join public.purchase_invoices invoice
    on invoice.tenant_id = entry.tenant_id
   and (
     invoice.invoice_number = entry.source_reference
     or invoice.id::text = entry.source_reference
   )
  where entry.source_module = 'purchase_invoices'
    and entry.source_document_id is null
  group by entry.id
  having count(distinct invoice.id) = 1
)
update public.journal_entries entry
set source_document_type = 'purchase_invoice',
    source_document_id = matched.purchase_invoice_id,
    updated_at = clock_timestamp()
from unique_matches matched
where entry.id = matched.journal_entry_id;

create or replace function public.resolve_supplier_party_for_journal_source(
  p_tenant_id uuid,
  p_source_document_type text,
  p_source_document_id uuid,
  p_source_module text,
  p_source_reference text
)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_party_id uuid;
begin
  if p_source_document_type = 'purchase_invoice' then
    select supplier.party_id into v_party_id
    from public.purchase_invoices invoice
    join public.suppliers supplier
      on supplier.tenant_id = invoice.tenant_id
     and supplier.id = invoice.supplier_id
    where invoice.tenant_id = p_tenant_id
      and invoice.id = p_source_document_id;
  elsif p_source_document_type = 'expense' then
    select supplier.party_id into v_party_id
    from public.expenses expense
    join public.suppliers supplier
      on supplier.tenant_id = expense.tenant_id
     and supplier.id = expense.supplier_id
    where expense.tenant_id = p_tenant_id
      and expense.id = p_source_document_id;
  elsif p_source_document_type = 'purchase_payment' then
    select supplier.party_id into v_party_id
    from public.purchase_payments payment
    join public.purchase_invoices invoice
      on invoice.tenant_id = payment.tenant_id
     and invoice.id = payment.invoice_id
    join public.suppliers supplier
      on supplier.tenant_id = invoice.tenant_id
     and supplier.id = invoice.supplier_id
    where payment.tenant_id = p_tenant_id
      and payment.id = p_source_document_id;
  elsif p_source_document_type = 'expense_payment' then
    select supplier.party_id into v_party_id
    from public.expense_payments payment
    join public.expenses expense
      on expense.tenant_id = payment.tenant_id
     and expense.id = payment.expense_id
    join public.suppliers supplier
      on supplier.tenant_id = expense.tenant_id
     and supplier.id = expense.supplier_id
    where payment.tenant_id = p_tenant_id
      and payment.id = p_source_document_id;
  elsif p_source_document_type = 'purchase_credit_note' then
    select supplier.party_id into v_party_id
    from public.purchase_credit_notes note
    join public.purchase_invoices invoice
      on invoice.tenant_id = note.tenant_id
     and invoice.id = note.purchase_invoice_id
    join public.suppliers supplier
      on supplier.tenant_id = invoice.tenant_id
     and supplier.id = invoice.supplier_id
    where note.tenant_id = p_tenant_id
      and note.id = p_source_document_id;
  elsif p_source_document_type = 'purchase_supplier_refund' then
    select supplier.party_id into v_party_id
    from public.purchase_supplier_refunds refund
    join public.purchase_invoices invoice
      on invoice.tenant_id = refund.tenant_id
     and invoice.id = refund.purchase_invoice_id
    join public.suppliers supplier
      on supplier.tenant_id = invoice.tenant_id
     and supplier.id = invoice.supplier_id
    where refund.tenant_id = p_tenant_id
      and refund.id = p_source_document_id;
  elsif p_source_module in ('purchase_invoices', 'purchase_payments') then
    select min(supplier.party_id::text)::uuid into v_party_id
    from public.purchase_invoices invoice
    join public.suppliers supplier
      on supplier.tenant_id = invoice.tenant_id
     and supplier.id = invoice.supplier_id
    where invoice.tenant_id = p_tenant_id
      and (
        invoice.invoice_number = p_source_reference
        or invoice.id::text = p_source_reference
      )
    having count(distinct invoice.id) = 1;
  end if;

  -- Purchase credit/refund commands create their journal before the source row
  -- because that source row holds the journal FK. During that short atomic
  -- window, resolve the already server-owned operation context back to the
  -- purchase invoice. Once the source exists, the branches above remain the
  -- canonical owner.
  if v_party_id is null
     and p_source_document_type in (
       'purchase_credit_note', 'purchase_supplier_refund'
     ) then
    select min(supplier.party_id::text)::uuid
    into v_party_id
    from public.inventory_accounting_operations operation
    join public.purchase_invoices invoice
      on invoice.tenant_id = operation.tenant_id
     and invoice.id = nullif(
       operation.context ->> 'purchase_invoice_id', ''
     )::uuid
    join public.suppliers supplier
      on supplier.tenant_id = invoice.tenant_id
     and supplier.id = invoice.supplier_id
    where operation.tenant_id = p_tenant_id
      and operation.document_type = p_source_document_type
      and operation.document_id = p_source_document_id
      and operation.action = 'create'
    having count(distinct invoice.id) = 1;
  end if;

  return v_party_id;
end;
$$;

revoke all on function public.resolve_supplier_party_for_journal_source(
  uuid, text, uuid, text, text
) from public, anon, authenticated, service_role;

create or replace function public.prepare_purchase_journal_provenance()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_invoice_id uuid;
begin
  if new.source_module = 'purchase_invoices'
     and new.source_document_id is null
     and nullif(new.source_reference, '') is not null then
    select min(invoice.id::text)::uuid
    into v_invoice_id
    from public.purchase_invoices invoice
    where invoice.tenant_id = new.tenant_id
      and (
        invoice.invoice_number = new.source_reference
        or invoice.id::text = new.source_reference
      )
    having count(distinct invoice.id) = 1;

    if v_invoice_id is not null then
      new.source_document_type := 'purchase_invoice';
      new.source_document_id := v_invoice_id;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prepare_purchase_journal_provenance
  on public.journal_entries;
create trigger trg_prepare_purchase_journal_provenance
  before insert or update of
    source_module, source_reference, source_document_type, source_document_id
  on public.journal_entries
  for each row
  execute function public.prepare_purchase_journal_provenance();

create or replace function public.validate_supplier_journal_provenance()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_party_id uuid;
  v_is_supplier_source boolean := new.source_document_type in (
    'purchase_invoice', 'expense', 'purchase_payment', 'expense_payment',
    'purchase_credit_note', 'purchase_supplier_refund'
  );
begin
  v_party_id := public.resolve_supplier_party_for_journal_source(
    new.tenant_id,
    new.source_document_type,
    new.source_document_id,
    new.source_module,
    new.source_reference
  );

  if v_is_supplier_source and v_party_id is null then
    raise exception 'Canonical journal source is missing or outside tenant'
      using errcode = '23514';
  end if;

  if tg_op = 'UPDATE'
     and row(
       old.tenant_id,
       old.source_document_type,
       old.source_document_id,
       old.source_module,
       old.source_reference
     ) is distinct from row(
       new.tenant_id,
       new.source_document_type,
       new.source_document_id,
       new.source_module,
       new.source_reference
     )
     and exists (
       select 1
       from public.journal_lines line
       where line.tenant_id = old.tenant_id
         and line.entry_id = old.id
         and line.counterparty_party_id is not null
         and line.counterparty_party_id is distinct from v_party_id
     ) then
    raise exception 'Journal provenance change contradicts existing counterparty lines'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_supplier_journal_provenance()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_validate_supplier_journal_provenance
  on public.journal_entries;
create trigger trg_validate_supplier_journal_provenance
  before insert or update of
    tenant_id, source_document_type, source_document_id,
    source_module, source_reference
  on public.journal_entries
  for each row
  execute function public.validate_supplier_journal_provenance();

create or replace function public.sync_supplier_journal_counterparties()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_party_id uuid;
begin
  v_party_id := public.resolve_supplier_party_for_journal_source(
    new.tenant_id,
    new.source_document_type,
    new.source_document_id,
    new.source_module,
    new.source_reference
  );

  if v_party_id is not null then
    update public.journal_lines line
    set counterparty_party_id = v_party_id,
        counterparty_context = 'supplier',
        updated_at = clock_timestamp()
    where line.tenant_id = new.tenant_id
      and line.entry_id = new.id
      and (
        line.counterparty_party_id is distinct from v_party_id
        or line.counterparty_context is distinct from 'supplier'
      );
  end if;

  return new;
end;
$$;

revoke all on function public.sync_supplier_journal_counterparties()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_sync_supplier_journal_counterparties
  on public.journal_entries;
create trigger trg_sync_supplier_journal_counterparties
  after insert or update of
    tenant_id, source_document_type, source_document_id,
    source_module, source_reference
  on public.journal_entries
  for each row
  execute function public.sync_supplier_journal_counterparties();

create or replace function public.derive_journal_line_counterparty()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_entry public.journal_entries%rowtype;
  v_party_id uuid;
begin
  if new.entry_id is null then
    return new;
  end if;

  select entry.*
  into v_entry
  from public.journal_entries entry
  where entry.id = new.entry_id
    and entry.tenant_id = new.tenant_id;

  if not found then
    return new;
  end if;

  v_party_id := public.resolve_supplier_party_for_journal_source(
    new.tenant_id,
    v_entry.source_document_type,
    v_entry.source_document_id,
    v_entry.source_module,
    v_entry.source_reference
  );

  if v_entry.source_document_type in (
    'purchase_invoice', 'expense', 'purchase_payment', 'expense_payment',
    'purchase_credit_note', 'purchase_supplier_refund'
  ) and v_party_id is null then
    raise exception 'Canonical journal source cannot resolve supplier counterparty'
      using errcode = '23514';
  end if;

  if v_party_id is not null then
    if new.counterparty_party_id is not null
       and new.counterparty_party_id is distinct from v_party_id then
      raise exception 'Journal line counterparty contradicts canonical source'
        using errcode = '23514';
    end if;

    if new.counterparty_context is not null
       and new.counterparty_context <> 'supplier' then
      raise exception 'Journal line counterparty context contradicts canonical source'
        using errcode = '23514';
    end if;

    new.counterparty_party_id := v_party_id;
    new.counterparty_context := 'supplier';
  end if;

  return new;
end;
$$;

revoke all on function public.derive_journal_line_counterparty()
  from public, anon, authenticated;

drop trigger if exists trg_derive_journal_line_counterparty
  on public.journal_lines;
create trigger trg_derive_journal_line_counterparty
  before insert or update of
    tenant_id, entry_id, counterparty_party_id, counterparty_context
  on public.journal_lines
  for each row
  execute function public.derive_journal_line_counterparty();

update public.journal_lines line
set counterparty_party_id = supplier.party_id,
    counterparty_context = 'supplier',
    updated_at = clock_timestamp()
from public.journal_entries entry
join public.purchase_invoices invoice
  on invoice.tenant_id = entry.tenant_id
 and entry.source_document_type = 'purchase_invoice'
 and invoice.id = entry.source_document_id
join public.suppliers supplier
  on supplier.tenant_id = invoice.tenant_id
 and supplier.id = invoice.supplier_id
where line.tenant_id = entry.tenant_id
  and line.entry_id = entry.id
  and line.counterparty_party_id is null
  and supplier.party_id is not null;

update public.journal_lines line
set counterparty_party_id = supplier.party_id,
    counterparty_context = 'supplier',
    updated_at = clock_timestamp()
from public.journal_entries entry
join public.expenses expense
  on expense.tenant_id = entry.tenant_id
 and entry.source_document_type = 'expense'
 and expense.id = entry.source_document_id
join public.suppliers supplier
  on supplier.tenant_id = expense.tenant_id
 and supplier.id = expense.supplier_id
where line.tenant_id = entry.tenant_id
  and line.entry_id = entry.id
  and line.counterparty_party_id is null
  and supplier.party_id is not null;

with legacy_payment_parties as (
  select
    entry.id as journal_entry_id,
    min(supplier.party_id::text)::uuid as party_id
  from public.journal_entries entry
  join public.purchase_invoices invoice
    on invoice.tenant_id = entry.tenant_id
   and (
     invoice.invoice_number = entry.source_reference
     or invoice.id::text = entry.source_reference
   )
  join public.suppliers supplier
    on supplier.tenant_id = invoice.tenant_id
   and supplier.id = invoice.supplier_id
  where entry.source_module = 'purchase_payments'
    and supplier.party_id is not null
  group by entry.id
  having count(distinct invoice.id) = 1
)
update public.journal_lines line
set counterparty_party_id = legacy.party_id,
    counterparty_context = 'supplier',
    updated_at = clock_timestamp()
from legacy_payment_parties legacy
where line.entry_id = legacy.journal_entry_id
  and line.counterparty_party_id is null;

create table if not exists public.supplier_data_quality_candidates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  issue_code text not null check (issue_code in (
    'legacy_portal_origin_not_canonical'
  )),
  severity text not null default 'warning'
    check (severity in ('info', 'warning', 'error')),
  scope_type text not null default 'supplier'
    check (scope_type in (
      'supplier', 'identity', 'engagement', 'accounting_policy',
      'credential', 'tax_document'
    )),
  scope_id uuid,
  related_code text,
  field_key text,
  display_reason text not null
    check (btrim(display_reason) <> ''),
  issue_source text not null
    check (issue_source in (
      'migration_validation', 'domain_validation', 'integration_validation'
    )),
  status text not null default 'pending'
    check (status in ('pending', 'resolved', 'dismissed')),
  metadata jsonb not null default '{}'::jsonb
    check (
      jsonb_typeof(metadata) = 'object'
      and not public.jsonb_contains_sensitive_key(metadata)
    ),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, supplier_id, issue_code),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade
);

comment on table public.supplier_data_quality_candidates is
  'Secret-free review queue for migration facts that cannot be promoted safely. Raw legacy credential URLs are never copied into this table.';

create table if not exists public.supplier_profile_command_receipts (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_id uuid not null,
  supplier_id uuid not null,
  request_fingerprint text not null check (btrim(request_fingerprint) <> ''),
  applied_at timestamptz not null default clock_timestamp(),
  primary key (tenant_id, operation_id),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade
);

comment on table public.supplier_profile_command_receipts is
  'Server-owned idempotency receipts for atomic identity, relationship, and assignment saves. It contains no user payload or secret material.';

create table if not exists public.supplier_ocr_template_command_receipts (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_id uuid not null,
  supplier_id uuid not null,
  request_fingerprint text not null check (btrim(request_fingerprint) <> ''),
  result jsonb not null check (
    jsonb_typeof(result) = 'object'
    and not public.jsonb_contains_sensitive_key(result)
  ),
  actor_id uuid references auth.users(id) on delete set null,
  applied_at timestamptz not null default clock_timestamp(),
  primary key (tenant_id, operation_id),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade
);

comment on table public.supplier_ocr_template_command_receipts is
  'Private idempotency receipts for the narrow supplier OCR-template command. Results contain only canonical non-sensitive template state.';

do $$
declare
  target record;
  constraint_name text;
begin
  for target in
    select *
    from (values
      ('external_parties', 'metadata'),
      ('external_party_identifiers', 'metadata'),
      ('business_sites', 'metadata'),
      ('supplier_role_definitions', 'metadata'),
      ('supplier_capability_definitions', 'metadata'),
      ('supplier_tag_definitions', 'metadata'),
      ('operational_nature_definitions', 'metadata'),
      ('supplier_relationship_roles', 'metadata'),
      ('supplier_relationship_capabilities', 'metadata'),
      ('supplier_relationship_tags', 'metadata'),
      ('supplier_engagements', 'metadata'),
      ('supplier_engagement_versions', 'terms'),
      ('supplier_accounting_policy_versions', 'posture'),
      ('supplier_accounting_rules', 'operand'),
      ('supplier_accounting_evidence', 'evidence'),
      ('supplier_classification_candidates', 'metadata'),
      ('received_tax_documents', 'metadata'),
      ('purchase_invoice_lines', 'source_item')
    ) as targets(table_name, column_name)
  loop
    constraint_name := substr(target.table_name, 1, 35) || '_' ||
      target.column_name || '_safe_' ||
      substr(md5(target.table_name || '.' || target.column_name), 1, 8);

    if not exists (
      select 1
      from pg_constraint constraint_row
      where constraint_row.conrelid =
        format('public.%I', target.table_name)::regclass
        and constraint_row.conname = constraint_name
    ) then
      execute format(
        'alter table public.%I add constraint %I check (not public.jsonb_contains_sensitive_key(%I))',
        target.table_name,
        constraint_name,
        target.column_name
      );
    end if;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- Supplier credentials: Vault-backed, explicit permission, copy-first cutover
-- ---------------------------------------------------------------------------

do $$
begin
  if to_regclass('vault.secrets') is null then
    raise exception 'Supabase Vault is required for supplier credentials';
  end if;
end
$$;

create table if not exists public.supplier_credentials (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  credential_kind text not null check (credential_kind in (
    'portal_password', 'api_token', 'other'
  )),
  credential_key text not null default 'default'
    check (credential_key ~ '^[a-z][a-z0-9_.-]*$'),
  engagement_id uuid,
  origin_url text check (
    origin_url is null or (
      public.canonical_https_origin(origin_url) is not null
      and origin_url = public.canonical_https_origin(origin_url)
    )
  ),
  label text,
  username text,
  vault_secret_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, supplier_id, credential_kind, credential_key),
  unique (vault_secret_id),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade,
  foreign key (tenant_id, engagement_id, supplier_id)
    references public.supplier_engagements(tenant_id, id, supplier_id)
    on delete set null (engagement_id)
);

create table if not exists public.supplier_credential_command_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_id uuid not null,
  supplier_id uuid not null,
  credential_kind text not null check (credential_kind in (
    'portal_password', 'api_token', 'other'
  )),
  credential_key text not null
    check (credential_key ~ '^[a-z][a-z0-9_.-]*$'),
  command_kind text not null check (command_kind in ('upsert', 'delete')),
  request_fingerprint text not null check (btrim(request_fingerprint) <> ''),
  expected_updated_at timestamptz,
  credential_id uuid,
  result jsonb not null check (jsonb_typeof(result) = 'object'),
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_id),
  unique (tenant_id, id)
);

comment on table public.supplier_credential_command_receipts is
  'Private idempotency receipts for credential writes. Delete receipts are durable tombstones; result and fingerprint never contain the secret.';

create table if not exists public.supplier_credential_access_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  credential_id uuid,
  credential_kind text not null check (credential_kind in (
    'portal_password', 'api_token', 'other'
  )),
  credential_key text not null default 'default'
    check (credential_key ~ '^[a-z][a-z0-9_.-]*$'),
  action text not null check (action in (
    'create', 'rotate', 'reveal', 'delete'
  )),
  actor_id uuid references auth.users(id) on delete set null,
  occurred_at timestamptz not null default clock_timestamp(),
  metadata jsonb not null default '{}'::jsonb
    check (
      jsonb_typeof(metadata) = 'object'
      and not public.jsonb_contains_sensitive_key(metadata)
    ),
  unique (tenant_id, id),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete restrict
);

comment on column public.supplier_credential_access_events.credential_id is
  'Audit snapshot only, intentionally not a foreign key so delete evidence outlives credential metadata.';
comment on column public.supplier_credential_access_events.metadata is
  'Operational audit context only. Secrets, usernames, and decrypted Vault values are prohibited.';
create index if not exists idx_supplier_credential_events_supplier_time
  on public.supplier_credential_access_events(
    tenant_id, supplier_id, occurred_at desc
  );

comment on table public.supplier_credentials is
  'Non-secret metadata pointing to Supabase Vault. No client role has direct table access; all secret operations require explicit tenant-scoped authority.';
comment on column public.suppliers.portal_password is
  'LEGACY COPY ONLY after 20260808210000. A second cutover migration must clear this column only after every supported client reads supplier credentials through the Vault RPCs and copy/readback coverage is complete.';

create or replace function public.refresh_supplier_portal_origin_issue(
  p_tenant_id uuid,
  p_supplier_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_website text;
  v_credential_exists boolean;
  v_origin_url text;
  v_requires_review boolean;
begin
  select supplier.website
  into v_website
  from public.suppliers supplier
  where supplier.tenant_id = p_tenant_id
    and supplier.id = p_supplier_id;

  if not found then
    return;
  end if;

  select true, credential.origin_url
  into v_credential_exists, v_origin_url
  from public.supplier_credentials credential
  where credential.tenant_id = p_tenant_id
    and credential.supplier_id = p_supplier_id
    and credential.credential_kind = 'portal_password'
    and credential.credential_key = 'default';

  v_requires_review := coalesce(v_credential_exists, false)
    and v_origin_url is null
    and nullif(btrim(v_website), '') is not null
    and public.canonical_https_origin(v_website) is null;

  if v_requires_review then
    insert into public.supplier_data_quality_candidates (
      tenant_id,
      supplier_id,
      issue_code,
      scope_type,
      scope_id,
      related_code,
      field_key,
      display_reason,
      issue_source,
      status,
      metadata
    ) values (
      p_tenant_id,
      p_supplier_id,
      'legacy_portal_origin_not_canonical',
      'credential',
      p_supplier_id,
      'portal_password/default',
      'origin_url',
      'El origen del portal legado requiere revision antes de asociar credenciales.',
      'domain_validation',
      'pending',
      jsonb_build_object(
        'source', 'suppliers.website',
        'reason', 'not_an_exact_https_origin'
      )
    ) on conflict (tenant_id, supplier_id, issue_code) do update
    set status = 'pending',
        display_reason = excluded.display_reason,
        issue_source = excluded.issue_source,
        metadata = excluded.metadata,
        updated_at = clock_timestamp();
  else
    update public.supplier_data_quality_candidates candidate
    set status = 'resolved',
        updated_at = clock_timestamp()
    where candidate.tenant_id = p_tenant_id
      and candidate.supplier_id = p_supplier_id
      and candidate.issue_code = 'legacy_portal_origin_not_canonical'
      and candidate.status = 'pending';
  end if;
end;
$$;

revoke all on function public.refresh_supplier_portal_origin_issue(uuid, uuid)
  from public, anon, authenticated, service_role;

alter table public.supplier_credentials enable row level security;
alter table public.supplier_credential_command_receipts enable row level security;
alter table public.supplier_credential_access_events enable row level security;
revoke all on table public.supplier_credentials
  from public, anon, authenticated;
revoke all on table public.supplier_credential_command_receipts
  from public, anon, authenticated;
revoke all on table public.supplier_credential_access_events
  from public, anon, authenticated;
revoke all on table vault.secrets from anon, authenticated;
revoke all on table vault.decrypted_secrets from anon, authenticated;

create or replace function public.backfill_supplier_credentials_to_vault()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  supplier_row record;
  v_secret_name text;
  v_secret_id uuid;
  v_count integer := 0;
  v_inserted integer := 0;
  v_credential_id uuid;
begin
  for supplier_row in
    select
      supplier.id,
      supplier.tenant_id,
      supplier.portal_username,
      supplier.portal_password,
      supplier.website
    from public.suppliers supplier
    where supplier.tenant_id is not null
      and nullif(supplier.portal_password, '') is not null
      and not exists (
        select 1
        from public.supplier_credentials credential
        where credential.tenant_id = supplier.tenant_id
          and credential.supplier_id = supplier.id
          and credential.credential_kind = 'portal_password'
          and credential.credential_key = 'default'
      )
    order by supplier.id
  loop
    if nullif(btrim(supplier_row.website), '') is not null
       and public.canonical_https_origin(supplier_row.website) is null then
      insert into public.supplier_data_quality_candidates (
        tenant_id,
        supplier_id,
        issue_code,
        scope_type,
        scope_id,
        related_code,
        field_key,
        display_reason,
        issue_source,
        metadata
      ) values (
        supplier_row.tenant_id,
        supplier_row.id,
        'legacy_portal_origin_not_canonical',
        'credential',
        supplier_row.id,
        'portal_password/default',
        'origin_url',
        'El origen del portal legado requiere revisión antes de asociar credenciales.',
        'migration_validation',
        jsonb_build_object(
          'source', 'suppliers.website',
          'reason', 'not_an_exact_https_origin'
        )
      ) on conflict (tenant_id, supplier_id, issue_code) do nothing;
    end if;

    v_secret_name :=
      'supplier_portal_password_' || supplier_row.id::text;

    select secret.id
    into v_secret_id
    from vault.secrets secret
    where secret.name = v_secret_name
    limit 1;

    if v_secret_id is null then
      v_secret_id := vault.create_secret(
        supplier_row.portal_password,
        v_secret_name,
        'Supplier portal password copied from legacy supplier ' ||
          supplier_row.id::text
      );
    else
      perform vault.update_secret(
        v_secret_id,
        supplier_row.portal_password,
        v_secret_name,
        'Supplier portal password copied from legacy supplier ' ||
          supplier_row.id::text
      );
    end if;

    insert into public.supplier_credentials (
      tenant_id,
      supplier_id,
      credential_kind,
      credential_key,
      origin_url,
      label,
      username,
      vault_secret_id
    ) values (
      supplier_row.tenant_id,
      supplier_row.id,
      'portal_password',
      'default',
      public.canonical_https_origin(supplier_row.website),
      'Portal principal',
      nullif(btrim(supplier_row.portal_username), ''),
      v_secret_id
    )
    on conflict (
      tenant_id, supplier_id, credential_kind, credential_key
    )
    do nothing
    returning id into v_credential_id;

    get diagnostics v_inserted = row_count;

    if v_inserted = 1 then
      insert into public.supplier_credential_access_events (
        tenant_id,
        supplier_id,
        credential_id,
        credential_kind,
        credential_key,
        action,
        actor_id,
        metadata
      ) values (
        supplier_row.tenant_id,
        supplier_row.id,
        v_credential_id,
        'portal_password',
        'default',
        'create',
        null,
        jsonb_build_object('source', 'legacy_copy_first_migration')
      );
    end if;

    perform public.refresh_supplier_portal_origin_issue(
      supplier_row.tenant_id,
      supplier_row.id
    );

    v_count := v_count + v_inserted;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.backfill_supplier_credentials_to_vault()
  from public, anon, authenticated;
grant execute on function public.backfill_supplier_credentials_to_vault()
  to service_role;

select public.backfill_supplier_credentials_to_vault();

create or replace function public.sync_legacy_supplier_portal_credential()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_guard text := coalesce(
    current_setting('app.supplier_credential_sync_guard', true),
    ''
  );
  v_expected_guard text := txid_current()::text || ':' || new.id::text;
  v_credential public.supplier_credentials%rowtype;
  v_secret_id uuid;
  v_secret_name text := 'supplier_portal_password_' || new.id::text;
  v_action text;
begin
  if v_guard = v_expected_guard then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.portal_password is not distinct from old.portal_password
     and new.portal_username is not distinct from old.portal_username then
    return new;
  end if;

  if tg_op = 'INSERT'
     and nullif(new.portal_password, '') is null
     and nullif(btrim(new.portal_username), '') is null then
    return new;
  end if;

  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(new.tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  if nullif(btrim(new.website), '') is not null
     and public.canonical_https_origin(new.website) is null then
    insert into public.supplier_data_quality_candidates (
      tenant_id,
      supplier_id,
      issue_code,
      scope_type,
      scope_id,
      related_code,
      field_key,
      display_reason,
      issue_source,
      metadata
    ) values (
      new.tenant_id,
      new.id,
      'legacy_portal_origin_not_canonical',
      'credential',
      new.id,
      'portal_password/default',
      'origin_url',
      'El origen del portal legado requiere revisión antes de asociar credenciales.',
      'domain_validation',
      jsonb_build_object(
        'source', 'suppliers.website',
        'reason', 'not_an_exact_https_origin'
      )
    ) on conflict (tenant_id, supplier_id, issue_code) do nothing;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_credential:' || new.tenant_id::text || ':' ||
      new.id::text || ':portal_password:default',
      0
    )
  );

  select credential.*
  into v_credential
  from public.supplier_credentials credential
  where credential.tenant_id = new.tenant_id
    and credential.supplier_id = new.id
    and credential.credential_kind = 'portal_password'
    and credential.credential_key = 'default'
  for update;

  if nullif(new.portal_password, '') is null then
    if found then
      delete from public.supplier_credentials credential
      where credential.id = v_credential.id;

      delete from vault.secrets secret
      where secret.id = v_credential.vault_secret_id;

      insert into public.supplier_credential_access_events (
        tenant_id,
        supplier_id,
        credential_id,
        credential_kind,
        credential_key,
        action,
        actor_id,
        metadata
      ) values (
        new.tenant_id,
        new.id,
        v_credential.id,
        'portal_password',
        'default',
        'delete',
        case when v_role = 'service_role' then null else auth.uid() end,
        jsonb_build_object(
          'source', case when v_role = 'service_role'
            then 'service_role_legacy_supplier_write'
            else 'legacy_supplier_write' end
        )
      );
    end if;

    return new;
  end if;

  if found then
    v_action := 'rotate';
    v_secret_id := v_credential.vault_secret_id;
    perform vault.update_secret(
      v_secret_id,
      new.portal_password,
      v_secret_name,
      'Supplier portal credential synchronized from legacy supplier ' ||
        new.id::text
    );

    update public.supplier_credentials credential
    set username = nullif(btrim(new.portal_username), ''),
        updated_at = clock_timestamp()
    where credential.id = v_credential.id;
  else
    v_action := 'create';

    select secret.id
    into v_secret_id
    from vault.secrets secret
    where secret.name = v_secret_name
    limit 1;

    if v_secret_id is null then
      v_secret_id := vault.create_secret(
        new.portal_password,
        v_secret_name,
        'Supplier portal credential synchronized from legacy supplier ' ||
          new.id::text
      );
    else
      perform vault.update_secret(
        v_secret_id,
        new.portal_password,
        v_secret_name,
        'Supplier portal credential synchronized from legacy supplier ' ||
          new.id::text
      );
    end if;

    insert into public.supplier_credentials (
      tenant_id,
      supplier_id,
      credential_kind,
      credential_key,
      origin_url,
      label,
      username,
      vault_secret_id
    ) values (
      new.tenant_id,
      new.id,
      'portal_password',
      'default',
      public.canonical_https_origin(new.website),
      'Portal principal',
      nullif(btrim(new.portal_username), ''),
      v_secret_id
    )
    returning * into v_credential;
  end if;

  insert into public.supplier_credential_access_events (
    tenant_id,
    supplier_id,
    credential_id,
    credential_kind,
    credential_key,
    action,
    actor_id,
    metadata
  ) values (
    new.tenant_id,
    new.id,
    v_credential.id,
    'portal_password',
    'default',
    v_action,
    case when v_role = 'service_role' then null else auth.uid() end,
    jsonb_build_object(
      'source', case when v_role = 'service_role'
        then 'service_role_legacy_supplier_write'
        else 'legacy_supplier_write' end
    )
  );

  return new;
end;
$$;

revoke all on function public.sync_legacy_supplier_portal_credential()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_supplier_legacy_portal_credential_sync
  on public.suppliers;
create trigger trg_supplier_legacy_portal_credential_sync
  after update of portal_password, portal_username
  on public.suppliers
  for each row
  when (
    old.portal_password is distinct from new.portal_password
    or old.portal_username is distinct from new.portal_username
  )
  execute function public.sync_legacy_supplier_portal_credential();

drop trigger if exists trg_supplier_legacy_portal_credential_insert_sync
  on public.suppliers;
create trigger trg_supplier_legacy_portal_credential_insert_sync
  after insert
  on public.suppliers
  for each row
  when (
    nullif(new.portal_password, '') is not null
    or nullif(btrim(new.portal_username), '') is not null
  )
  execute function public.sync_legacy_supplier_portal_credential();

-- Obsolete clients cannot supply a durable operation id. Give each actual
-- wrapper invocation a fresh generation and let optimistic concurrency fail a
-- race, rather than replaying a historical A/B/A payload receipt.
create or replace function public.upsert_supplier_credential(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_credential_kind text,
  p_label text,
  p_username text,
  p_secret text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_kind text := lower(btrim(coalesce(p_credential_kind, '')));
  v_credential public.supplier_credentials%rowtype;
  v_secret_id uuid;
  v_secret_name text;
  v_action text;
begin
  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(p_tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  if v_kind not in ('portal_password', 'api_token', 'other')
     or nullif(p_secret, '') is null then
    raise exception 'Valid credential kind and non-empty secret are required'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.suppliers supplier
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id
  ) then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_credential:' || p_tenant_id::text || ':' ||
      p_supplier_id::text || ':' || v_kind || ':default',
      0
    )
  );

  select credential.*
  into v_credential
  from public.supplier_credentials credential
  where credential.tenant_id = p_tenant_id
    and credential.supplier_id = p_supplier_id
    and credential.credential_kind = v_kind
    and credential.credential_key = 'default'
  for update;

  v_secret_name :=
    'supplier_' || v_kind || '_' || p_supplier_id::text;

  if found then
    v_action := 'rotate';
    perform vault.update_secret(
      v_credential.vault_secret_id,
      p_secret,
      v_secret_name,
      'Supplier credential ' || v_kind || ' for ' || p_supplier_id::text
    );
    v_secret_id := v_credential.vault_secret_id;

    update public.supplier_credentials
    set label = nullif(btrim(p_label), ''),
        username = nullif(btrim(p_username), ''),
        updated_at = clock_timestamp()
    where id = v_credential.id;
  else
    v_action := 'create';
    select secret.id
    into v_secret_id
    from vault.secrets secret
    where secret.name = v_secret_name
    limit 1;

    if v_secret_id is null then
      v_secret_id := vault.create_secret(
        p_secret,
        v_secret_name,
        'Supplier credential ' || v_kind || ' for ' || p_supplier_id::text
      );
    else
      perform vault.update_secret(
        v_secret_id,
        p_secret,
        v_secret_name,
        'Supplier credential ' || v_kind || ' for ' || p_supplier_id::text
      );
    end if;

    insert into public.supplier_credentials (
      tenant_id,
      supplier_id,
      credential_kind,
      credential_key,
      label,
      username,
      vault_secret_id
    ) values (
      p_tenant_id,
      p_supplier_id,
      v_kind,
      'default',
      nullif(btrim(p_label), ''),
      nullif(btrim(p_username), ''),
      v_secret_id
    ) returning * into v_credential;
  end if;

  insert into public.supplier_credential_access_events (
    tenant_id,
    supplier_id,
    credential_id,
    credential_kind,
    credential_key,
    action,
    actor_id,
    metadata
  ) values (
    p_tenant_id,
    p_supplier_id,
    v_credential.id,
    v_kind,
    'default',
    v_action,
    case when v_role = 'service_role' then null else auth.uid() end,
    jsonb_build_object(
      'source', case when v_role = 'service_role'
        then 'service_role' else 'authorized_user' end
    )
  );

  if v_kind = 'portal_password' then
    perform set_config(
      'app.supplier_credential_sync_guard',
      txid_current()::text || ':' || p_supplier_id::text,
      true
    );
    update public.suppliers supplier
    set portal_username = nullif(btrim(p_username), ''),
        portal_password = p_secret,
        updated_at = clock_timestamp()
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id;
    perform set_config('app.supplier_credential_sync_guard', '', true);
  end if;

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'supplier_id', p_supplier_id,
    'credential_kind', v_kind,
    'credential_key', 'default',
    'label', nullif(btrim(p_label), ''),
    'username', nullif(btrim(p_username), ''),
    'credential_stored', true
  );
end;
$$;

create or replace function public.get_supplier_credential(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_credential_kind text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_kind text := lower(btrim(coalesce(p_credential_kind, '')));
  v_result jsonb;
  v_credential_id uuid;
begin
  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(p_tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'tenant_id', credential.tenant_id,
    'supplier_id', credential.supplier_id,
    'credential_kind', credential.credential_kind,
    'label', credential.label,
    'credential_key', credential.credential_key,
    'engagement_id', credential.engagement_id,
    'origin_url', credential.origin_url,
    'username', credential.username,
    'secret', secret.decrypted_secret,
    'updated_at', credential.updated_at
  ), credential.id
  into v_result, v_credential_id
  from public.supplier_credentials credential
  join vault.decrypted_secrets secret
    on secret.id = credential.vault_secret_id
  where credential.tenant_id = p_tenant_id
    and credential.supplier_id = p_supplier_id
    and credential.credential_kind = v_kind
    and credential.credential_key = 'default'
    and nullif(secret.decrypted_secret, '') is not null;

  if v_result is null then
    raise exception 'Supplier credential not found' using errcode = 'P0002';
  end if;

  insert into public.supplier_credential_access_events (
    tenant_id,
    supplier_id,
    credential_id,
    credential_kind,
    credential_key,
    action,
    actor_id,
    metadata
  ) values (
    p_tenant_id,
    p_supplier_id,
    v_credential_id,
    v_kind,
    'default',
    'reveal',
    case when v_role = 'service_role' then null else auth.uid() end,
    jsonb_build_object(
      'source', case when v_role = 'service_role'
        then 'service_role' else 'authorized_user' end
    )
  );

  return v_result;
end;
$$;

create or replace function public.delete_supplier_credential(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_credential_kind text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_kind text := lower(btrim(coalesce(p_credential_kind, '')));
  v_secret_id uuid;
  v_credential_id uuid;
begin
  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(p_tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  delete from public.supplier_credentials credential
  where credential.tenant_id = p_tenant_id
    and credential.supplier_id = p_supplier_id
    and credential.credential_kind = v_kind
    and credential.credential_key = 'default'
  returning credential.id, credential.vault_secret_id
  into v_credential_id, v_secret_id;

  if v_secret_id is null then
    return false;
  end if;

  delete from vault.secrets secret where secret.id = v_secret_id;

  insert into public.supplier_credential_access_events (
    tenant_id,
    supplier_id,
    credential_id,
    credential_kind,
    credential_key,
    action,
    actor_id,
    metadata
  ) values (
    p_tenant_id,
    p_supplier_id,
    v_credential_id,
    v_kind,
    'default',
    'delete',
    case when v_role = 'service_role' then null else auth.uid() end,
    jsonb_build_object(
      'source', case when v_role = 'service_role'
        then 'service_role' else 'authorized_user' end
    )
  );

  if v_kind = 'portal_password' then
    perform set_config(
      'app.supplier_credential_sync_guard',
      txid_current()::text || ':' || p_supplier_id::text,
      true
    );
    update public.suppliers supplier
    set portal_username = null,
        portal_password = null,
        updated_at = clock_timestamp()
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id;
    perform set_config('app.supplier_credential_sync_guard', '', true);
  end if;

  return true;
end;
$$;

create or replace function public.get_supplier_credential_status(
  p_tenant_id uuid,
  p_supplier_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_credentials jsonb;
begin
  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(p_tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.suppliers supplier
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id
  ) then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'credential_kind', credential.credential_kind,
        'credential_key', credential.credential_key,
        'engagement_id', credential.engagement_id,
        'origin_url', credential.origin_url,
        'label', credential.label,
        'username', credential.username,
        'updated_at', credential.updated_at
      ) order by credential.credential_kind, credential.credential_key,
        credential.id
    ),
    '[]'::jsonb
  )
  into v_credentials
  from public.supplier_credentials credential
  where credential.tenant_id = p_tenant_id
    and credential.supplier_id = p_supplier_id;

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'supplier_id', p_supplier_id,
    'has_portal_credential', exists (
      select 1
      from public.supplier_credentials credential
      where credential.tenant_id = p_tenant_id
        and credential.supplier_id = p_supplier_id
        and credential.credential_kind = 'portal_password'
    ),
    'credentials', v_credentials
  );
end;
$$;

create or replace function public.find_supplier_credential_for_origin(
  p_tenant_id uuid,
  p_origin_url text,
  p_credential_kind text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_origin_input text := nullif(btrim(p_origin_url), '');
  v_origin_url text := public.canonical_https_origin(v_origin_input);
  v_kind text := nullif(lower(btrim(p_credential_kind)), '');
  v_match_count integer;
  v_candidates jsonb;
  v_match jsonb;
  v_business_date date;
begin
  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(p_tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  if v_origin_input is null or v_origin_url is null then
    raise exception 'An exact canonical HTTPS origin is required'
      using errcode = '22023';
  end if;

  if v_kind is not null
     and v_kind not in ('portal_password', 'api_token', 'other') then
    raise exception 'Unsupported supplier credential kind'
      using errcode = '22023';
  end if;

  v_business_date := public.tenant_business_date(p_tenant_id);

  select
    count(*)::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'supplier_id', credential.supplier_id,
          'credential_kind', credential.credential_kind,
          'credential_key', credential.credential_key,
          'engagement_id', credential.engagement_id,
          'origin_url', credential.origin_url,
          'label', credential.label,
          'updated_at', credential.updated_at
        ) order by credential.supplier_id, credential.credential_kind,
          credential.credential_key, credential.id
      ),
      '[]'::jsonb
    )
  into v_match_count, v_candidates
  from public.supplier_credentials credential
  join public.suppliers supplier
    on supplier.tenant_id = credential.tenant_id
   and supplier.id = credential.supplier_id
   and supplier.is_active is true
  where credential.tenant_id = p_tenant_id
    and credential.origin_url = v_origin_url
    and (v_kind is null or credential.credential_kind = v_kind)
    and (
      credential.engagement_id is null
      or exists (
        select 1
        from public.supplier_engagements engagement
        join public.supplier_engagement_versions version
          on version.tenant_id = engagement.tenant_id
         and version.engagement_id = engagement.id
         and version.effective_from <= v_business_date
         and (
           version.effective_to is null
           or version.effective_to >= v_business_date
         )
        where engagement.tenant_id = credential.tenant_id
          and engagement.id = credential.engagement_id
          and engagement.supplier_id = credential.supplier_id
          and engagement.status = 'active'
          and (
            engagement.starts_on is null
            or engagement.starts_on <= v_business_date
          )
          and (
            engagement.ends_on is null
            or engagement.ends_on >= v_business_date
          )
      )
    );

  if v_match_count = 1 then
    v_match := v_candidates -> 0;
  end if;

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'effective_business_date', v_business_date,
    'canonical_origin', v_origin_url,
    'credential_kind', v_kind,
    'match_status', case
      when v_match_count = 0 then 'no_match'
      when v_match_count = 1 then 'unique'
      else 'ambiguous'
    end,
    'match_count', v_match_count,
    'match', v_match,
    'candidates', v_candidates
  );
end;
$$;

comment on function public.find_supplier_credential_for_origin(
  uuid, text, text
) is
  'Permission-gated metadata lookup for an exact canonical HTTPS origin. It uses and publishes the tenant effective business date for engagement validity, never reads Vault, never returns a secret or username, and only publishes match when the tenant-scoped result is unique.';

create or replace function public.upsert_supplier_credential_v2(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_credential_kind text,
  p_credential_key text,
  p_operation_id uuid,
  p_expected_updated_at timestamptz,
  p_engagement_id uuid,
  p_origin_url text,
  p_label text,
  p_username text,
  p_secret text,
  p_clear_engagement boolean,
  p_clear_origin boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_kind text := lower(btrim(coalesce(p_credential_kind, '')));
  v_key text := lower(btrim(coalesce(p_credential_key, 'default')));
  v_origin_input text := nullif(btrim(p_origin_url), '');
  v_origin_url text := public.canonical_https_origin(v_origin_input);
  v_credential public.supplier_credentials%rowtype;
  v_receipt public.supplier_credential_command_receipts%rowtype;
  v_secret_id uuid;
  v_secret_name text;
  v_action text;
  v_request_fingerprint text;
  v_applied jsonb;
  v_current jsonb;
  v_result jsonb;
  v_current_secret text;
begin
  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(p_tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  if v_kind not in ('portal_password', 'api_token', 'other')
     or v_key !~ '^[a-z][a-z0-9_.-]*$'
     or p_operation_id is null
     or nullif(p_secret, '') is null
     or (v_origin_input is not null and v_origin_url is null)
     or (coalesce(p_clear_engagement, false)
       and p_engagement_id is not null)
     or (coalesce(p_clear_origin, false) and v_origin_input is not null) then
    raise exception 'Valid credential kind, key, operation id, HTTPS origin, and secret are required'
      using errcode = '22023';
  end if;

  v_request_fingerprint := encode(extensions.digest(
    jsonb_build_object(
      'supplier_id', p_supplier_id,
      'credential_kind', v_kind,
      'credential_key', v_key,
      'expected_updated_at', p_expected_updated_at,
      'engagement_id', p_engagement_id,
      'origin_url', v_origin_url,
      'label', nullif(btrim(p_label), ''),
      'username', nullif(btrim(p_username), ''),
      'secret_digest', encode(extensions.digest(p_secret, 'sha256'), 'hex'),
      'clear_engagement', coalesce(p_clear_engagement, false),
      'clear_origin', coalesce(p_clear_origin, false)
    )::text,
    'sha256'
  ), 'hex');

  -- Every credential writer, including receipt replay repair, owns the
  -- supplier shell before it can lock or read credential state.
  perform 1
    from public.suppliers supplier
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id
    for update;

  if not found then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_credential_operation:' || p_tenant_id::text || ':' ||
      p_operation_id::text,
      0
    )
  );

  select receipt.*
  into v_receipt
  from public.supplier_credential_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.operation_id = p_operation_id;

  if found then
    if v_receipt.command_kind <> 'upsert'
       or v_receipt.request_fingerprint <> v_request_fingerprint then
      raise exception 'Supplier credential operation id was reused with different content'
        using errcode = '23505';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(
      'supplier_credential:' || p_tenant_id::text || ':' ||
      p_supplier_id::text || ':' || v_kind || ':' || v_key,
      0
    ));

    select credential.*
    into v_credential
    from public.supplier_credentials credential
    where credential.tenant_id = p_tenant_id
      and credential.supplier_id = p_supplier_id
      and credential.credential_kind = v_kind
      and credential.credential_key = v_key
    for update;

    if found then
      v_current := jsonb_build_object(
        'tenant_id', v_credential.tenant_id,
        'supplier_id', v_credential.supplier_id,
        'credential_kind', v_credential.credential_kind,
        'credential_key', v_credential.credential_key,
        'engagement_id', v_credential.engagement_id,
        'origin_url', v_credential.origin_url,
        'label', v_credential.label,
        'username', v_credential.username,
        'updated_at', v_credential.updated_at
      );
    else
      v_current := null;
    end if;

    if v_kind = 'portal_password'
       and v_key = 'default'
       and v_credential.id is not null then
      select secret.decrypted_secret
      into v_current_secret
      from vault.decrypted_secrets secret
      where secret.id = v_credential.vault_secret_id;

      if nullif(v_current_secret, '') is not null then
        perform set_config(
          'app.supplier_credential_sync_guard',
          txid_current()::text || ':' || p_supplier_id::text,
          true
        );
        update public.suppliers supplier
        set portal_username = v_current->>'username',
            portal_password = v_current_secret,
            updated_at = clock_timestamp()
        where supplier.tenant_id = p_tenant_id
          and supplier.id = p_supplier_id
          and (
            supplier.portal_username is distinct from v_current->>'username'
            or supplier.portal_password is distinct from v_current_secret
          );
        perform set_config('app.supplier_credential_sync_guard', '', true);
      end if;

      perform public.refresh_supplier_portal_origin_issue(
        p_tenant_id,
        p_supplier_id
      );
    end if;

    return v_receipt.result || jsonb_build_object(
      'idempotent_replay', true,
      'current_credential', to_jsonb(v_current)
    );
  end if;

  if p_engagement_id is not null and not exists (
    select 1 from public.supplier_engagements engagement
    where engagement.tenant_id = p_tenant_id
      and engagement.id = p_engagement_id
      and engagement.supplier_id = p_supplier_id
  ) then
    raise exception 'Credential engagement does not belong to supplier'
      using errcode = '23514';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_credential:' || p_tenant_id::text || ':' ||
      p_supplier_id::text || ':' || v_kind || ':' || v_key,
      0
    )
  );

  select credential.*
  into v_credential
  from public.supplier_credentials credential
  where credential.tenant_id = p_tenant_id
    and credential.supplier_id = p_supplier_id
    and credential.credential_kind = v_kind
    and credential.credential_key = v_key
  for update;

  v_secret_name := 'supplier_' || v_kind || '_' ||
    p_supplier_id::text || case when v_key = 'default'
      then '' else '_' || v_key end;

  if found then
    if p_expected_updated_at is null then
      raise exception 'Expected credential updated_at is required for rotation'
        using errcode = '22023';
    end if;
    if v_credential.updated_at is distinct from p_expected_updated_at then
      raise exception 'Supplier credential changed concurrently'
        using errcode = '40001';
    end if;

    v_action := 'rotate';
    v_secret_id := v_credential.vault_secret_id;
    perform vault.update_secret(
      v_secret_id,
      p_secret,
      v_secret_name,
      'Supplier credential ' || v_kind || '/' || v_key || ' for ' ||
        p_supplier_id::text
    );

    update public.supplier_credentials credential
    set engagement_id = case
          when coalesce(p_clear_engagement, false) then null
          when p_engagement_id is not null then p_engagement_id
          else credential.engagement_id
        end,
        origin_url = case
          when coalesce(p_clear_origin, false) then null
          when v_origin_input is not null then v_origin_url
          else credential.origin_url
        end,
        label = nullif(btrim(p_label), ''),
        username = nullif(btrim(p_username), ''),
        updated_at = greatest(
          clock_timestamp(),
          credential.updated_at + interval '1 microsecond'
        )
    where credential.id = v_credential.id
    returning * into v_credential;
  else
    if p_expected_updated_at is not null then
      raise exception 'Supplier credential changed concurrently'
        using errcode = '40001';
    end if;

    v_action := 'create';
    select secret.id
    into v_secret_id
    from vault.secrets secret
    where secret.name = v_secret_name
    limit 1;

    if v_secret_id is null then
      v_secret_id := vault.create_secret(
        p_secret,
        v_secret_name,
        'Supplier credential ' || v_kind || '/' || v_key || ' for ' ||
          p_supplier_id::text
      );
    else
      perform vault.update_secret(
        v_secret_id,
        p_secret,
        v_secret_name,
        'Supplier credential ' || v_kind || '/' || v_key || ' for ' ||
          p_supplier_id::text
      );
    end if;

    insert into public.supplier_credentials (
      tenant_id,
      supplier_id,
      credential_kind,
      credential_key,
      engagement_id,
      origin_url,
      label,
      username,
      vault_secret_id
    ) values (
      p_tenant_id,
      p_supplier_id,
      v_kind,
      v_key,
      p_engagement_id,
      v_origin_url,
      nullif(btrim(p_label), ''),
      nullif(btrim(p_username), ''),
      v_secret_id
    ) returning * into v_credential;
  end if;

  insert into public.supplier_credential_access_events (
    tenant_id,
    supplier_id,
    credential_id,
    credential_kind,
    credential_key,
    action,
    actor_id,
    metadata
  ) values (
    p_tenant_id,
    p_supplier_id,
    v_credential.id,
    v_kind,
    v_key,
    v_action,
    case when v_role = 'service_role' then null else auth.uid() end,
    jsonb_build_object(
      'source', case when v_role = 'service_role'
        then 'service_role' else 'authorized_user' end
    )
  );

  if v_kind = 'portal_password' and v_key = 'default' then
    perform set_config(
      'app.supplier_credential_sync_guard',
      txid_current()::text || ':' || p_supplier_id::text,
      true
    );
    update public.suppliers supplier
    set portal_username = nullif(btrim(p_username), ''),
        portal_password = p_secret,
        updated_at = clock_timestamp()
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id;
    perform set_config('app.supplier_credential_sync_guard', '', true);
    perform public.refresh_supplier_portal_origin_issue(
      p_tenant_id,
      p_supplier_id
    );
  end if;

  v_applied := jsonb_build_object(
    'tenant_id', v_credential.tenant_id,
    'supplier_id', v_credential.supplier_id,
    'credential_kind', v_credential.credential_kind,
    'credential_key', v_credential.credential_key,
    'engagement_id', v_credential.engagement_id,
    'origin_url', v_credential.origin_url,
    'label', v_credential.label,
    'username', v_credential.username,
    'updated_at', v_credential.updated_at
  );

  v_result := jsonb_build_object(
    'operation_id', p_operation_id,
    'idempotent_replay', false,
    'action', v_action,
    'credential_stored', true,
    'tenant_id', v_credential.tenant_id,
    'supplier_id', v_credential.supplier_id,
    'credential_kind', v_credential.credential_kind,
    'credential_key', v_credential.credential_key,
    'engagement_id', v_credential.engagement_id,
    'origin_url', v_credential.origin_url,
    'label', v_credential.label,
    'username', v_credential.username,
    'updated_at', v_credential.updated_at,
    'applied_credential', v_applied,
    'current_credential', v_applied
  );

  insert into public.supplier_credential_command_receipts (
    tenant_id,
    operation_id,
    supplier_id,
    credential_kind,
    credential_key,
    command_kind,
    request_fingerprint,
    expected_updated_at,
    credential_id,
    result,
    actor_id
  ) values (
    p_tenant_id,
    p_operation_id,
    p_supplier_id,
    v_kind,
    v_key,
    'upsert',
    v_request_fingerprint,
    p_expected_updated_at,
    v_credential.id,
    v_result,
    case when v_role = 'service_role' then null else auth.uid() end
  );

  return v_result;
end;
$$;

create or replace function public.get_supplier_credential_v2(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_credential_kind text,
  p_credential_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_kind text := lower(btrim(coalesce(p_credential_kind, '')));
  v_key text := lower(btrim(coalesce(p_credential_key, 'default')));
  v_result jsonb;
  v_credential_id uuid;
begin
  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(p_tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'tenant_id', credential.tenant_id,
    'supplier_id', credential.supplier_id,
    'credential_kind', credential.credential_kind,
    'credential_key', credential.credential_key,
    'engagement_id', credential.engagement_id,
    'origin_url', credential.origin_url,
    'label', credential.label,
    'username', credential.username,
    'secret', secret.decrypted_secret,
    'updated_at', credential.updated_at
  ), credential.id
  into v_result, v_credential_id
  from public.supplier_credentials credential
  join vault.decrypted_secrets secret
    on secret.id = credential.vault_secret_id
  where credential.tenant_id = p_tenant_id
    and credential.supplier_id = p_supplier_id
    and credential.credential_kind = v_kind
    and credential.credential_key = v_key
    and nullif(secret.decrypted_secret, '') is not null;

  if v_result is null then
    raise exception 'Supplier credential not found' using errcode = 'P0002';
  end if;

  insert into public.supplier_credential_access_events (
    tenant_id, supplier_id, credential_id, credential_kind,
    credential_key, action, actor_id, metadata
  ) values (
    p_tenant_id, p_supplier_id, v_credential_id, v_kind,
    v_key, 'reveal',
    case when v_role = 'service_role' then null else auth.uid() end,
    jsonb_build_object(
      'source', case when v_role = 'service_role'
        then 'service_role' else 'authorized_user' end
    )
  );

  return v_result;
end;
$$;

create or replace function public.delete_supplier_credential_v2(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_credential_kind text,
  p_credential_key text,
  p_operation_id uuid,
  p_expected_updated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_kind text := lower(btrim(coalesce(p_credential_kind, '')));
  v_key text := lower(btrim(coalesce(p_credential_key, 'default')));
  v_credential public.supplier_credentials%rowtype;
  v_receipt public.supplier_credential_command_receipts%rowtype;
  v_request_fingerprint text;
  v_deleted_at timestamptz;
  v_tombstone jsonb;
  v_result jsonb;
  v_current jsonb;
  v_current_secret text;
begin
  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(p_tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  if v_kind not in ('portal_password', 'api_token', 'other')
     or v_key !~ '^[a-z][a-z0-9_.-]*$'
     or p_operation_id is null then
    raise exception 'Valid credential kind, key, and operation id are required'
      using errcode = '22023';
  end if;

  v_request_fingerprint := encode(extensions.digest(
    jsonb_build_object(
      'supplier_id', p_supplier_id,
      'credential_kind', v_kind,
      'credential_key', v_key,
      'expected_updated_at', p_expected_updated_at
    )::text,
    'sha256'
  ), 'hex');

  -- Match legacy and upsert lock order even on durable receipt replay.
  perform 1
    from public.suppliers supplier
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id
    for update;

  if not found then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_credential_operation:' || p_tenant_id::text || ':' ||
      p_operation_id::text,
      0
    )
  );

  select receipt.*
  into v_receipt
  from public.supplier_credential_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.operation_id = p_operation_id;

  if found then
    if v_receipt.command_kind <> 'delete'
       or v_receipt.request_fingerprint <> v_request_fingerprint then
      raise exception 'Supplier credential operation id was reused with different content'
        using errcode = '23505';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(
      'supplier_credential:' || p_tenant_id::text || ':' ||
      p_supplier_id::text || ':' || v_kind || ':' || v_key,
      0
    ));

    select credential.*
    into v_credential
    from public.supplier_credentials credential
    where credential.tenant_id = p_tenant_id
      and credential.supplier_id = p_supplier_id
      and credential.credential_kind = v_kind
      and credential.credential_key = v_key
    for update;

    if found then
      v_current := jsonb_build_object(
        'tenant_id', v_credential.tenant_id,
        'supplier_id', v_credential.supplier_id,
        'credential_kind', v_credential.credential_kind,
        'credential_key', v_credential.credential_key,
        'engagement_id', v_credential.engagement_id,
        'origin_url', v_credential.origin_url,
        'label', v_credential.label,
        'username', v_credential.username,
        'updated_at', v_credential.updated_at
      );
    else
      v_current := null;
    end if;

    if v_kind = 'portal_password'
       and v_key = 'default'
       and v_credential.id is not null then
      select secret.decrypted_secret
      into v_current_secret
      from vault.decrypted_secrets secret
      where secret.id = v_credential.vault_secret_id;
    end if;

    if v_kind = 'portal_password'
       and v_key = 'default'
       and nullif(v_current_secret, '') is not null then
      perform set_config(
        'app.supplier_credential_sync_guard',
        txid_current()::text || ':' || p_supplier_id::text,
        true
      );
      update public.suppliers supplier
      set portal_username = v_current->>'username',
          portal_password = v_current_secret,
          updated_at = clock_timestamp()
      where supplier.tenant_id = p_tenant_id
        and supplier.id = p_supplier_id
        and (
          supplier.portal_username is distinct from v_current->>'username'
          or supplier.portal_password is distinct from v_current_secret
        );
      perform set_config('app.supplier_credential_sync_guard', '', true);
    end if;

    if v_kind = 'portal_password' and v_key = 'default' then
      perform public.refresh_supplier_portal_origin_issue(
        p_tenant_id,
        p_supplier_id
      );
    end if;

    return v_receipt.result || jsonb_build_object(
      'idempotent_replay', true,
      'current_credential', to_jsonb(v_current)
    );
  end if;

  if p_expected_updated_at is null then
    raise exception 'Expected credential updated_at is required for delete'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_credential:' || p_tenant_id::text || ':' ||
      p_supplier_id::text || ':' || v_kind || ':' || v_key,
      0
    )
  );

  select credential.*
  into v_credential
  from public.supplier_credentials credential
  where credential.tenant_id = p_tenant_id
    and credential.supplier_id = p_supplier_id
    and credential.credential_kind = v_kind
    and credential.credential_key = v_key
  for update;

  if not found
     or v_credential.updated_at is distinct from p_expected_updated_at then
    raise exception 'Supplier credential changed concurrently or was deleted'
      using errcode = '40001';
  end if;

  delete from public.supplier_credentials credential
  where credential.id = v_credential.id;

  delete from vault.secrets secret
  where secret.id = v_credential.vault_secret_id;

  v_deleted_at := clock_timestamp();

  insert into public.supplier_credential_access_events (
    tenant_id, supplier_id, credential_id, credential_kind,
    credential_key, action, actor_id, metadata
  ) values (
    p_tenant_id, p_supplier_id, v_credential.id, v_kind,
    v_key, 'delete',
    case when v_role = 'service_role' then null else auth.uid() end,
    jsonb_build_object(
      'source', case when v_role = 'service_role'
        then 'service_role' else 'authorized_user' end
    )
  );

  if v_kind = 'portal_password' and v_key = 'default' then
    perform set_config(
      'app.supplier_credential_sync_guard',
      txid_current()::text || ':' || p_supplier_id::text,
      true
    );
    update public.suppliers supplier
    set portal_username = null,
        portal_password = null,
        updated_at = clock_timestamp()
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id;
    perform set_config('app.supplier_credential_sync_guard', '', true);
    perform public.refresh_supplier_portal_origin_issue(
      p_tenant_id,
      p_supplier_id
    );
  end if;

  v_tombstone := jsonb_build_object(
    'credential_id', v_credential.id,
    'tenant_id', v_credential.tenant_id,
    'supplier_id', v_credential.supplier_id,
    'credential_kind', v_credential.credential_kind,
    'credential_key', v_credential.credential_key,
    'engagement_id', v_credential.engagement_id,
    'origin_url', v_credential.origin_url,
    'label', v_credential.label,
    'username', v_credential.username,
    'previous_updated_at', v_credential.updated_at,
    'deleted_at', v_deleted_at
  );

  v_result := jsonb_build_object(
    'operation_id', p_operation_id,
    'idempotent_replay', false,
    'action', 'delete',
    'deleted', true,
    'tenant_id', p_tenant_id,
    'supplier_id', p_supplier_id,
    'credential_kind', v_kind,
    'credential_key', v_key,
    'tombstone', v_tombstone,
    'current_credential', null
  );

  insert into public.supplier_credential_command_receipts (
    tenant_id,
    operation_id,
    supplier_id,
    credential_kind,
    credential_key,
    command_kind,
    request_fingerprint,
    expected_updated_at,
    credential_id,
    result,
    actor_id
  ) values (
    p_tenant_id,
    p_operation_id,
    p_supplier_id,
    v_kind,
    v_key,
    'delete',
    v_request_fingerprint,
    p_expected_updated_at,
    v_credential.id,
    v_result,
    case when v_role = 'service_role' then null else auth.uid() end
  );

  return v_result;
end;
$$;

create or replace function public.upsert_supplier_credential(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_credential_kind text,
  p_label text,
  p_username text,
  p_secret text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  v_kind text := lower(btrim(coalesce(p_credential_kind, '')));
  v_operation_id uuid := gen_random_uuid();
  v_expected_updated_at timestamptz;
begin
  select credential.updated_at
  into v_expected_updated_at
  from public.supplier_credentials credential
  where credential.tenant_id = p_tenant_id
    and credential.supplier_id = p_supplier_id
    and credential.credential_kind = v_kind
    and credential.credential_key = 'default';

  return public.upsert_supplier_credential_v2(
    p_tenant_id,
    p_supplier_id,
    v_kind,
    'default',
    v_operation_id,
    v_expected_updated_at,
    null,
    null,
    p_label,
    p_username,
    p_secret,
    false,
    false
  );
end;
$$;

create or replace function public.get_supplier_credential(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_credential_kind text
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select public.get_supplier_credential_v2(
    p_tenant_id,
    p_supplier_id,
    p_credential_kind,
    'default'
  )
$$;

create or replace function public.delete_supplier_credential(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_credential_kind text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  v_kind text := lower(btrim(coalesce(p_credential_kind, '')));
  v_operation_id uuid := gen_random_uuid();
  v_expected_updated_at timestamptz;
  v_result jsonb;
begin
  select credential.updated_at
  into v_expected_updated_at
  from public.supplier_credentials credential
  where credential.tenant_id = p_tenant_id
    and credential.supplier_id = p_supplier_id
    and credential.credential_kind = v_kind
    and credential.credential_key = 'default';

  if v_expected_updated_at is null then
    return false;
  end if;

  v_result := public.delete_supplier_credential_v2(
    p_tenant_id,
    p_supplier_id,
    v_kind,
    'default',
    v_operation_id,
    v_expected_updated_at
  );

  return coalesce((v_result->>'deleted')::boolean, false);
end;
$$;

-- Transitional old-client bridge. Every actual legacy row transition owns a
-- fresh operation id. A lost-ack retry that writes the already-current value
-- does not fire the DISTINCT trigger, while A->B->A and repeated delete cycles
-- must never replay a receipt from an earlier credential generation.
create or replace function public.sync_legacy_supplier_portal_credential()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, vault, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_guard text := coalesce(
    current_setting('app.supplier_credential_sync_guard', true),
    ''
  );
  v_expected_guard text := txid_current()::text || ':' || new.id::text;
  v_operation_id uuid := gen_random_uuid();
  v_expected_updated_at timestamptz;
  v_origin_url text := public.canonical_https_origin(new.website);
begin
  if v_guard = v_expected_guard then
    return new;
  end if;

  if v_role <> 'service_role'
     and not public.can_manage_supplier_credentials(new.tenant_id) then
    raise exception 'Supplier credential authority required'
      using errcode = '42501';
  end if;

  if nullif(btrim(new.website), '') is not null and v_origin_url is null then
    insert into public.supplier_data_quality_candidates (
      tenant_id, supplier_id, issue_code, scope_type, scope_id,
      related_code, field_key, display_reason, issue_source, metadata
    ) values (
      new.tenant_id,
      new.id,
      'legacy_portal_origin_not_canonical',
      'credential',
      new.id,
      'portal_password/default',
      'origin_url',
      'El origen del portal legado requiere revisión antes de asociar credenciales.',
      'domain_validation',
      jsonb_build_object(
        'source', 'suppliers.website',
        'reason', 'not_an_exact_https_origin'
      )
    ) on conflict (tenant_id, supplier_id, issue_code) do nothing;
  end if;

  if nullif(new.portal_password, '') is null then
    select credential.updated_at
    into v_expected_updated_at
    from public.supplier_credentials credential
    where credential.tenant_id = new.tenant_id
      and credential.supplier_id = new.id
      and credential.credential_kind = 'portal_password'
      and credential.credential_key = 'default';

    if v_expected_updated_at is not null then
      perform public.delete_supplier_credential_v2(
        new.tenant_id,
        new.id,
        'portal_password',
        'default',
        v_operation_id,
        v_expected_updated_at
      );
    end if;
  else
    select credential.updated_at
    into v_expected_updated_at
    from public.supplier_credentials credential
    where credential.tenant_id = new.tenant_id
      and credential.supplier_id = new.id
      and credential.credential_kind = 'portal_password'
      and credential.credential_key = 'default';

    perform public.upsert_supplier_credential_v2(
      new.tenant_id,
      new.id,
      'portal_password',
      'default',
      v_operation_id,
      v_expected_updated_at,
      null,
      v_origin_url,
      'Portal principal',
      new.portal_username,
      new.portal_password,
      false,
      false
    );
  end if;

  return new;
end;
$$;

revoke all on function public.sync_legacy_supplier_portal_credential()
  from public, anon, authenticated, service_role;

revoke all on function public.upsert_supplier_credential(
  uuid, uuid, text, text, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.get_supplier_credential(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.delete_supplier_credential(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.get_supplier_credential_status(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.find_supplier_credential_for_origin(
  uuid, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.upsert_supplier_credential_v2(
  uuid, uuid, text, text, uuid, timestamptz,
  uuid, text, text, text, text, boolean, boolean
) from public, anon, authenticated, service_role;
revoke all on function public.get_supplier_credential_v2(
  uuid, uuid, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.delete_supplier_credential_v2(
  uuid, uuid, text, text, uuid, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.upsert_supplier_credential(
  uuid, uuid, text, text, text, text
) to authenticated, service_role;
grant execute on function public.get_supplier_credential(uuid, uuid, text)
  to authenticated, service_role;
grant execute on function public.delete_supplier_credential(uuid, uuid, text)
  to authenticated, service_role;
grant execute on function public.get_supplier_credential_status(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.find_supplier_credential_for_origin(
  uuid, text, text
) to authenticated, service_role;
grant execute on function public.upsert_supplier_credential_v2(
  uuid, uuid, text, text, uuid, timestamptz,
  uuid, text, text, text, text, boolean, boolean
) to authenticated, service_role;
grant execute on function public.get_supplier_credential_v2(
  uuid, uuid, text, text
) to authenticated, service_role;
grant execute on function public.delete_supplier_credential_v2(
  uuid, uuid, text, text, uuid, timestamptz
) to authenticated, service_role;

-- The legacy backup serializer snapshots suppliers.* and therefore used to
-- duplicate portal_password outside Vault. Keep its broad implementation
-- private behind a transactionally sanitizing owner, so manual and scheduled
-- backups both persist only non-secret supplier fields.
do $$
begin
  if to_regprocedure(
    'public.create_backup_legacy_unsafe_internal(uuid,text,text,text)'
  ) is null then
    if to_regprocedure(
      'public.create_backup_internal(uuid,text,text,text)'
    ) is null then
      raise exception 'Missing canonical create_backup_internal RPC';
    end if;

    alter function public.create_backup_internal(uuid, text, text, text)
      rename to create_backup_legacy_unsafe_internal;
  end if;
end
$$;

revoke all on function public.create_backup_legacy_unsafe_internal(
  uuid, text, text, text
) from public, anon, authenticated, service_role;

create or replace function public.redact_supplier_passwords_from_backup_row(
  p_backup_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_updated boolean;
begin
  with sanitized as (
    select
      backup.id,
      case
        when jsonb_typeof(backup.backup_data -> 'suppliers') = 'array'
          then jsonb_set(
            backup.backup_data,
            '{suppliers}',
            coalesce(
              (
                select jsonb_agg(
                  supplier_item -
                    array['portal_username', 'portal_password']
                  order by ordinal
                )
                from jsonb_array_elements(
                  backup.backup_data -> 'suppliers'
                ) with ordinality as item(supplier_item, ordinal)
              ),
              '[]'::jsonb
            ),
            true
          )
        else backup.backup_data
      end as payload
    from public.database_backups backup
    where backup.id = p_backup_id
  ), updated as (
    update public.database_backups backup
    set backup_data = sanitized.payload,
        backup_size_bytes = length(sanitized.payload::text)
    from sanitized
    where backup.id = sanitized.id
    returning true as did_update
  )
  select did_update into v_updated from updated;

  return coalesce(v_updated, false);
end;
$$;

revoke all on function public.redact_supplier_passwords_from_backup_row(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.create_backup_internal(
  p_tenant_id uuid,
  p_backup_name text,
  p_backup_type text default 'manual',
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  v_result jsonb;
  v_backup_id uuid;
  v_backup_size_bytes bigint;
begin
  v_result := public.create_backup_legacy_unsafe_internal(
    p_tenant_id,
    p_backup_name,
    p_backup_type,
    p_notes
  );

  if coalesce((v_result ->> 'success')::boolean, false) then
    v_backup_id := nullif(v_result ->> 'backup_id', '')::uuid;
    if v_backup_id is null
       or not public.redact_supplier_passwords_from_backup_row(v_backup_id) then
      raise exception 'Created backup could not be sanitized'
        using errcode = 'P0001';
    end if;

    select backup.backup_size_bytes
    into v_backup_size_bytes
    from public.database_backups backup
    where backup.id = v_backup_id;

    if v_backup_size_bytes is null then
      raise exception 'Sanitized backup size could not be verified'
        using errcode = 'P0001';
    end if;

    v_result := jsonb_set(
      v_result,
      '{size_mb}',
      to_jsonb(round((v_backup_size_bytes / 1024.0 / 1024.0)::numeric, 2)),
      true
    );
  end if;

  return v_result;
end;
$$;

revoke all on function public.create_backup_internal(
  uuid, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.create_backup_internal(
  uuid, text, text, text
) to service_role;

-- The legacy restore deletes/recreates suppliers and purchase invoices. During
-- its transaction the wrapper shields those two durable aggregate identities,
-- removes their arrays from the legacy payload, then applies the historical
-- rows in place. This preserves new FK-bound history and rehydrates the party
-- bridge. Set changes or account-linked foundation policies fail closed before
-- any legacy delete; a later backup-domain migration can add full set mutation.
create or replace function public.guard_supplier_foundation_restore_delete()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if current_setting('app.supplier_foundation_restore_tenant', true)
       = old.tenant_id::text
     and current_user::text in (
       'postgres', 'supabase_admin', 'service_role'
     ) then
    return null;
  end if;

  return old;
end;
$$;

revoke all on function public.guard_supplier_foundation_restore_delete()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_supplier_foundation_restore_delete
  on public.suppliers;
drop trigger if exists a00_guard_supplier_foundation_restore_delete
  on public.suppliers;
create trigger a00_guard_supplier_foundation_restore_delete
  before delete on public.suppliers
  for each row
  execute function public.guard_supplier_foundation_restore_delete();

drop trigger if exists trg_guard_purchase_invoice_foundation_restore_delete
  on public.purchase_invoices;
drop trigger if exists a00_guard_purchase_invoice_foundation_restore_delete
  on public.purchase_invoices;
create trigger a00_guard_purchase_invoice_foundation_restore_delete
  before delete on public.purchase_invoices
  for each row
  execute function public.guard_supplier_foundation_restore_delete();

create or replace function public.lock_supplier_foundation_restore_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_old_tenant_id uuid := case when tg_op = 'INSERT'
    then null else old.tenant_id end;
  v_new_tenant_id uuid := case when tg_op = 'DELETE'
    then null else new.tenant_id end;
  v_first_tenant_id uuid;
  v_second_tenant_id uuid;
begin
  if v_old_tenant_id is null
     or v_new_tenant_id is null
     or v_old_tenant_id = v_new_tenant_id then
    perform pg_advisory_xact_lock_shared(hashtextextended(
      'supplier_foundation_restore:' ||
        coalesce(v_new_tenant_id, v_old_tenant_id)::text,
      0
    ));
  else
    if v_old_tenant_id::text < v_new_tenant_id::text then
      v_first_tenant_id := v_old_tenant_id;
      v_second_tenant_id := v_new_tenant_id;
    else
      v_first_tenant_id := v_new_tenant_id;
      v_second_tenant_id := v_old_tenant_id;
    end if;

    perform pg_advisory_xact_lock_shared(hashtextextended(
      'supplier_foundation_restore:' || v_first_tenant_id::text,
      0
    ));
    perform pg_advisory_xact_lock_shared(hashtextextended(
      'supplier_foundation_restore:' || v_second_tenant_id::text,
      0
    ));
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

comment on function public.lock_supplier_foundation_restore_mutation() is
  'Ordinary supplier and purchase-invoice mutations share a tenant advisory owner. The restore first drains DML through a table SHARE fence, avoiding the UPDATE/DELETE tuple-lock deadlock that a row-trigger advisory fence alone cannot prevent.';

revoke all on function public.lock_supplier_foundation_restore_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_00_supplier_foundation_restore_lock
  on public.suppliers;
create trigger trg_00_supplier_foundation_restore_lock
  before insert or update or delete on public.suppliers
  for each row
  execute function public.lock_supplier_foundation_restore_mutation();

drop trigger if exists trg_00_supplier_foundation_restore_lock
  on public.purchase_invoices;
create trigger trg_00_supplier_foundation_restore_lock
  before insert or update or delete on public.purchase_invoices
  for each row
  execute function public.lock_supplier_foundation_restore_mutation();

create or replace function public.supplier_foundation_invoice_rehydrate_is_active(
  p_tenant_id uuid
)
returns boolean
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if nullif(current_setting(
       'app.supplier_foundation_invoice_rehydrate_tenant', true
     ), '') is distinct from p_tenant_id::text then
    return false;
  end if;

  -- The setting is only an internal transaction marker, not authority. A
  -- normal authenticated table writer remains current_user=authenticated and
  -- cannot forge the restore bypass. The SECURITY DEFINER restore owner stays
  -- authoritative even when request.jwt.claims correctly retains the admin
  -- caller's authenticated role.
  return current_user::text in ('postgres', 'supabase_admin', 'service_role');
end;
$$;

comment on function public.supplier_foundation_invoice_rehydrate_is_active(uuid)
  is 'Internal transaction-local predicate used only to suppress purchase-invoice derived effects while the canonical SECURITY DEFINER restore owner rehydrates an already-restored snapshot. The marker is not authority and direct authenticated callers always fail closed.';

revoke all on function public.supplier_foundation_invoice_rehydrate_is_active(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.supplier_foundation_invoice_rehydrate_is_active(uuid)
  to authenticated, service_role;

-- The legacy restore owner has already restored products, stock movements,
-- journals and normalized source tables before the foundation wrapper updates
-- the preserved purchase-invoice identities in place. Every UPDATE trigger
-- that can validate, normalize, trace, broadcast or derive invoice state must
-- therefore consume the internal rehydrate marker. INSERT and DELETE retain
-- their ordinary trigger behavior under separate event-specific triggers.

drop trigger if exists aa_inventory_trace_activate_purchase_invoices
  on public.purchase_invoices;
drop trigger if exists aa_inventory_trace_activate_purchase_invoices_i
  on public.purchase_invoices;
drop trigger if exists aa_inventory_trace_activate_purchase_invoices_d
  on public.purchase_invoices;
do $$
begin
  if to_regprocedure(
    'public.activate_inventory_accounting_trace_context_frame()'
  ) is not null then
    execute 'create trigger aa_inventory_trace_activate_purchase_invoices after update on public.purchase_invoices for each row when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id)) execute function public.activate_inventory_accounting_trace_context_frame()';
    execute 'create trigger aa_inventory_trace_activate_purchase_invoices_i after insert on public.purchase_invoices for each row execute function public.activate_inventory_accounting_trace_context_frame()';
    execute 'create trigger aa_inventory_trace_activate_purchase_invoices_d after delete on public.purchase_invoices for each row execute function public.activate_inventory_accounting_trace_context_frame()';
  end if;
end;
$$;

drop trigger if exists purchase_invoice_reversal_trigger
  on public.purchase_invoices;
create trigger purchase_invoice_reversal_trigger
  before update of status on public.purchase_invoices
  for each row
  when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id))
  execute function public.handle_purchase_invoice_reversal();

drop trigger if exists trg_broadcast_financial_projection_change
  on public.purchase_invoices;
drop trigger if exists trg_broadcast_financial_projection_change_i
  on public.purchase_invoices;
drop trigger if exists trg_broadcast_financial_projection_change_d
  on public.purchase_invoices;
create trigger trg_broadcast_financial_projection_change
  after update on public.purchase_invoices
  for each row
  when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id))
  execute function public.broadcast_financial_projection_change();
create trigger trg_broadcast_financial_projection_change_i
  after insert on public.purchase_invoices
  for each row
  execute function public.broadcast_financial_projection_change();
create trigger trg_broadcast_financial_projection_change_d
  after delete on public.purchase_invoices
  for each row
  execute function public.broadcast_financial_projection_change();

drop trigger if exists trg_guard_legacy_purchase_receiving_when_enforced
  on public.purchase_invoices;
drop trigger if exists trg_guard_legacy_purchase_receiving_when_enforced_i
  on public.purchase_invoices;
do $$
begin
  if to_regprocedure(
    'public.guard_legacy_purchase_receiving_when_enforced()'
  ) is not null then
    execute 'create trigger trg_guard_legacy_purchase_receiving_when_enforced before update of status on public.purchase_invoices for each row when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id)) execute function public.guard_legacy_purchase_receiving_when_enforced()';
    execute 'create trigger trg_guard_legacy_purchase_receiving_when_enforced_i before insert on public.purchase_invoices for each row execute function public.guard_legacy_purchase_receiving_when_enforced()';
  end if;
end;
$$;

drop trigger if exists trg_prevent_financial_edit_with_purchase_credit
  on public.purchase_invoices;
do $$
begin
  if to_regprocedure(
    'public.prevent_financial_edit_with_posted_purchase_credit()'
  ) is not null then
    execute 'create trigger trg_prevent_financial_edit_with_purchase_credit before update on public.purchase_invoices for each row when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id)) execute function public.prevent_financial_edit_with_posted_purchase_credit()';
  end if;
end;
$$;

drop trigger if exists trg_purchase_invoices_change
  on public.purchase_invoices;
drop trigger if exists trg_purchase_invoices_change_i
  on public.purchase_invoices;
drop trigger if exists trg_purchase_invoices_change_d
  on public.purchase_invoices;
create trigger trg_purchase_invoices_change
  after update on public.purchase_invoices
  for each row
  when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id))
  execute function public.handle_purchase_invoice_change();
create trigger trg_purchase_invoices_change_i
  after insert on public.purchase_invoices
  for each row
  execute function public.handle_purchase_invoice_change();
create trigger trg_purchase_invoices_change_d
  after delete on public.purchase_invoices
  for each row
  execute function public.handle_purchase_invoice_change();

drop trigger if exists trg_purchase_invoices_normalize_clp_amounts
  on public.purchase_invoices;
drop trigger if exists trg_purchase_invoices_normalize_clp_amounts_i
  on public.purchase_invoices;
create trigger trg_purchase_invoices_normalize_clp_amounts
  before update of subtotal, tax, iva_amount, total, paid_amount, balance,
    net_amount, discount_amount, tax_treatment on public.purchase_invoices
  for each row
  when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id))
  execute function public.normalize_purchase_invoice_clp_amounts();
create trigger trg_purchase_invoices_normalize_clp_amounts_i
  before insert on public.purchase_invoices
  for each row
  execute function public.normalize_purchase_invoice_clp_amounts();

drop trigger if exists trg_purchase_invoices_updated_at
  on public.purchase_invoices;
create trigger trg_purchase_invoices_updated_at
  before update on public.purchase_invoices
  for each row
  when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id))
  execute function public.set_updated_at();

drop trigger if exists trg_set_purchase_context
  on public.purchase_invoices;
do $$
begin
  if to_regprocedure(
    'public.set_purchase_context_on_status_change()'
  ) is not null then
    execute 'create trigger trg_set_purchase_context before update of status on public.purchase_invoices for each row when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id)) execute function public.set_purchase_context_on_status_change()';
  end if;
end;
$$;

drop trigger if exists trg_sync_purchase_invoice_legacy_lines
  on public.purchase_invoices;
drop trigger if exists trg_sync_purchase_invoice_legacy_lines_i
  on public.purchase_invoices;
create trigger trg_sync_purchase_invoice_legacy_lines
  after update of items, additional_costs, discount_amount, total, tax,
    tax_treatment on public.purchase_invoices
  for each row
  when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id))
  execute function public.sync_changed_purchase_invoice_legacy_lines();
create trigger trg_sync_purchase_invoice_legacy_lines_i
  after insert on public.purchase_invoices
  for each row
  execute function public.sync_changed_purchase_invoice_legacy_lines();

drop trigger if exists trg_sync_purchase_invoice_tax_document_link
  on public.purchase_invoices;
drop trigger if exists trg_sync_purchase_invoice_tax_document_link_i
  on public.purchase_invoices;
create trigger trg_sync_purchase_invoice_tax_document_link
  after update of received_tax_document_id, tenant_id
  on public.purchase_invoices
  for each row
  when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id))
  execute function public.sync_purchase_invoice_tax_document_link();
create trigger trg_sync_purchase_invoice_tax_document_link_i
  after insert on public.purchase_invoices
  for each row
  execute function public.sync_purchase_invoice_tax_document_link();

drop trigger if exists trg_update_purchase_list_on_status_change
  on public.purchase_invoices;
create trigger trg_update_purchase_list_on_status_change
  after update of status on public.purchase_invoices
  for each row
  when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id))
  execute function public.auto_update_purchase_list_on_invoice_status();

drop trigger if exists trg_validate_purchase_invoice_tax_document_link
  on public.purchase_invoices;
drop trigger if exists trg_validate_purchase_invoice_tax_document_link_i
  on public.purchase_invoices;
create trigger trg_validate_purchase_invoice_tax_document_link
  before update of tenant_id, supplier_id, received_tax_document_id
  on public.purchase_invoices
  for each row
  when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id))
  execute function public.validate_purchase_invoice_tax_document_link();
create trigger trg_validate_purchase_invoice_tax_document_link_i
  before insert on public.purchase_invoices
  for each row
  execute function public.validate_purchase_invoice_tax_document_link();

drop trigger if exists zy_inventory_trace_push_purchase_invoices
  on public.purchase_invoices;
drop trigger if exists zy_inventory_trace_push_purchase_invoices_d
  on public.purchase_invoices;
do $$
begin
  if to_regprocedure(
    'public.push_inventory_accounting_trace_context_frame()'
  ) is not null then
    execute 'create trigger zy_inventory_trace_push_purchase_invoices before update on public.purchase_invoices for each row when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id)) execute function public.push_inventory_accounting_trace_context_frame()';
    execute 'create trigger zy_inventory_trace_push_purchase_invoices_d before delete on public.purchase_invoices for each row execute function public.push_inventory_accounting_trace_context_frame()';
  end if;
end;
$$;

drop trigger if exists zz_inventory_trace_begin_purchase_invoice
  on public.purchase_invoices;
drop trigger if exists zz_inventory_trace_begin_purchase_invoice_d
  on public.purchase_invoices;
create trigger zz_inventory_trace_begin_purchase_invoice
  before update on public.purchase_invoices
  for each row
  when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id))
  execute function public.begin_invoice_inventory_accounting_trace();
create trigger zz_inventory_trace_begin_purchase_invoice_d
  before delete on public.purchase_invoices
  for each row
  execute function public.begin_invoice_inventory_accounting_trace();

drop trigger if exists zza_inventory_trace_capture_purchase_invoices
  on public.purchase_invoices;
drop trigger if exists zza_inventory_trace_capture_purchase_invoices_d
  on public.purchase_invoices;
do $$
begin
  if to_regprocedure(
    'public.capture_inventory_accounting_trace_context_frame()'
  ) is not null then
    execute 'create trigger zza_inventory_trace_capture_purchase_invoices before update on public.purchase_invoices for each row when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id)) execute function public.capture_inventory_accounting_trace_context_frame()';
    execute 'create trigger zza_inventory_trace_capture_purchase_invoices_d before delete on public.purchase_invoices for each row execute function public.capture_inventory_accounting_trace_context_frame()';
  end if;
end;
$$;

drop trigger if exists zzy_observe_legacy_purchase_receipt_transition
  on public.purchase_invoices;
do $$
begin
  if to_regprocedure(
    'public.observe_legacy_purchase_receipt_transition()'
  ) is not null then
    execute 'create trigger zzy_observe_legacy_purchase_receipt_transition after update of status on public.purchase_invoices for each row when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id)) execute function public.observe_legacy_purchase_receipt_transition()';
  end if;
end;
$$;

drop trigger if exists zzz_inventory_trace_complete_purchase_invoice
  on public.purchase_invoices;
drop trigger if exists zzz_inventory_trace_complete_purchase_invoice_i
  on public.purchase_invoices;
drop trigger if exists zzz_inventory_trace_complete_purchase_invoice_d
  on public.purchase_invoices;
create trigger zzz_inventory_trace_complete_purchase_invoice
  after update on public.purchase_invoices
  for each row
  when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id))
  execute function public.complete_invoice_inventory_accounting_trace();
create trigger zzz_inventory_trace_complete_purchase_invoice_i
  after insert on public.purchase_invoices
  for each row
  execute function public.complete_invoice_inventory_accounting_trace();
create trigger zzz_inventory_trace_complete_purchase_invoice_d
  after delete on public.purchase_invoices
  for each row
  execute function public.complete_invoice_inventory_accounting_trace();

drop trigger if exists zzzz_inventory_trace_restore_purchase_invoices
  on public.purchase_invoices;
drop trigger if exists zzzz_inventory_trace_restore_purchase_invoices_i
  on public.purchase_invoices;
drop trigger if exists zzzz_inventory_trace_restore_purchase_invoices_d
  on public.purchase_invoices;
do $$
begin
  if to_regprocedure(
    'public.restore_inventory_accounting_trace_context_frame()'
  ) is not null then
    execute 'create trigger zzzz_inventory_trace_restore_purchase_invoices after update on public.purchase_invoices for each row when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id)) execute function public.restore_inventory_accounting_trace_context_frame()';
    execute 'create trigger zzzz_inventory_trace_restore_purchase_invoices_i after insert on public.purchase_invoices for each row execute function public.restore_inventory_accounting_trace_context_frame()';
    execute 'create trigger zzzz_inventory_trace_restore_purchase_invoices_d after delete on public.purchase_invoices for each row execute function public.restore_inventory_accounting_trace_context_frame()';
  end if;
end;
$$;

do $$
begin
  if to_regprocedure(
    'public.restore_backup_legacy_unsafe_internal(uuid,uuid)'
  ) is null then
    if to_regprocedure(
      'public.restore_backup_internal(uuid,uuid)'
    ) is null then
      raise exception 'Missing canonical restore_backup_internal RPC';
    end if;

    alter function public.restore_backup_internal(uuid, uuid)
      rename to restore_backup_legacy_unsafe_internal;
  end if;
end
$$;

revoke all on function public.restore_backup_legacy_unsafe_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.restore_backup_internal(
  p_backup_id uuid,
  p_tenant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, vault, extensions, pg_temp
as $$
declare
  v_backup_data jsonb;
  v_backup_suppliers jsonb;
  v_backup_purchase_invoices jsonb;
  v_backup_supplier_ids uuid[];
  v_current_supplier_ids uuid[];
  v_backup_invoice_ids uuid[];
  v_current_invoice_ids uuid[];
  v_working_backup_id uuid := gen_random_uuid();
  v_working_backup_data jsonb;
  v_supplier_item jsonb;
  v_invoice_item jsonb;
  v_current_supplier public.suppliers%rowtype;
  v_restored_supplier public.suppliers%rowtype;
  v_current_invoice public.purchase_invoices%rowtype;
  v_restored_invoice public.purchase_invoices%rowtype;
  v_supplier_count integer := 0;
  v_invoice_count integer := 0;
  v_credential_count integer := 0;
  v_result jsonb;
begin
  -- Acquire the table-level DML fence before any tenant row or advisory lock.
  -- UPDATE/DELETE take tuple locks before BEFORE ROW triggers, so relying on
  -- the advisory trigger alone could deadlock a writer against this restore.
  -- SHARE ROW EXCLUSIVE conflicts with every DML RowExclusive lock at
  -- statement entry and with another restore fence, while preserving ordinary
  -- reads. Self-conflict avoids the SHARE-to-RowExclusive lock-upgrade
  -- deadlock that two concurrent restores could otherwise create.
  lock table public.suppliers, public.purchase_invoices
    in share row exclusive mode;

  -- Keep the tenant advisory owner for explicit command-level coordination,
  -- but only after the table fence has drained existing DML safely.
  perform pg_advisory_xact_lock(hashtextextended(
    'supplier_foundation_restore:' || p_tenant_id::text,
    0
  ));

  select backup.backup_data
  into v_backup_data
  from public.database_backups backup
  where backup.id = p_backup_id
    and backup.tenant_id = p_tenant_id
    and backup.status = 'completed';

  if v_backup_data is null then
    raise exception 'Backup not found or invalid' using errcode = 'P0002';
  end if;

  if (v_backup_data ? 'suppliers'
      and v_backup_data -> 'suppliers' <> 'null'::jsonb
      and jsonb_typeof(v_backup_data -> 'suppliers') <> 'array')
     or (v_backup_data ? 'purchase_invoices'
      and v_backup_data -> 'purchase_invoices' <> 'null'::jsonb
      and jsonb_typeof(v_backup_data -> 'purchase_invoices') <> 'array') then
    return jsonb_build_object(
      'success', false,
      'error_code', 'supplier_foundation_restore_invalid_payload',
      'message', 'El respaldo no contiene arreglos validos de proveedores y facturas de compra.',
      'backup_id', p_backup_id,
      'tenant_id', p_tenant_id
    );
  end if;

  v_backup_suppliers := case
    when jsonb_typeof(v_backup_data -> 'suppliers') = 'array'
      then v_backup_data -> 'suppliers'
    else '[]'::jsonb
  end;
  v_backup_purchase_invoices := case
    when jsonb_typeof(v_backup_data -> 'purchase_invoices') = 'array'
      then v_backup_data -> 'purchase_invoices'
    else '[]'::jsonb
  end;

  if exists (
    select 1
    from jsonb_array_elements(v_backup_suppliers) item
    where nullif(item ->> 'id', '') is null
      or (
        nullif(item ->> 'tenant_id', '') is not null
        and (item ->> 'tenant_id')::uuid <> p_tenant_id
      )
  ) or exists (
    select 1
    from jsonb_array_elements(v_backup_purchase_invoices) item
    where nullif(item ->> 'id', '') is null
      or (
        nullif(item ->> 'tenant_id', '') is not null
        and (item ->> 'tenant_id')::uuid <> p_tenant_id
      )
  ) then
    return jsonb_build_object(
      'success', false,
      'error_code', 'supplier_foundation_restore_invalid_identity',
      'message', 'El respaldo contiene identidades vacias o de otro tenant.',
      'backup_id', p_backup_id,
      'tenant_id', p_tenant_id
    );
  end if;

  select coalesce(array_agg(id order by id), array[]::uuid[])
  into v_backup_supplier_ids
  from (
    select (item ->> 'id')::uuid as id
    from jsonb_array_elements(v_backup_suppliers) item
  ) ids;

  select coalesce(array_agg(supplier.id order by supplier.id), array[]::uuid[])
  into v_current_supplier_ids
  from public.suppliers supplier
  where supplier.tenant_id = p_tenant_id;

  select coalesce(array_agg(id order by id), array[]::uuid[])
  into v_backup_invoice_ids
  from (
    select (item ->> 'id')::uuid as id
    from jsonb_array_elements(v_backup_purchase_invoices) item
  ) ids;

  select coalesce(array_agg(invoice.id order by invoice.id), array[]::uuid[])
  into v_current_invoice_ids
  from public.purchase_invoices invoice
  where invoice.tenant_id = p_tenant_id;

  if v_backup_supplier_ids is distinct from v_current_supplier_ids then
    return jsonb_build_object(
      'success', false,
      'error_code', 'supplier_foundation_restore_supplier_set_changed',
      'message', 'Este respaldo cambia el conjunto de proveedores. La restauracion segura exige los mismos IDs durables.',
      'backup_id', p_backup_id,
      'tenant_id', p_tenant_id,
      'current_count', cardinality(v_current_supplier_ids),
      'backup_count', cardinality(v_backup_supplier_ids)
    );
  end if;

  if v_backup_invoice_ids is distinct from v_current_invoice_ids then
    return jsonb_build_object(
      'success', false,
      'error_code', 'supplier_foundation_restore_purchase_invoice_set_changed',
      'message', 'Este respaldo cambia el conjunto de facturas de compra. La restauracion segura exige los mismos IDs durables.',
      'backup_id', p_backup_id,
      'tenant_id', p_tenant_id,
      'current_count', cardinality(v_current_invoice_ids),
      'backup_count', cardinality(v_backup_invoice_ids)
    );
  end if;

  if exists (
    select 1
    from public.supplier_accounting_policy_versions version
    where version.tenant_id = p_tenant_id
      and (
        version.debit_account_id is not null
        or version.liability_account_id is not null
      )
  ) or exists (
    select 1
    from public.supplier_accounting_evidence evidence
    where evidence.tenant_id = p_tenant_id
      and (
        evidence.debit_account_id is not null
        or evidence.liability_account_id is not null
      )
  ) then
    return jsonb_build_object(
      'success', false,
      'error_code', 'supplier_foundation_restore_account_dependencies',
      'message', 'La restauracion reemplazaria cuentas que ya estan referenciadas por politicas o evidencia contable de proveedores.',
      'backup_id', p_backup_id,
      'tenant_id', p_tenant_id
    );
  end if;

  v_working_backup_data := jsonb_set(
    jsonb_set(v_backup_data, '{suppliers}', '[]'::jsonb, true),
    '{purchase_invoices}',
    '[]'::jsonb,
    true
  );

  insert into public.database_backups (
    id,
    tenant_id,
    backup_name,
    backup_type,
    status,
    backup_data,
    summary,
    created_by,
    created_at,
    backup_size_bytes,
    notes
  )
  select
    v_working_backup_id,
    backup.tenant_id,
    backup.backup_name || ' [internal foundation restore]',
    backup.backup_type,
    'completed',
    v_working_backup_data,
    backup.summary,
    backup.created_by,
    backup.created_at,
    length(v_working_backup_data::text),
    backup.notes
  from public.database_backups backup
  where backup.id = p_backup_id
    and backup.tenant_id = p_tenant_id;

  perform set_config(
    'app.supplier_foundation_restore_tenant',
    p_tenant_id::text,
    true
  );
  -- The legacy owner inserts the backed-up product balances before it inserts
  -- the backed-up stock movements. Suppress compatibility stock-adjustment
  -- triggers for that exact internal window so the snapshot is not augmented
  -- with a second synthetic opening movement.
  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);
  v_result := public.restore_backup_legacy_unsafe_internal(
    v_working_backup_id,
    p_tenant_id
  );
  perform set_config('app.skip_stock_adjustment_trigger', '', true);
  perform set_config('app.supplier_foundation_restore_tenant', '', true);
  delete from public.database_backups
  where id = v_working_backup_id;

  if not coalesce((v_result ->> 'success')::boolean, false) then
    return (v_result - 'backup_id') || jsonb_build_object(
      'backup_id', p_backup_id,
      'error_code', 'supplier_foundation_legacy_restore_failed',
      'foundation_safe', true
    );
  end if;

  -- Avoid transient tenant/name conflicts while two historical names swap.
  update public.suppliers supplier
  set name = '__foundation_restore__' || supplier.id::text
  where supplier.tenant_id = p_tenant_id;

  for v_supplier_item in
    select item
    from jsonb_array_elements(v_backup_suppliers) item
    order by item ->> 'id'
  loop
    select supplier.*
    into strict v_current_supplier
    from public.suppliers supplier
    where supplier.tenant_id = p_tenant_id
      and supplier.id = (v_supplier_item ->> 'id')::uuid
    for update;

    v_restored_supplier := jsonb_populate_record(
      v_current_supplier,
      v_supplier_item - array[
        'id', 'tenant_id', 'party_id', 'portal_username', 'portal_password'
      ]
    );

    if v_restored_supplier.default_tax_treatment = 'taxIncluded' then
      v_restored_supplier.default_tax_treatment := 'tax_included';
    end if;

    update public.suppliers supplier
    set name = v_restored_supplier.name,
        legal_name = v_restored_supplier.legal_name,
        trade_name = v_restored_supplier.trade_name,
        owner_name = v_restored_supplier.owner_name,
        aliases = v_restored_supplier.aliases,
        rut = v_restored_supplier.rut,
        email = v_restored_supplier.email,
        phone = v_restored_supplier.phone,
        address = v_restored_supplier.address,
        city = v_restored_supplier.city,
        region = v_restored_supplier.region,
        comuna = v_restored_supplier.comuna,
        contact_person = v_restored_supplier.contact_person,
        website = v_restored_supplier.website,
        type = v_restored_supplier.type,
        bank_details = v_restored_supplier.bank_details,
        ocr_template = v_restored_supplier.ocr_template,
        payment_terms = v_restored_supplier.payment_terms,
        notes = v_restored_supplier.notes,
        image_url = v_restored_supplier.image_url,
        sales_rep_name = v_restored_supplier.sales_rep_name,
        sales_rep_phone = v_restored_supplier.sales_rep_phone,
        sales_rep_email = v_restored_supplier.sales_rep_email,
        purchase_instructions = v_restored_supplier.purchase_instructions,
        is_active = v_restored_supplier.is_active,
        created_at = v_restored_supplier.created_at,
        updated_at = v_restored_supplier.updated_at,
        default_tax_treatment = v_restored_supplier.default_tax_treatment
    where supplier.tenant_id = p_tenant_id
      and supplier.id = v_restored_supplier.id;

    v_supplier_count := v_supplier_count + 1;
  end loop;

  perform set_config(
    'app.supplier_foundation_invoice_rehydrate_tenant',
    p_tenant_id::text,
    true
  );

  update public.purchase_invoices invoice
  set invoice_number = '__foundation_restore__' || invoice.id::text
  where invoice.tenant_id = p_tenant_id;

  for v_invoice_item in
    select item
    from jsonb_array_elements(v_backup_purchase_invoices) item
    order by item ->> 'id'
  loop
    select invoice.*
    into strict v_current_invoice
    from public.purchase_invoices invoice
    where invoice.tenant_id = p_tenant_id
      and invoice.id = (v_invoice_item ->> 'id')::uuid
    for update;

    v_restored_invoice := jsonb_populate_record(
      v_current_invoice,
      v_invoice_item - array[
        'id', 'tenant_id', 'received_tax_document_id'
      ]
    );

    update public.purchase_invoices invoice
    set invoice_number = v_restored_invoice.invoice_number,
        supplier_id = v_restored_invoice.supplier_id,
        supplier_name = v_restored_invoice.supplier_name,
        supplier_rut = v_restored_invoice.supplier_rut,
        date = v_restored_invoice.date,
        due_date = v_restored_invoice.due_date,
        reference = v_restored_invoice.reference,
        notes = v_restored_invoice.notes,
        status = v_restored_invoice.status,
        subtotal = v_restored_invoice.subtotal,
        tax = v_restored_invoice.tax,
        iva_amount = v_restored_invoice.iva_amount,
        total = v_restored_invoice.total,
        paid_amount = v_restored_invoice.paid_amount,
        balance = v_restored_invoice.balance,
        prepayment_model = v_restored_invoice.prepayment_model,
        items = v_restored_invoice.items,
        additional_costs = v_restored_invoice.additional_costs,
        sent_date = v_restored_invoice.sent_date,
        confirmed_date = v_restored_invoice.confirmed_date,
        received_date = v_restored_invoice.received_date,
        paid_date = v_restored_invoice.paid_date,
        supplier_invoice_number = v_restored_invoice.supplier_invoice_number,
        supplier_invoice_date = v_restored_invoice.supplier_invoice_date,
        created_at = v_restored_invoice.created_at,
        updated_at = v_restored_invoice.updated_at,
        tax_treatment = v_restored_invoice.tax_treatment,
        net_amount = v_restored_invoice.net_amount,
        discount_amount = v_restored_invoice.discount_amount,
        created_by = v_restored_invoice.created_by
    where invoice.tenant_id = p_tenant_id
      and invoice.id = v_restored_invoice.id;

    -- Normalized lines are a deterministic projection of the legacy JSON and
    -- are not part of the legacy backup payload. Rebuild that projection
    -- explicitly while every inventory/journal trigger remains suppressed.
    perform public.sync_purchase_invoice_lines_from_legacy_json(
      v_restored_invoice.id,
      'legacy_json'
    );

    v_invoice_count := v_invoice_count + 1;
  end loop;

  perform set_config(
    'app.supplier_foundation_invoice_rehydrate_tenant',
    '',
    true
  );

  select count(*)::integer
  into v_credential_count
  from public.supplier_credentials credential
  where credential.tenant_id = p_tenant_id;

  update public.database_backups backup
  set status = 'restored',
      restored_at = clock_timestamp(),
      restored_by = auth.uid()
  where backup.id = p_backup_id
    and backup.tenant_id = p_tenant_id;

  return (v_result - 'backup_id') || jsonb_build_object(
    'backup_id', p_backup_id,
    'foundation_safe', true,
    'foundation_restore_mode', 'same_durable_identity_set',
    'supplier_rows_restored_in_place', v_supplier_count,
    'purchase_invoice_rows_restored_in_place', v_invoice_count,
    'supplier_credentials_preserved_count', v_credential_count
  );
end;
$$;

revoke all on function public.restore_backup_internal(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.restore_backup_internal(uuid, uuid)
  to service_role;

create or replace function public.get_supplier_foundation_reset_preflight(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_supplier_count integer;
  v_purchase_invoice_count integer;
  v_expense_count integer;
  v_received_document_count integer;
  v_evidence_count integer;
  v_engagement_count integer;
  v_policy_count integer;
  v_credential_count integer;
  v_credential_event_count integer;
begin
  if v_role <> 'service_role'
     and not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Supplier foundation reset preflight denied'
      using errcode = '42501';
  end if;

  select count(*)::integer into v_supplier_count
  from public.suppliers supplier
  where supplier.tenant_id = p_tenant_id;

  select count(*)::integer into v_purchase_invoice_count
  from public.purchase_invoices invoice
  where invoice.tenant_id = p_tenant_id
    and invoice.supplier_id is not null;

  select count(*)::integer into v_expense_count
  from public.expenses expense
  where expense.tenant_id = p_tenant_id
    and expense.supplier_id is not null;

  select count(*)::integer into v_received_document_count
  from public.received_tax_documents document
  where document.tenant_id = p_tenant_id
    and document.supplier_id is not null;

  select count(*)::integer into v_evidence_count
  from public.supplier_accounting_evidence evidence
  where evidence.tenant_id = p_tenant_id;

  select count(*)::integer into v_engagement_count
  from public.supplier_engagements engagement
  where engagement.tenant_id = p_tenant_id;

  select count(*)::integer into v_policy_count
  from public.supplier_accounting_policies policy
  where policy.tenant_id = p_tenant_id;

  select count(*)::integer into v_credential_count
  from public.supplier_credentials credential
  where credential.tenant_id = p_tenant_id;

  select count(*)::integer into v_credential_event_count
  from public.supplier_credential_access_events event
  where event.tenant_id = p_tenant_id;

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'supported', v_supplier_count = 0,
    'error_code', case when v_supplier_count = 0 then null
      else 'supplier_foundation_reset_requires_domain_operation' end,
    'display_reason', case when v_supplier_count = 0
      then 'No hay relaciones de proveedores que eliminar.'
      else 'El borrado selectivo de proveedores esta deshabilitado porque debe preservar identidades, documentos, evidencia contable y auditoria. Desactiva relaciones individuales o usa una operacion administrativa de dominio revisada.'
    end,
    'required_action', case when v_supplier_count = 0 then null
      else 'disable_selective_supplier_reset' end,
    'blocker_counts', jsonb_build_object(
      'suppliers', v_supplier_count,
      'purchase_invoices', v_purchase_invoice_count,
      'expenses', v_expense_count,
      'received_tax_documents', v_received_document_count,
      'accounting_evidence', v_evidence_count,
      'engagements', v_engagement_count,
      'accounting_policies', v_policy_count,
      'credentials', v_credential_count,
      'credential_audit_events', v_credential_event_count
    )
  );
end;
$$;

revoke all on function public.get_supplier_foundation_reset_preflight(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_supplier_foundation_reset_preflight(uuid)
  to authenticated, service_role;

create or replace function public.redact_supplier_passwords_from_backups(
  p_tenant_id uuid,
  p_backup_ids uuid[] default null,
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt() ->> 'role', auth.role(), '');
  v_candidate_count integer;
  v_nonnull_secret_count integer;
  v_nonnull_sensitive_count integer;
  v_redacted_count integer := 0;
begin
  if v_role <> 'service_role'
     and not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Backup access denied' using errcode = '42501';
  end if;

  select
    count(distinct backup.id)::integer,
    count(*) filter (
      where nullif(supplier_item ->> 'portal_password', '') is not null
    )::integer,
    count(*) filter (
      where nullif(supplier_item ->> 'portal_password', '') is not null
         or nullif(supplier_item ->> 'portal_username', '') is not null
    )::integer
  into
    v_candidate_count,
    v_nonnull_secret_count,
    v_nonnull_sensitive_count
  from public.database_backups backup
  cross join lateral jsonb_array_elements(
    case when jsonb_typeof(backup.backup_data -> 'suppliers') = 'array'
      then backup.backup_data -> 'suppliers'
      else '[]'::jsonb
    end
  ) supplier_item
  where backup.tenant_id = p_tenant_id
    and (p_backup_ids is null or backup.id = any(p_backup_ids))
    and supplier_item ?| array['portal_username', 'portal_password'];

  if not coalesce(p_dry_run, true) then
    with candidates as (
      select backup.id, backup.backup_data
      from public.database_backups backup
      where backup.tenant_id = p_tenant_id
        and (p_backup_ids is null or backup.id = any(p_backup_ids))
        and exists (
          select 1
          from jsonb_array_elements(
            case when jsonb_typeof(
              backup.backup_data -> 'suppliers'
            ) = 'array'
              then backup.backup_data -> 'suppliers'
              else '[]'::jsonb
            end
          ) supplier_item
          where supplier_item ?| array['portal_username', 'portal_password']
        )
    ), sanitized as (
      select
        candidate.id,
        jsonb_set(
          candidate.backup_data,
          '{suppliers}',
          coalesce(
            (
              select jsonb_agg(
                supplier_item -
                  array['portal_username', 'portal_password']
                order by ordinal
              )
              from jsonb_array_elements(
                candidate.backup_data -> 'suppliers'
              ) with ordinality as item(supplier_item, ordinal)
            ),
            '[]'::jsonb
          ),
          true
        ) as payload
      from candidates candidate
    ), redacted as (
      update public.database_backups backup
      set backup_data = sanitized.payload,
          backup_size_bytes = length(sanitized.payload::text)
      from sanitized
      where backup.id = sanitized.id
      returning backup.id
    )
    select count(*)::integer into v_redacted_count from redacted;
  end if;

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'dry_run', coalesce(p_dry_run, true),
    'candidate_backup_count', coalesce(v_candidate_count, 0),
    'nonnull_secret_value_count', coalesce(v_nonnull_secret_count, 0),
    'nonnull_sensitive_value_count', coalesce(v_nonnull_sensitive_count, 0),
    'redacted_backup_count', v_redacted_count
  );
end;
$$;

comment on function public.redact_supplier_passwords_from_backups(
  uuid, uuid[], boolean
) is
  'Guarded historical remediation. Dry-run is the default; applying it removes portal_username and portal_password from supplier snapshots while retaining the backup row and history. Foundation-aware restore preserves the current Vault-backed credential bridge.';

revoke all on function public.redact_supplier_passwords_from_backups(
  uuid, uuid[], boolean
) from public, anon, authenticated, service_role;
grant execute on function public.redact_supplier_passwords_from_backups(
  uuid, uuid[], boolean
) to authenticated, service_role;

-- backup_data contains broad tenant snapshots. Tenant membership alone is not
-- sufficient authority to read or mutate it, even after supplier credential
-- fields are redacted.
alter table public.database_backups enable row level security;
drop policy if exists "backups_select" on public.database_backups;
drop policy if exists "backups_insert" on public.database_backups;
drop policy if exists "backups_update" on public.database_backups;
drop policy if exists "backups_delete" on public.database_backups;
create policy "backups_select"
  on public.database_backups
  for select to authenticated
  using (public.can_manage_tenant_backups(tenant_id));
create policy "backups_insert"
  on public.database_backups
  for insert to authenticated
  with check (public.can_manage_tenant_backups(tenant_id));
create policy "backups_update"
  on public.database_backups
  for update to authenticated
  using (public.can_manage_tenant_backups(tenant_id))
  with check (public.can_manage_tenant_backups(tenant_id));
create policy "backups_delete"
  on public.database_backups
  for delete to authenticated
  using (public.can_manage_tenant_backups(tenant_id));
revoke all on table public.database_backups
  from public, anon, authenticated;
grant select, delete on table public.database_backups to authenticated;

-- ---------------------------------------------------------------------------
-- RLS, grants, timestamps
-- ---------------------------------------------------------------------------

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'external_parties',
    'external_party_identifiers',
    'supplier_role_definitions',
    'supplier_capability_definitions',
    'supplier_tag_definitions',
    'operational_nature_definitions',
    'supplier_relationship_roles',
    'supplier_relationship_capabilities',
    'supplier_relationship_tags',
    'supplier_engagements',
    'supplier_engagement_versions',
    'supplier_accounting_policies',
    'supplier_accounting_policy_versions',
    'supplier_accounting_rules',
    'supplier_classification_candidates',
    'supplier_data_quality_candidates',
    'received_tax_documents',
    'purchase_invoice_lines'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'drop policy if exists %I on public.%I',
      table_name || '_select',
      table_name
    );
    execute format(
      'drop policy if exists %I on public.%I',
      table_name || '_write',
      table_name
    );
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.is_active_tenant_member(tenant_id))',
      table_name || '_select',
      table_name
    );
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant select on table public.%I to authenticated', table_name);
  end loop;

  foreach table_name in array array[
    'business_sites'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'drop policy if exists %I on public.%I',
      table_name || '_select',
      table_name
    );
    execute format(
      'drop policy if exists %I on public.%I',
      table_name || '_write',
      table_name
    );
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.is_active_tenant_member(tenant_id))',
      table_name || '_select',
      table_name
    );
    execute format(
      'create policy %I on public.%I for all to authenticated using (public.can_edit_tenant_settings(tenant_id)) with check (public.can_edit_tenant_settings(tenant_id))',
      table_name || '_write',
      table_name
    );
    execute format(
      'grant select, insert, update, delete on table public.%I to authenticated',
      table_name
    );
  end loop;
end
$$;

alter table public.supplier_accounting_evidence enable row level security;
alter table public.supplier_profile_command_receipts enable row level security;
alter table public.supplier_ocr_template_command_receipts enable row level security;
revoke all on table public.supplier_profile_command_receipts
  from public, anon, authenticated;
revoke all on table public.supplier_ocr_template_command_receipts
  from public, anon, authenticated;
drop policy if exists supplier_accounting_evidence_select
  on public.supplier_accounting_evidence;
drop policy if exists supplier_accounting_evidence_insert
  on public.supplier_accounting_evidence;
create policy supplier_accounting_evidence_select
  on public.supplier_accounting_evidence
  for select to authenticated
  using (public.is_active_tenant_member(tenant_id));
revoke all on table public.supplier_accounting_evidence
  from public, anon, authenticated;
grant select on table public.supplier_accounting_evidence
  to authenticated;

create or replace function public.set_supplier_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  new.updated_at := greatest(
    clock_timestamp(),
    old.updated_at + interval '1 microsecond'
  );
  return new;
end;
$$;

revoke all on function public.set_supplier_updated_at()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_suppliers_updated_at on public.suppliers;
create trigger trg_suppliers_updated_at
  before update on public.suppliers
  for each row
  execute function public.set_supplier_updated_at();

create or replace function public.set_supplier_credential_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  new.updated_at := greatest(
    clock_timestamp(),
    old.updated_at + interval '1 microsecond'
  );
  return new;
end;
$$;

revoke all on function public.set_supplier_credential_updated_at()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_supplier_credentials_updated_at
  on public.supplier_credentials;
create trigger trg_supplier_credentials_updated_at
  before update on public.supplier_credentials
  for each row
  execute function public.set_supplier_credential_updated_at();

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'external_parties',
    'external_party_identifiers',
    'business_sites',
    'supplier_role_definitions',
    'supplier_capability_definitions',
    'supplier_tag_definitions',
    'operational_nature_definitions',
    'supplier_relationship_roles',
    'supplier_relationship_capabilities',
    'supplier_relationship_tags',
    'supplier_engagements',
    'supplier_engagement_versions',
    'supplier_accounting_policies',
    'supplier_accounting_policy_versions',
    'supplier_accounting_rules',
    'supplier_classification_candidates',
    'supplier_data_quality_candidates',
    'received_tax_documents',
    'purchase_invoice_lines'
  ]
  loop
    execute format(
      'drop trigger if exists %I on public.%I',
      'trg_' || table_name || '_updated_at',
      table_name
    );
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
      'trg_' || table_name || '_updated_at',
      table_name
    );
  end loop;
end
$$;

revoke all on function public.normalize_received_tax_document()
  from public, anon, authenticated;
revoke all on function public.prepare_purchase_journal_provenance()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Published, secret-free read projections
-- ---------------------------------------------------------------------------

create or replace function public.has_supplier_portal_credential(
  p_tenant_id uuid,
  p_supplier_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
begin
  if v_role <> 'service_role'
     and not public.is_active_tenant_member(p_tenant_id) then
    return false;
  end if;

  return exists (
    select 1
    from public.supplier_credentials credential
    where credential.tenant_id = p_tenant_id
      and credential.supplier_id = p_supplier_id
      and credential.credential_kind = 'portal_password'
  );
end;
$$;

revoke all on function public.has_supplier_portal_credential(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.has_supplier_portal_credential(uuid, uuid)
  to authenticated, service_role;

create or replace function public.has_supplier_credential_reference(
  p_tenant_id uuid,
  p_supplier_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
begin
  if v_role <> 'service_role'
     and not public.is_active_tenant_member(p_tenant_id) then
    return false;
  end if;

  return exists (
    select 1
    from public.supplier_credentials credential
    where credential.tenant_id = p_tenant_id
      and credential.supplier_id = p_supplier_id
  );
end;
$$;

revoke all on function public.has_supplier_credential_reference(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.has_supplier_credential_reference(uuid, uuid)
  to authenticated, service_role;

create or replace view public.active_business_site_read_model
with (security_invoker = true)
as
select
  site.tenant_id,
  site.id as site_id,
  site.code,
  site.name,
  site.site_kind,
  site.address,
  site.city,
  site.region,
  site.comuna,
  site.country_code,
  site.metadata,
  site.created_at,
  site.updated_at
from public.business_sites site
where site.is_active is true;

comment on view public.active_business_site_read_model is
  'Tenant-RLS-backed active site catalog for engagement selection. Site creation and lifecycle remain owned by the shared business-site workflow, not the supplier relationship aggregate.';

create or replace view public.supplier_profile_read_model
with (security_invoker = true)
as
select
  supplier.tenant_id,
  supplier.id as supplier_id,
  business_date.effective_business_date,
  supplier.party_id,
  coalesce(party.party_kind, 'other') as party_kind,
  coalesce(party.display_name, supplier.name) as display_name,
  coalesce(party.legal_name, supplier.legal_name) as legal_name,
  coalesce(party.trade_name, supplier.trade_name) as trade_name,
  party.country_code,
  party.notes as party_notes,
  coalesce(party.metadata, '{}'::jsonb) as party_metadata,
  identifier.identifier_id as tax_identifier_id,
  identifier.tax_identifier,
  identifier.tax_country_code,
  supplier.is_active,
  supplier.email,
  supplier.phone,
  supplier.website,
  supplier.contact_person,
  supplier.address,
  supplier.city,
  supplier.region,
  supplier.comuna,
  supplier.type as legacy_type,
  supplier.payment_terms,
  supplier.notes,
  supplier.aliases,
  supplier.default_tax_treatment,
  public.has_supplier_portal_credential(
    supplier.tenant_id,
    supplier.id
  ) as has_portal_credential,
  relationship_summary.service_relationship_summary,
  coalesce(roles.items, '[]'::jsonb) as relationship_roles,
  coalesce(capabilities.items, '[]'::jsonb) as relationship_capabilities,
  coalesce(tags.items, '[]'::jsonb) as relationship_tags,
  coalesce(engagements.active_count, 0)::bigint as active_engagement_count,
  coalesce(policies.active_count, 0)::bigint as active_policy_count,
  coalesce(activity.recognized_document_count, 0)::bigint
    as recognized_document_count,
  coalesce(data_issues.pending_count, 0)::bigint
    as validation_issue_count,
  coalesce(data_issues.items, '[]'::jsonb) as validation_incidents,
  case
    when coalesce(data_issues.pending_count, 0) > 0 then 'partial'
    else 'known'
  end::text as data_completeness_status,
  case
    when coalesce(activity.recognized_document_count, 0) = 0
      then 'not_applicable'
    when coalesce(roles.confirmed_count, 0)
       + coalesce(capabilities.confirmed_count, 0)
       + coalesce(tags.confirmed_count, 0) = 0
      then 'unclassified'
    else 'classified'
  end::text as classification_status,
  case
    when coalesce(activity.recognized_document_count, 0) = 0
      then 'not_applicable'
    when coalesce(policies.active_count, 0) = 0 then 'missing_policy'
    else 'configured'
  end::text as accounting_policy_status,
  supplier.created_at,
  supplier.updated_at,
  public.has_supplier_credential_reference(
    supplier.tenant_id,
    supplier.id
  ) as has_credential_reference
from public.suppliers supplier
cross join lateral (
  select public.tenant_business_date(supplier.tenant_id)
    as effective_business_date
) business_date
left join public.external_parties party
  on party.tenant_id = supplier.tenant_id
 and party.id = supplier.party_id
left join lateral (
  select
    id.id as identifier_id,
    coalesce(id.display_value, id.normalized_value) as tax_identifier,
    id.country_code as tax_country_code
  from public.external_party_identifiers id
  where id.tenant_id = supplier.tenant_id
    and id.party_id = supplier.party_id
    and id.identifier_kind = 'tax_id'
    and id.valid_from <= business_date.effective_business_date
    and (
      id.valid_to is null
      or id.valid_to >= business_date.effective_business_date
    )
  order by id.is_primary desc, id.valid_from desc, id.id
  limit 1
) identifier on true
left join lateral (
  select
    jsonb_agg(
      jsonb_build_object(
        'id', role.id,
        'definition_id', definition.id,
        'code', role.role_code,
        'label', definition.label,
        'valid_from', role.valid_from,
        'valid_to', role.valid_to,
        'source', role.assignment_source,
        'metadata', role.metadata
      ) order by role.role_code
    ) as items,
    count(*) as confirmed_count
  from public.supplier_relationship_roles role
  join public.supplier_role_definitions definition
    on definition.tenant_id = role.tenant_id
   and definition.code = role.role_code
  where role.tenant_id = supplier.tenant_id
    and role.supplier_id = supplier.id
    and role.assignment_source <> 'observed'
    and role.valid_from <= business_date.effective_business_date
    and (
      role.valid_to is null
      or role.valid_to >= business_date.effective_business_date
    )
) roles on true
left join lateral (
  select
    jsonb_agg(
      jsonb_build_object(
        'id', capability.id,
        'definition_id', definition.id,
        'code', capability.capability_code,
        'label', definition.label,
        'valid_from', capability.valid_from,
        'valid_to', capability.valid_to,
        'source', capability.assignment_source,
        'metadata', capability.metadata
      ) order by capability.capability_code
    ) as items,
    count(*) as confirmed_count
  from public.supplier_relationship_capabilities capability
  join public.supplier_capability_definitions definition
    on definition.tenant_id = capability.tenant_id
   and definition.code = capability.capability_code
  where capability.tenant_id = supplier.tenant_id
    and capability.supplier_id = supplier.id
    and capability.assignment_source <> 'observed'
    and capability.valid_from <= business_date.effective_business_date
    and (
      capability.valid_to is null
      or capability.valid_to >= business_date.effective_business_date
    )
) capabilities on true
left join lateral (
  select
    jsonb_agg(
      jsonb_build_object(
        'id', tag.id,
        'definition_id', definition.id,
        'code', tag.tag_code,
        'label', definition.label,
        'valid_from', tag.valid_from,
        'valid_to', tag.valid_to,
        'source', tag.assignment_source,
        'metadata', tag.metadata
      ) order by definition.label, tag.tag_code
    ) as items,
    count(*) as confirmed_count
  from public.supplier_relationship_tags tag
  join public.supplier_tag_definitions definition
    on definition.tenant_id = tag.tenant_id
   and definition.code = tag.tag_code
  where tag.tenant_id = supplier.tenant_id
    and tag.supplier_id = supplier.id
    and tag.assignment_source <> 'observed'
    and tag.valid_from <= business_date.effective_business_date
    and (
      tag.valid_to is null
      or tag.valid_to >= business_date.effective_business_date
    )
) tags on true
left join lateral (
  select case
    when summary.relationship_count = 0 then null
    when summary.relationship_count = 1 then summary.first_label
    else summary.first_label || ' y ' ||
      (summary.relationship_count - 1)::text || ' más'
  end::text as service_relationship_summary
  from (
    select
      count(*)::integer as relationship_count,
      (array_agg(
        engagement.name || case when site.id is null
          then '' else ' · ' || site.name end
        order by engagement.name, engagement.id
      ))[1] as first_label
    from public.supplier_engagements engagement
    left join public.business_sites site
      on site.tenant_id = engagement.tenant_id
     and site.id = engagement.site_id
    where engagement.tenant_id = supplier.tenant_id
      and engagement.supplier_id = supplier.id
      and engagement.status = 'active'
      and (
        engagement.starts_on is null
        or engagement.starts_on <= business_date.effective_business_date
      )
      and (
        engagement.ends_on is null
        or engagement.ends_on >= business_date.effective_business_date
      )
      and exists (
        select 1
        from public.supplier_engagement_versions version
        where version.tenant_id = engagement.tenant_id
          and version.engagement_id = engagement.id
          and version.effective_from <= business_date.effective_business_date
          and (
            version.effective_to is null
            or version.effective_to >= business_date.effective_business_date
          )
      )
  ) summary
) relationship_summary on true
left join lateral (
  select count(*) as active_count
  from public.supplier_engagements engagement
  where engagement.tenant_id = supplier.tenant_id
    and engagement.supplier_id = supplier.id
    and engagement.status = 'active'
    and (
      engagement.starts_on is null
      or engagement.starts_on <= business_date.effective_business_date
    )
    and (
      engagement.ends_on is null
      or engagement.ends_on >= business_date.effective_business_date
    )
    and exists (
      select 1
      from public.supplier_engagement_versions version
      where version.tenant_id = engagement.tenant_id
        and version.engagement_id = engagement.id
        and version.effective_from <= business_date.effective_business_date
        and (
          version.effective_to is null
          or version.effective_to >= business_date.effective_business_date
        )
    )
) engagements on true
left join lateral (
  select count(*) as active_count
  from public.supplier_accounting_policies policy
  where policy.tenant_id = supplier.tenant_id
    and policy.supplier_id = supplier.id
    and policy.status = 'active'
    and exists (
      select 1
      from public.supplier_accounting_policy_versions version
      where version.tenant_id = policy.tenant_id
        and version.policy_id = policy.id
        and version.effective_from <= business_date.effective_business_date
        and (
          version.effective_to is null
          or version.effective_to >= business_date.effective_business_date
        )
    )
) policies on true
left join lateral (
  select (
    select count(*)
    from public.purchase_invoices invoice
    where invoice.tenant_id = supplier.tenant_id
      and invoice.supplier_id = supplier.id
      and invoice.status in ('confirmed', 'received', 'paid')
  ) + (
    select count(*)
    from public.expenses expense
    where expense.tenant_id = supplier.tenant_id
      and expense.supplier_id = supplier.id
      and expense.posting_status = 'posted'
  ) as recognized_document_count
) activity on true
left join lateral (
  select
    count(*) as pending_count,
    jsonb_agg(
      jsonb_build_object(
        'code', candidate.issue_code,
        'severity', candidate.severity,
        'scope_type', candidate.scope_type,
        'scope_id', coalesce(candidate.scope_id, candidate.supplier_id),
        'related_code', candidate.related_code,
        'field_key', candidate.field_key,
        'display_reason', candidate.display_reason,
        'source', candidate.issue_source,
        'status', candidate.status
      ) order by candidate.severity desc, candidate.issue_code,
        candidate.id
    ) as items
  from public.supplier_data_quality_candidates candidate
  where candidate.tenant_id = supplier.tenant_id
    and candidate.supplier_id = supplier.id
    and candidate.status = 'pending'
) data_issues on true;

comment on view public.supplier_profile_read_model is
  'Secret-free supplier profile projection. It publishes the tenant effective business date, excludes observed evidence from current editable classifications, and deliberately excludes legacy portal_password, Vault ids, and decrypted credentials.';

create or replace view public.supplier_economic_read_model
with (security_invoker = true)
as
select
  invoice.tenant_id,
  invoice.supplier_id,
  supplier.party_id,
  'purchase_invoice'::text as event_type,
  invoice.id as event_id,
  invoice.date as event_date,
  invoice.invoice_number as document_number,
  invoice.status as event_status,
  case
    when invoice.status = 'cancelled' then 'void'
    when invoice.status not in ('confirmed', 'received', 'paid')
      then 'not_recognized'
    when settlement.effective_total <= 0 then 'no_balance'
    when settlement.balance_amount <= 0.01
      and (payment.paid_amount > 0
        or credit.credited_amount >= invoice.total) then 'paid'
    when settlement.net_paid_amount > 0 then 'partial'
    else 'pending'
  end::text as payment_status,
  'CLP'::text as currency_code,
  settlement.effective_total::numeric(14,2) as gross_amount,
  settlement.net_paid_amount::numeric(14,2) as paid_amount,
  case
    when invoice.status in ('confirmed', 'received', 'paid')
      then settlement.balance_amount::numeric(14,2)
    else null
  end as balance_amount,
  (payment.payment_count + refund.refund_count)::bigint as payment_count,
  invoice.status in ('confirmed', 'received', 'paid') as is_recognized,
  case
    when invoice.status not in ('confirmed', 'received', 'paid')
      then 'not_recognized'
    when payment.paid_amount < 0
      or credit.credited_amount < 0
      or refund.refunded_amount < 0
      or abs(coalesce(invoice.paid_amount, 0) - payment.paid_amount) > 0.01
      or abs(
        coalesce(invoice.credited_amount, 0) - credit.credited_amount
      ) > 0.01
      or abs(
        coalesce(invoice.supplier_refunded_amount, 0) -
        refund.refunded_amount
      ) > 0.01
      or abs(
        coalesce(invoice.balance, 0) -
        settlement.balance_amount
      ) > 0.01
      or lines.unclassified_line_count > 0
      then 'needs_review'
    else 'complete'
  end::text as data_quality_status,
  invoice.id as source_document_id,
  jsonb_build_object(
    'received_tax_document_id', invoice.received_tax_document_id,
    'stored_paid_amount', invoice.paid_amount,
    'stored_credited_amount', invoice.credited_amount,
    'stored_refunded_amount', invoice.supplier_refunded_amount,
    'stored_balance_amount', invoice.balance,
    'gross_payment_amount', payment.paid_amount,
    'credited_amount', credit.credited_amount,
    'refunded_amount', refund.refunded_amount,
    'derived_net_paid_amount', settlement.net_paid_amount,
    'derived_effective_total', settlement.effective_total,
    'derived_balance_amount',
      case when invoice.status in ('confirmed', 'received', 'paid')
        then settlement.balance_amount
        else null end,
    'unclassified_line_count', lines.unclassified_line_count,
    'has_journal_provenance', provenance.has_provenance
  ) as metadata
from public.purchase_invoices invoice
join public.suppliers supplier
  on supplier.tenant_id = invoice.tenant_id
 and supplier.id = invoice.supplier_id
left join lateral (
  select
    count(*)::bigint as payment_count,
    coalesce(sum(purchase_payment.amount), 0)::numeric(14,2)
      as paid_amount
  from public.purchase_payments purchase_payment
  where purchase_payment.tenant_id = invoice.tenant_id
    and purchase_payment.invoice_id = invoice.id
    and purchase_payment.deleted_at is null
) payment on true
left join lateral (
  select
    count(*)::bigint as credit_note_count,
    coalesce(sum(note.total_amount), 0)::numeric(14,2)
      as credited_amount
  from public.purchase_credit_notes note
  where note.tenant_id = invoice.tenant_id
    and note.purchase_invoice_id = invoice.id
    and note.status = 'posted'
) credit on true
left join lateral (
  select
    count(*)::bigint as refund_count,
    coalesce(sum(refund_row.amount), 0)::numeric(14,2)
      as refunded_amount
  from public.purchase_supplier_refunds refund_row
  where refund_row.tenant_id = invoice.tenant_id
    and refund_row.purchase_invoice_id = invoice.id
    and refund_row.status = 'posted'
) refund on true
left join lateral (
  select
    greatest(invoice.total - credit.credited_amount, 0)::numeric(14,2)
      as effective_total,
    greatest(payment.paid_amount - refund.refunded_amount, 0)::numeric(14,2)
      as net_paid_amount,
    greatest(
      greatest(invoice.total - credit.credited_amount, 0) -
      greatest(payment.paid_amount - refund.refunded_amount, 0),
      0
    )::numeric(14,2) as balance_amount
) settlement on true
left join lateral (
  select count(*)::bigint as unclassified_line_count
  from public.purchase_invoice_lines line
  where line.tenant_id = invoice.tenant_id
    and line.purchase_invoice_id = invoice.id
    and line.classification_status = 'needs_review'
) lines on true
left join lateral (
  select exists (
    select 1
    from public.journal_entries entry
    where entry.tenant_id = invoice.tenant_id
      and entry.source_document_type = 'purchase_invoice'
      and entry.source_document_id = invoice.id
      and entry.status = 'posted'
  ) as has_provenance
) provenance on true
where invoice.supplier_id is not null

union all

select
  expense.tenant_id,
  expense.supplier_id,
  supplier.party_id,
  'expense'::text,
  expense.id,
  expense.issue_date,
  expense.expense_number,
  expense.posting_status,
  case
    when expense.posting_status = 'void' then 'void'
    when expense.posting_status <> 'posted' then 'not_recognized'
    when expense.total_amount <= 0 then 'no_balance'
    when expense.amount_paid + 0.01 >= expense.total_amount then 'paid'
    when expense.amount_paid > 0 then 'partial'
    else 'pending'
  end::text,
  expense.currency,
  expense.total_amount::numeric(14,2),
  expense.amount_paid::numeric(14,2),
  case
    when expense.posting_status = 'posted'
      then expense.balance::numeric(14,2)
    else null
  end,
  payment.payment_count,
  expense.posting_status = 'posted',
  case
    when expense.posting_status <> 'posted' then 'not_recognized'
    when expense.approval_status <> 'approved'
      or expense.amount_paid < 0
      or expense.amount_paid > expense.total_amount + 0.01
      or abs(coalesce(expense.amount_paid, 0) - payment.paid_amount) > 0.01
      or abs(
        coalesce(expense.balance, 0) -
        greatest(expense.total_amount - expense.amount_paid, 0)
      ) > 0.01
      then 'needs_review'
    else 'complete'
  end::text,
  expense.id,
  jsonb_build_object(
    'approval_status', expense.approval_status,
    'document_type', expense.document_type,
    'stored_payment_status', expense.payment_status,
    'stored_paid_amount', expense.amount_paid,
    'stored_balance_amount', expense.balance,
    'payment_row_amount', payment.paid_amount,
    'payment_ledger_coverage',
      case when abs(coalesce(expense.amount_paid, 0) - payment.paid_amount)
        <= 0.01 then 'complete' else 'legacy_projection' end,
    'has_journal_provenance', provenance.has_provenance
  )
from public.expenses expense
join public.suppliers supplier
  on supplier.tenant_id = expense.tenant_id
 and supplier.id = expense.supplier_id
left join lateral (
  select
    count(*)::bigint as payment_count,
    coalesce(sum(expense_payment.amount), 0)::numeric(14,2)
      as paid_amount
  from public.expense_payments expense_payment
  where expense_payment.tenant_id = expense.tenant_id
    and expense_payment.expense_id = expense.id
) payment on true
left join lateral (
  select exists (
    select 1
    from public.journal_entries entry
    where entry.tenant_id = expense.tenant_id
      and entry.source_document_type = 'expense'
      and entry.source_document_id = expense.id
      and entry.status = 'posted'
  ) as has_provenance
) provenance on true
where expense.supplier_id is not null

union all

select
  payment.tenant_id,
  invoice.supplier_id,
  supplier.party_id,
  'purchase_payment'::text,
  payment.id,
  payment.date,
  invoice.invoice_number,
  'recorded'::text,
  'recorded'::text,
  'CLP'::text,
  payment.amount::numeric(14,2),
  payment.amount::numeric(14,2),
  null::numeric(14,2),
  1::bigint,
  true,
  case
    when invoice.status in ('confirmed', 'received', 'paid')
      then 'complete'
    else 'needs_review'
  end::text,
  invoice.id,
  jsonb_build_object(
    'payment_id', payment.id,
    'parent_status', invoice.status
  )
from public.purchase_payments payment
join public.purchase_invoices invoice
  on invoice.tenant_id = payment.tenant_id
 and invoice.id = payment.invoice_id
join public.suppliers supplier
  on supplier.tenant_id = invoice.tenant_id
 and supplier.id = invoice.supplier_id
where invoice.supplier_id is not null
  and payment.deleted_at is null

union all

select
  note.tenant_id,
  invoice.supplier_id,
  supplier.party_id,
  'purchase_credit_note'::text,
  note.id,
  note.issue_date,
  note.credit_note_number,
  note.status,
  case when note.status = 'posted'
    then 'credited' else 'void' end::text,
  'CLP'::text,
  (-note.total_amount)::numeric(14,2),
  0::numeric(14,2),
  null::numeric(14,2),
  0::bigint,
  note.status = 'posted',
  case when note.status <> 'posted' then 'not_recognized'
    when entry.id is null or entry.status <> 'posted' then 'needs_review'
    else 'complete' end::text,
  invoice.id,
  jsonb_build_object(
    'credit_note_id', note.id,
    'journal_entry_id', note.journal_entry_id,
    'official_dte_status', note.official_dte_status
  )
from public.purchase_credit_notes note
join public.purchase_invoices invoice
  on invoice.tenant_id = note.tenant_id
 and invoice.id = note.purchase_invoice_id
join public.suppliers supplier
  on supplier.tenant_id = invoice.tenant_id
 and supplier.id = invoice.supplier_id
left join public.journal_entries entry
  on entry.tenant_id = note.tenant_id
 and entry.id = note.journal_entry_id
where invoice.supplier_id is not null

union all

select
  refund.tenant_id,
  invoice.supplier_id,
  supplier.party_id,
  'purchase_supplier_refund'::text,
  refund.id,
  refund.refunded_at,
  refund.refund_number,
  refund.status,
  case when refund.status = 'posted'
    then 'refunded' else 'void' end::text,
  'CLP'::text,
  refund.amount::numeric(14,2),
  (-refund.amount)::numeric(14,2),
  null::numeric(14,2),
  1::bigint,
  refund.status = 'posted',
  case when refund.status <> 'posted' then 'not_recognized'
    when entry.id is null or entry.status <> 'posted' then 'needs_review'
    else 'complete' end::text,
  invoice.id,
  jsonb_build_object(
    'supplier_refund_id', refund.id,
    'purchase_credit_note_id', refund.purchase_credit_note_id,
    'journal_entry_id', refund.journal_entry_id
  )
from public.purchase_supplier_refunds refund
join public.purchase_invoices invoice
  on invoice.tenant_id = refund.tenant_id
 and invoice.id = refund.purchase_invoice_id
join public.suppliers supplier
  on supplier.tenant_id = invoice.tenant_id
 and supplier.id = invoice.supplier_id
left join public.journal_entries entry
  on entry.tenant_id = refund.tenant_id
 and entry.id = refund.journal_entry_id
where invoice.supplier_id is not null

union all

select
  payment.tenant_id,
  expense.supplier_id,
  supplier.party_id,
  'expense_payment'::text,
  payment.id,
  payment.payment_date,
  expense.expense_number,
  case when payment.reversal_of_id is null
    then 'recorded' else 'reversal' end::text,
  case when payment.reversal_of_id is null
    then 'recorded' else 'compensation' end::text,
  expense.currency,
  payment.amount::numeric(14,2),
  payment.amount::numeric(14,2),
  null::numeric(14,2),
  1::bigint,
  true,
  case when expense.posting_status = 'posted'
    then 'complete' else 'needs_review' end::text,
  expense.id,
  jsonb_build_object(
    'payment_id', payment.id,
    'reversal_of_id', payment.reversal_of_id,
    'parent_posting_status', expense.posting_status
  )
from public.expense_payments payment
join public.expenses expense
  on expense.tenant_id = payment.tenant_id
 and expense.id = payment.expense_id
join public.suppliers supplier
  on supplier.tenant_id = expense.tenant_id
 and supplier.id = expense.supplier_id
where expense.supplier_id is not null;

comment on view public.supplier_economic_read_model is
  'Event timeline. Purchase settlement derives effective total and net paid from active payments, posted credits, and posted supplier refunds. Expense documents temporarily preserve the legacy header projection when payment-row coverage is incomplete and expose that gap as data quality. Draft/cancelled/void documents remain visible but are not recognized monetary facts. Payment, credit, and refund events are never added again to document summary totals.';

create or replace view public.supplier_economic_summary_read_model
with (security_invoker = true)
as
with currency_scope as (
  select
    supplier.tenant_id,
    supplier.id as supplier_id,
    'CLP'::text as currency_code
  from public.suppliers supplier
  union
  select expense.tenant_id, expense.supplier_id, expense.currency
  from public.expenses expense
  where expense.supplier_id is not null
), recognized_documents as (
  select
    event.tenant_id,
    event.supplier_id,
    event.currency_code,
    event.event_type as source_type,
    event.source_document_id as source_id,
    event.gross_amount,
    event.paid_amount,
    event.balance_amount,
    event.payment_count,
    event.data_quality_status,
    coalesce(
      event.metadata->>'payment_ledger_coverage',
      'complete'
    ) as payment_ledger_coverage,
    coalesce((event.metadata->>'has_journal_provenance')::boolean, false)
      as has_provenance
  from public.supplier_economic_read_model event
  where event.event_type in ('purchase_invoice', 'expense')
    and event.is_recognized is true
), document_summary as (
  select
    fact.tenant_id,
    fact.supplier_id,
    fact.currency_code,
    count(*) filter (
      where fact.source_type = 'purchase_invoice'
    )::bigint as purchase_document_count,
    sum(fact.gross_amount) filter (
      where fact.source_type = 'purchase_invoice'
    )::numeric(14,2) as purchase_gross_amount,
    sum(fact.paid_amount) filter (
      where fact.source_type = 'purchase_invoice'
    )::numeric(14,2) as purchase_paid_amount,
    sum(fact.balance_amount) filter (
      where fact.source_type = 'purchase_invoice'
    )::numeric(14,2) as purchase_balance_amount,
    coalesce(sum(fact.payment_count) filter (
      where fact.source_type = 'purchase_invoice'
    ), 0)::bigint as purchase_payment_count,
    count(*) filter (
      where fact.source_type = 'expense'
    )::bigint as expense_document_count,
    sum(fact.gross_amount) filter (
      where fact.source_type = 'expense'
    )::numeric(14,2) as expense_gross_amount,
    sum(fact.paid_amount) filter (
      where fact.source_type = 'expense'
    )::numeric(14,2) as expense_paid_amount,
    sum(fact.balance_amount) filter (
      where fact.source_type = 'expense'
    )::numeric(14,2) as expense_balance_amount,
    coalesce(sum(fact.payment_count) filter (
      where fact.source_type = 'expense'
    ), 0)::bigint as expense_payment_count,
    count(*)::bigint as total_document_count,
    count(*) filter (where fact.has_provenance)::bigint
      as traced_document_count,
    count(*) filter (where not fact.has_provenance)::bigint
      as untraced_document_count,
    count(*) filter (
      where fact.data_quality_status <> 'complete'
    )::bigint as payment_state_anomaly_count,
    count(*) filter (
      where fact.source_type = 'expense'
        and fact.payment_ledger_coverage <> 'complete'
    )::bigint as expense_payment_ledger_gap_document_count
  from recognized_documents fact
  group by fact.tenant_id, fact.supplier_id, fact.currency_code
), lifecycle_summary as (
  select
    event.tenant_id,
    event.supplier_id,
    event.currency_code,
    count(*)::bigint as excluded_lifecycle_document_count
  from public.supplier_economic_read_model event
  where event.event_type in ('purchase_invoice', 'expense')
    and event.is_recognized is false
  group by event.tenant_id, event.supplier_id, event.currency_code
), classification_summary as (
  select
    invoice.tenant_id,
    invoice.supplier_id,
    'CLP'::text as currency_code,
    count(*) filter (
      where line.classification_status = 'needs_review'
    )::bigint as unclassified_line_count
  from public.purchase_invoices invoice
  join public.purchase_invoice_lines line
    on line.tenant_id = invoice.tenant_id
   and line.purchase_invoice_id = invoice.id
  where invoice.supplier_id is not null
    and invoice.status in ('confirmed', 'received', 'paid')
  group by invoice.tenant_id, invoice.supplier_id
), activity as (
  select
    event.tenant_id,
    event.supplier_id,
    event.currency_code,
    max(event.event_date) as last_activity_at
  from public.supplier_economic_read_model event
  group by event.tenant_id, event.supplier_id, event.currency_code
)
select
  scope.tenant_id,
  scope.supplier_id,
  supplier.party_id,
  scope.currency_code,
  coalesce(summary.purchase_document_count, 0)::bigint
    as purchase_document_count,
  summary.purchase_gross_amount,
  summary.purchase_paid_amount,
  summary.purchase_balance_amount,
  coalesce(summary.purchase_payment_count, 0)::bigint
    as purchase_payment_count,
  coalesce(summary.expense_document_count, 0)::bigint
    as expense_document_count,
  summary.expense_gross_amount,
  summary.expense_paid_amount,
  summary.expense_balance_amount,
  coalesce(summary.expense_payment_count, 0)::bigint
    as expense_payment_count,
  (
    coalesce(summary.purchase_payment_count, 0) +
    coalesce(summary.expense_payment_count, 0)
  )::bigint as payment_count,
  coalesce(summary.total_document_count, 0)::bigint
    as total_document_count,
  coalesce(summary.traced_document_count, 0)::bigint
    as traced_document_count,
  coalesce(summary.untraced_document_count, 0)::bigint
    as untraced_document_count,
  coalesce(classification.unclassified_line_count, 0)::bigint
    as unclassified_line_count,
  coalesce(summary.payment_state_anomaly_count, 0)::bigint
    as payment_state_anomaly_count,
  coalesce(summary.expense_payment_ledger_gap_document_count, 0)::bigint
    as expense_payment_ledger_gap_document_count,
  coalesce(lifecycle.excluded_lifecycle_document_count, 0)::bigint
    as excluded_lifecycle_document_count,
  case
    when coalesce(summary.total_document_count, 0) = 0 then null
    else round(
      summary.traced_document_count::numeric /
      summary.total_document_count::numeric,
      4
    )
  end as provenance_coverage,
  case
    when coalesce(summary.total_document_count, 0) = 0 then 'not_applicable'
    when summary.traced_document_count = summary.total_document_count
      then 'complete'
    when summary.traced_document_count = 0 then 'none'
    else 'partial'
  end::text as provenance_status,
  case
    when coalesce(summary.total_document_count, 0) = 0
      and coalesce(lifecycle.excluded_lifecycle_document_count, 0) > 0
      then 'lifecycle_only'
    when coalesce(summary.total_document_count, 0) = 0
      then 'not_applicable'
    when coalesce(summary.payment_state_anomaly_count, 0) > 0
      or coalesce(classification.unclassified_line_count, 0) > 0
      then 'needs_review'
    else 'complete'
  end::text as data_quality_status,
  activity.last_activity_at
from currency_scope scope
join public.suppliers supplier
  on supplier.tenant_id = scope.tenant_id
 and supplier.id = scope.supplier_id
left join document_summary summary
  on summary.tenant_id = scope.tenant_id
 and summary.supplier_id = scope.supplier_id
 and summary.currency_code = scope.currency_code
left join lifecycle_summary lifecycle
  on lifecycle.tenant_id = scope.tenant_id
 and lifecycle.supplier_id = scope.supplier_id
 and lifecycle.currency_code = scope.currency_code
left join classification_summary classification
  on classification.tenant_id = scope.tenant_id
 and classification.supplier_id = scope.supplier_id
 and classification.currency_code = scope.currency_code
left join activity
  on activity.tenant_id = scope.tenant_id
 and activity.supplier_id = scope.supplier_id
 and activity.currency_code = scope.currency_code;

comment on view public.supplier_economic_summary_read_model is
  'Authoritative per-supplier/currency summary of recognized documents only. Purchases and expenses remain separate monetary universes; payment events affect activity but are not summed into document totals. Null monetary aggregates distinguish no recognized facts from real zero amounts.';

create or replace function public.save_supplier_relationship_profile(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_expected_updated_at timestamptz,
  p_profile jsonb,
  p_roles jsonb,
  p_capabilities jsonb,
  p_tags jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_supplier public.suppliers%rowtype;
  v_supplier_id uuid := coalesce(p_supplier_id, gen_random_uuid());
  v_display_name text := btrim(coalesce(p_profile->>'display_name', ''));
  v_item jsonb;
  v_code text;
  v_assignment_id uuid;
  v_metadata jsonb;
  v_definition_label text;
  v_tax_value text;
  v_tax_country text;
  v_tax_normalized text;
  v_identifier_id uuid;
  v_identifier_party_id uuid;
  v_result jsonb;
  v_operation_id uuid := nullif(p_profile->>'operation_id', '')::uuid;
  v_request_fingerprint text;
  v_receipt public.supplier_profile_command_receipts%rowtype;
  v_business_date date;
begin
  if v_role <> 'service_role'
     and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required'
      using errcode = '42501';
  end if;

  if jsonb_typeof(p_profile) <> 'object'
     or jsonb_typeof(coalesce(p_roles, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_capabilities, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_tags, '[]'::jsonb)) <> 'array' then
    raise exception 'Profile must be an object and assignments must be arrays'
      using errcode = '22023';
  end if;

  v_business_date := public.tenant_business_date(p_tenant_id);

  if v_operation_id is null then
    raise exception 'Supplier profile operation_id is required'
      using errcode = '22023';
  end if;

  v_request_fingerprint := md5(jsonb_build_object(
    'supplier_id', p_supplier_id,
    'expected_updated_at', p_expected_updated_at,
    'profile', p_profile - 'operation_id',
    'roles', coalesce(p_roles, '[]'::jsonb),
    'capabilities', coalesce(p_capabilities, '[]'::jsonb),
    'tags', coalesce(p_tags, '[]'::jsonb)
  )::text);

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_profile_operation:' || p_tenant_id::text || ':' ||
      v_operation_id::text,
      0
    )
  );

  select receipt.*
  into v_receipt
  from public.supplier_profile_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.operation_id = v_operation_id;

  if found then
    if v_receipt.request_fingerprint <> v_request_fingerprint then
      raise exception 'Supplier profile operation id was reused with different content'
        using errcode = '23505';
    end if;

    select to_jsonb(profile)
    into v_result
    from public.supplier_profile_read_model profile
    where profile.tenant_id = p_tenant_id
      and profile.supplier_id = v_receipt.supplier_id;

    return coalesce(v_result, '{}'::jsonb)
      || jsonb_build_object('idempotent_replay', true);
  end if;

  if p_supplier_id is null and v_display_name = '' then
    raise exception 'Supplier display name is required'
      using errcode = '22023';
  end if;

  if p_profile ? 'website'
     and nullif(btrim(p_profile->>'website'), '') is not null
     and not public.is_safe_https_portal_url(p_profile->>'website')
     and (
       p_supplier_id is null
       or not exists (
         select 1
         from public.suppliers supplier
         where supplier.tenant_id = p_tenant_id
           and supplier.id = p_supplier_id
           and supplier.website is not distinct from
             nullif(btrim(p_profile->>'website'), '')
       )
     ) then
    raise exception 'Supplier website must be a safe HTTPS URL without userinfo, query, or fragment'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_roles, '[]'::jsonb)) item
    group by lower(btrim(item->>'code'))
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_array_elements(coalesce(p_capabilities, '[]'::jsonb)) item
    group by lower(btrim(item->>'code'))
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_array_elements(coalesce(p_tags, '[]'::jsonb)) item
    group by lower(btrim(item->>'code'))
    having count(*) > 1
  ) then
    raise exception 'Duplicate assignment code in profile payload'
      using errcode = '23514';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_profile:' || p_tenant_id::text || ':' ||
      v_supplier_id::text,
      0
    )
  );

  perform set_config(
    'app.supplier_party_sync_guard',
    txid_current()::text || ':' || v_supplier_id::text,
    true
  );

  if p_supplier_id is null then
    insert into public.suppliers (
      id,
      tenant_id,
      name,
      legal_name,
      trade_name,
      aliases,
      rut,
      email,
      phone,
      address,
      city,
      region,
      comuna,
      contact_person,
      website,
      type,
      payment_terms,
      notes,
      is_active,
      default_tax_treatment
    ) values (
      v_supplier_id,
      p_tenant_id,
      v_display_name,
      nullif(btrim(p_profile->>'legal_name'), ''),
      nullif(btrim(p_profile->>'trade_name'), ''),
      case when jsonb_typeof(p_profile->'aliases') = 'array' then array(
        select btrim(value)
        from jsonb_array_elements_text(p_profile->'aliases') value
        where btrim(value) <> ''
      ) else '{}'::text[] end,
      nullif(btrim(p_profile->>'tax_identifier'), ''),
      nullif(btrim(p_profile->>'email'), ''),
      nullif(btrim(p_profile->>'phone'), ''),
      nullif(btrim(p_profile->>'address'), ''),
      nullif(btrim(p_profile->>'city'), ''),
      nullif(btrim(p_profile->>'region'), ''),
      nullif(btrim(p_profile->>'comuna'), ''),
      nullif(btrim(p_profile->>'contact_person'), ''),
      nullif(btrim(p_profile->>'website'), ''),
      coalesce(nullif(btrim(p_profile->>'legacy_type'), ''), 'local'),
      coalesce(nullif(btrim(p_profile->>'payment_terms'), ''), 'net30'),
      nullif(btrim(p_profile->>'notes'), ''),
      coalesce((p_profile->>'is_active')::boolean, true),
      coalesce(
        nullif(btrim(p_profile->>'default_tax_treatment'), ''),
        'no_tax'
      )
    ) returning * into v_supplier;
  else
    select supplier.*
    into v_supplier
    from public.suppliers supplier
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id
    for update;

    if not found then
      raise exception 'Supplier not found in tenant' using errcode = 'P0002';
    end if;

    if v_role <> 'service_role' and p_expected_updated_at is null then
      raise exception 'Expected supplier updated_at is required for update'
        using errcode = '22023';
    end if;

    if p_expected_updated_at is not null
       and v_supplier.updated_at is distinct from p_expected_updated_at then
      raise exception 'Supplier profile changed concurrently'
        using errcode = '40001';
    end if;

    update public.suppliers supplier
    set name = coalesce(nullif(v_display_name, ''), supplier.name),
        legal_name = case when p_profile ? 'legal_name'
          then nullif(btrim(p_profile->>'legal_name'), '')
          else supplier.legal_name end,
        trade_name = case when p_profile ? 'trade_name'
          then nullif(btrim(p_profile->>'trade_name'), '')
          else supplier.trade_name end,
        aliases = case when jsonb_typeof(p_profile->'aliases') = 'array'
          then array(
            select btrim(value)
            from jsonb_array_elements_text(p_profile->'aliases') value
            where btrim(value) <> ''
          ) else supplier.aliases end,
        rut = case when p_profile ? 'tax_identifier'
          then nullif(btrim(p_profile->>'tax_identifier'), '')
          else supplier.rut end,
        email = case when p_profile ? 'email'
          then nullif(btrim(p_profile->>'email'), '') else supplier.email end,
        phone = case when p_profile ? 'phone'
          then nullif(btrim(p_profile->>'phone'), '') else supplier.phone end,
        address = case when p_profile ? 'address'
          then nullif(btrim(p_profile->>'address'), '') else supplier.address end,
        city = case when p_profile ? 'city'
          then nullif(btrim(p_profile->>'city'), '') else supplier.city end,
        region = case when p_profile ? 'region'
          then nullif(btrim(p_profile->>'region'), '') else supplier.region end,
        comuna = case when p_profile ? 'comuna'
          then nullif(btrim(p_profile->>'comuna'), '') else supplier.comuna end,
        contact_person = case when p_profile ? 'contact_person'
          then nullif(btrim(p_profile->>'contact_person'), '')
          else supplier.contact_person end,
        website = case when p_profile ? 'website'
          then nullif(btrim(p_profile->>'website'), '')
          else supplier.website end,
        type = case when p_profile ? 'legacy_type'
          then coalesce(nullif(btrim(p_profile->>'legacy_type'), ''), 'local')
          else supplier.type end,
        payment_terms = case when p_profile ? 'payment_terms'
          then coalesce(
            nullif(btrim(p_profile->>'payment_terms'), ''), 'net30'
          ) else supplier.payment_terms end,
        notes = case when p_profile ? 'notes'
          then nullif(btrim(p_profile->>'notes'), '') else supplier.notes end,
        is_active = case when p_profile ? 'is_active'
          then (p_profile->>'is_active')::boolean else supplier.is_active end,
        default_tax_treatment = case
          when p_profile ? 'default_tax_treatment' then coalesce(
            nullif(btrim(p_profile->>'default_tax_treatment'), ''), 'no_tax'
          ) else supplier.default_tax_treatment end,
        updated_at = clock_timestamp()
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id
    returning * into v_supplier;
  end if;

  update public.external_parties party
  set party_kind = coalesce(
        nullif(lower(btrim(p_profile->>'party_kind')), ''),
        party.party_kind
      ),
      display_name = coalesce(nullif(v_display_name, ''), party.display_name),
      legal_name = case when p_profile ? 'legal_name'
        then nullif(btrim(p_profile->>'legal_name'), '')
        else party.legal_name end,
      trade_name = case when p_profile ? 'trade_name'
        then nullif(btrim(p_profile->>'trade_name'), '')
        else party.trade_name end,
      country_code = case when p_profile ? 'country_code'
        then nullif(upper(btrim(p_profile->>'country_code')), '')
        else party.country_code end,
      is_active = v_supplier.is_active,
      notes = case when p_profile ? 'party_notes'
        then nullif(btrim(p_profile->>'party_notes'), '')
        else party.notes end,
      metadata = case when jsonb_typeof(p_profile->'party_metadata') = 'object'
        then p_profile->'party_metadata' else party.metadata end,
      created_by = coalesce(
        party.created_by,
        case when v_role = 'service_role' then null else auth.uid() end
      ),
      updated_at = clock_timestamp()
  where party.tenant_id = p_tenant_id
    and party.id = v_supplier.party_id;

  perform set_config('app.supplier_party_sync_guard', '', true);

  if p_profile ? 'tax_identifier' then
    v_tax_value := nullif(btrim(p_profile->>'tax_identifier'), '');
    v_tax_country := coalesce(
      nullif(upper(btrim(p_profile->>'tax_country_code')), ''),
      nullif(upper(btrim(p_profile->>'country_code')), ''),
      'CL'
    );

    if v_tax_value is null then
      delete from public.external_party_identifiers identifier
      where identifier.tenant_id = p_tenant_id
        and identifier.party_id = v_supplier.party_id
        and identifier.identifier_kind = 'tax_id'
        and identifier.valid_to is null
        and identifier.valid_from = v_business_date;

      update public.external_party_identifiers identifier
      set valid_to = v_business_date - 1,
          is_primary = false,
          updated_at = clock_timestamp()
      where identifier.tenant_id = p_tenant_id
        and identifier.party_id = v_supplier.party_id
        and identifier.identifier_kind = 'tax_id'
        and identifier.valid_to is null
        and identifier.valid_from < v_business_date;
    else
      v_tax_normalized := lower(regexp_replace(
        v_tax_value,
        '[^0-9A-Za-z]',
        '',
        'g'
      ));

      select identifier.id, identifier.party_id
      into v_identifier_id, v_identifier_party_id
      from public.external_party_identifiers identifier
      where identifier.tenant_id = p_tenant_id
        and identifier.identifier_kind = 'tax_id'
        and identifier.country_code = v_tax_country
        and identifier.normalized_value = v_tax_normalized
        and identifier.valid_to is null
      limit 1;

      if v_identifier_id is not null
         and v_identifier_party_id is distinct from v_supplier.party_id then
        raise exception 'Tax identifier already belongs to another party'
          using errcode = '23505';
      end if;

      delete from public.external_party_identifiers identifier
      where identifier.tenant_id = p_tenant_id
        and identifier.party_id = v_supplier.party_id
        and identifier.identifier_kind = 'tax_id'
        and identifier.valid_to is null
        and identifier.valid_from = v_business_date
        and identifier.id is distinct from v_identifier_id;

      update public.external_party_identifiers identifier
      set valid_to = v_business_date - 1,
          is_primary = false,
          updated_at = clock_timestamp()
      where identifier.tenant_id = p_tenant_id
        and identifier.party_id = v_supplier.party_id
        and identifier.identifier_kind = 'tax_id'
        and identifier.valid_to is null
        and identifier.valid_from < v_business_date
        and identifier.id is distinct from v_identifier_id;

      if v_identifier_id is null then
        insert into public.external_party_identifiers (
          tenant_id,
          party_id,
          identifier_kind,
          country_code,
          normalized_value,
          display_value,
          is_primary,
          valid_from,
          metadata
        ) values (
          p_tenant_id,
          v_supplier.party_id,
          'tax_id',
          v_tax_country,
          v_tax_normalized,
          v_tax_value,
          true,
          v_business_date,
          jsonb_build_object('source', 'supplier_profile_command')
        );
      else
        update public.external_party_identifiers identifier
        set display_value = v_tax_value,
            is_primary = true,
            valid_to = null,
            updated_at = clock_timestamp()
        where identifier.id = v_identifier_id;
      end if;
    end if;
  end if;

  delete from public.supplier_relationship_roles assignment
  where assignment.tenant_id = p_tenant_id
    and assignment.supplier_id = v_supplier_id
    and assignment.assignment_source <> 'observed'
    and assignment.valid_to is null
    and assignment.valid_from = v_business_date
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(p_roles, '[]'::jsonb)) item
      where lower(btrim(item->>'code')) = assignment.role_code
    );

  update public.supplier_relationship_roles assignment
  set valid_to = v_business_date - 1,
      updated_at = clock_timestamp()
  where assignment.tenant_id = p_tenant_id
    and assignment.supplier_id = v_supplier_id
    and assignment.assignment_source <> 'observed'
    and assignment.valid_to is null
    and assignment.valid_from < v_business_date
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(p_roles, '[]'::jsonb)) item
      where lower(btrim(item->>'code')) = assignment.role_code
    );

  for v_item in
    select item from jsonb_array_elements(coalesce(p_roles, '[]'::jsonb)) item
  loop
    v_code := lower(btrim(coalesce(v_item->>'code', '')));
    v_assignment_id := nullif(v_item->>'id', '')::uuid;
    v_metadata := coalesce(v_item->'metadata', '{}'::jsonb);

    if jsonb_typeof(v_metadata) <> 'object'
       or not exists (
         select 1 from public.supplier_role_definitions definition
         where definition.tenant_id = p_tenant_id
           and definition.code = v_code and definition.is_active
       ) then
      raise exception 'Active supplier role definition is required'
        using errcode = '23503';
    end if;

    if v_assignment_id is not null and not exists (
      select 1 from public.supplier_relationship_roles assignment
      where assignment.tenant_id = p_tenant_id
        and assignment.supplier_id = v_supplier_id
        and assignment.id = v_assignment_id
        and assignment.role_code = v_code
        and assignment.assignment_source <> 'observed'
        and assignment.valid_to is null
    ) then
      raise exception 'Supplier role assignment id/code mismatch'
      using errcode = '23514';
    end if;

    if exists (
      select 1
      from public.supplier_relationship_roles assignment
      where assignment.tenant_id = p_tenant_id
        and assignment.supplier_id = v_supplier_id
        and assignment.role_code = v_code
        and assignment.assignment_source = 'observed'
    ) then
      raise exception 'Observed supplier role requires candidate review'
        using errcode = '23514';
    end if;

    update public.supplier_relationship_roles assignment
    set assignment_source = 'manual',
        metadata = v_metadata,
        updated_at = clock_timestamp()
    where assignment.tenant_id = p_tenant_id
      and assignment.supplier_id = v_supplier_id
      and assignment.role_code = v_code
      and assignment.assignment_source <> 'observed'
      and assignment.valid_to is null;

    if not found then
      insert into public.supplier_relationship_roles (
        tenant_id, supplier_id, role_code, valid_from, assignment_source,
        metadata
      ) values (
        p_tenant_id, v_supplier_id, v_code, v_business_date, 'manual', v_metadata
      )
      on conflict (tenant_id, supplier_id, role_code, valid_from)
      do update set valid_to = null,
          assignment_source = 'manual',
          metadata = excluded.metadata,
          updated_at = clock_timestamp();
    end if;
  end loop;

  delete from public.supplier_relationship_capabilities assignment
  where assignment.tenant_id = p_tenant_id
    and assignment.supplier_id = v_supplier_id
    and assignment.assignment_source <> 'observed'
    and assignment.valid_to is null
    and assignment.valid_from = v_business_date
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(p_capabilities, '[]'::jsonb)) item
      where lower(btrim(item->>'code')) = assignment.capability_code
    );

  update public.supplier_relationship_capabilities assignment
  set valid_to = v_business_date - 1,
      updated_at = clock_timestamp()
  where assignment.tenant_id = p_tenant_id
    and assignment.supplier_id = v_supplier_id
    and assignment.assignment_source <> 'observed'
    and assignment.valid_to is null
    and assignment.valid_from < v_business_date
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(p_capabilities, '[]'::jsonb)) item
      where lower(btrim(item->>'code')) = assignment.capability_code
    );

  for v_item in
    select item
    from jsonb_array_elements(coalesce(p_capabilities, '[]'::jsonb)) item
  loop
    v_code := lower(btrim(coalesce(v_item->>'code', '')));
    v_assignment_id := nullif(v_item->>'id', '')::uuid;
    v_metadata := coalesce(v_item->'metadata', '{}'::jsonb);

    if jsonb_typeof(v_metadata) <> 'object'
       or not exists (
         select 1 from public.supplier_capability_definitions definition
         where definition.tenant_id = p_tenant_id
           and definition.code = v_code and definition.is_active
       ) then
      raise exception 'Active supplier capability definition is required'
        using errcode = '23503';
    end if;

    if v_assignment_id is not null and not exists (
      select 1 from public.supplier_relationship_capabilities assignment
      where assignment.tenant_id = p_tenant_id
        and assignment.supplier_id = v_supplier_id
        and assignment.id = v_assignment_id
        and assignment.capability_code = v_code
        and assignment.assignment_source <> 'observed'
        and assignment.valid_to is null
    ) then
      raise exception 'Supplier capability assignment id/code mismatch'
      using errcode = '23514';
    end if;

    if exists (
      select 1
      from public.supplier_relationship_capabilities assignment
      where assignment.tenant_id = p_tenant_id
        and assignment.supplier_id = v_supplier_id
        and assignment.capability_code = v_code
        and assignment.assignment_source = 'observed'
    ) then
      raise exception 'Observed supplier capability requires candidate review'
        using errcode = '23514';
    end if;

    update public.supplier_relationship_capabilities assignment
    set assignment_source = 'manual',
        metadata = v_metadata,
        updated_at = clock_timestamp()
    where assignment.tenant_id = p_tenant_id
      and assignment.supplier_id = v_supplier_id
      and assignment.capability_code = v_code
      and assignment.assignment_source <> 'observed'
      and assignment.valid_to is null;

    if not found then
      insert into public.supplier_relationship_capabilities (
        tenant_id, supplier_id, capability_code, valid_from,
        assignment_source, metadata
      ) values (
        p_tenant_id, v_supplier_id, v_code, v_business_date, 'manual', v_metadata
      )
      on conflict (tenant_id, supplier_id, capability_code, valid_from)
      do update set valid_to = null,
          assignment_source = 'manual',
          metadata = excluded.metadata,
          updated_at = clock_timestamp();
    end if;
  end loop;

  delete from public.supplier_relationship_tags assignment
  where assignment.tenant_id = p_tenant_id
    and assignment.supplier_id = v_supplier_id
    and assignment.assignment_source <> 'observed'
    and assignment.valid_to is null
    and assignment.valid_from = v_business_date
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(p_tags, '[]'::jsonb)) item
      where lower(btrim(item->>'code')) = assignment.tag_code
    );

  update public.supplier_relationship_tags assignment
  set valid_to = v_business_date - 1,
      updated_at = clock_timestamp()
  where assignment.tenant_id = p_tenant_id
    and assignment.supplier_id = v_supplier_id
    and assignment.assignment_source <> 'observed'
    and assignment.valid_to is null
    and assignment.valid_from < v_business_date
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(p_tags, '[]'::jsonb)) item
      where lower(btrim(item->>'code')) = assignment.tag_code
    );

  for v_item in
    select item from jsonb_array_elements(coalesce(p_tags, '[]'::jsonb)) item
  loop
    v_code := lower(btrim(coalesce(v_item->>'code', '')));
    v_assignment_id := nullif(v_item->>'id', '')::uuid;
    v_metadata := coalesce(v_item->'metadata', '{}'::jsonb);

    select definition.label
    into v_definition_label
    from public.supplier_tag_definitions definition
    where definition.tenant_id = p_tenant_id
      and definition.code = v_code
      and definition.is_active;

    if not found or jsonb_typeof(v_metadata) <> 'object' then
      raise exception 'Active supplier tag definition is required'
        using errcode = '23503';
    end if;

    if v_assignment_id is not null and not exists (
      select 1 from public.supplier_relationship_tags assignment
      where assignment.tenant_id = p_tenant_id
        and assignment.supplier_id = v_supplier_id
        and assignment.id = v_assignment_id
        and assignment.tag_code = v_code
        and assignment.assignment_source <> 'observed'
        and assignment.valid_to is null
    ) then
      raise exception 'Supplier tag assignment id/code mismatch'
      using errcode = '23514';
    end if;

    if exists (
      select 1
      from public.supplier_relationship_tags assignment
      where assignment.tenant_id = p_tenant_id
        and assignment.supplier_id = v_supplier_id
        and assignment.tag_code = v_code
        and assignment.assignment_source = 'observed'
    ) then
      raise exception 'Observed supplier tag requires candidate review'
        using errcode = '23514';
    end if;

    update public.supplier_relationship_tags assignment
    set label = v_definition_label,
        assignment_source = 'manual',
        metadata = v_metadata,
        updated_at = clock_timestamp()
    where assignment.tenant_id = p_tenant_id
      and assignment.supplier_id = v_supplier_id
      and assignment.tag_code = v_code
      and assignment.assignment_source <> 'observed'
      and assignment.valid_to is null;

    if not found then
      insert into public.supplier_relationship_tags (
        tenant_id, supplier_id, tag_code, label, valid_from,
        assignment_source, metadata
      ) values (
        p_tenant_id, v_supplier_id, v_code, v_definition_label,
        v_business_date, 'manual', v_metadata
      )
      on conflict (tenant_id, supplier_id, tag_code, valid_from)
      do update set valid_to = null,
          label = excluded.label,
          assignment_source = 'manual',
          metadata = excluded.metadata,
          updated_at = clock_timestamp();
    end if;
  end loop;

  update public.suppliers supplier
  set updated_at = clock_timestamp()
  where supplier.tenant_id = p_tenant_id
    and supplier.id = v_supplier_id;

  insert into public.supplier_profile_command_receipts (
    tenant_id,
    operation_id,
    supplier_id,
    request_fingerprint
  ) values (
    p_tenant_id,
    v_operation_id,
    v_supplier_id,
    v_request_fingerprint
  );

  select to_jsonb(profile)
  into v_result
  from public.supplier_profile_read_model profile
  where profile.tenant_id = p_tenant_id
    and profile.supplier_id = v_supplier_id;

  return v_result;
end;
$$;

revoke all on function public.save_supplier_relationship_profile(
  uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.save_supplier_relationship_profile(
  uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb
) to authenticated, service_role;

create or replace function public.update_supplier_ocr_template(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_expected_updated_at timestamptz,
  p_operation_id uuid,
  p_ocr_template jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_supplier public.suppliers%rowtype;
  v_receipt public.supplier_ocr_template_command_receipts%rowtype;
  v_request_fingerprint text;
  v_result jsonb;
begin
  if v_role <> 'service_role'
     and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required'
      using errcode = '42501';
  end if;

  if p_operation_id is null then
    raise exception 'OCR template operation_id is required'
      using errcode = '22023';
  end if;

  if v_role <> 'service_role' and p_expected_updated_at is null then
    raise exception 'Expected supplier updated_at is required for OCR template update'
      using errcode = '22023';
  end if;

  if jsonb_typeof(p_ocr_template) is distinct from 'object' then
    raise exception 'OCR template must be an object'
      using errcode = '22023';
  end if;

  if public.jsonb_contains_sensitive_key(p_ocr_template) then
    raise exception 'OCR template must not contain sensitive keys'
      using errcode = '22023';
  end if;

  if not (p_ocr_template ?& array['enabled', 'discount_parser'])
     or exists (
       select 1
       from jsonb_object_keys(p_ocr_template) key
       where key not in ('enabled', 'discount_parser')
     ) then
    raise exception 'OCR template requires only enabled and discount_parser'
      using errcode = '22023';
  end if;

  if jsonb_typeof(p_ocr_template->'enabled') is distinct from 'boolean'
     or jsonb_typeof(p_ocr_template->'discount_parser') is distinct from 'string'
     or p_ocr_template->>'discount_parser' not in (
       'none', 'anchoredTrailingNumeric'
     ) then
    raise exception 'OCR template enabled and discount_parser are invalid'
      using errcode = '22023';
  end if;

  v_request_fingerprint := md5(jsonb_build_object(
    'supplier_id', p_supplier_id,
    'expected_updated_at', p_expected_updated_at,
    'ocr_template', p_ocr_template
  )::text);

  -- The supplier shell is the first durable row lock for every profile writer.
  select supplier.*
  into v_supplier
  from public.suppliers supplier
  where supplier.tenant_id = p_tenant_id
    and supplier.id = p_supplier_id
  for update;

  if not found then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'supplier_ocr_template_operation:' || p_tenant_id::text || ':' ||
      p_operation_id::text,
    0
  ));

  select receipt.*
  into v_receipt
  from public.supplier_ocr_template_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.operation_id = p_operation_id;

  if found then
    if v_receipt.supplier_id <> p_supplier_id
       or v_receipt.request_fingerprint <> v_request_fingerprint then
      raise exception 'OCR template operation id was reused with different content'
        using errcode = '23505';
    end if;

    return v_receipt.result || jsonb_build_object(
      'idempotent_replay', true
    );
  end if;

  if p_expected_updated_at is not null
     and v_supplier.updated_at is distinct from p_expected_updated_at then
    raise exception 'Supplier changed concurrently'
      using errcode = '40001';
  end if;

  update public.suppliers supplier
  set ocr_template = p_ocr_template,
      updated_at = greatest(
        clock_timestamp(),
        supplier.updated_at + interval '1 microsecond'
      )
  where supplier.tenant_id = p_tenant_id
    and supplier.id = p_supplier_id
  returning * into v_supplier;

  v_result := jsonb_build_object(
    'tenant_id', p_tenant_id,
    'supplier_id', p_supplier_id,
    'operation_id', p_operation_id,
    'updated_at', v_supplier.updated_at,
    'ocr_template', v_supplier.ocr_template,
    'idempotent_replay', false
  );

  insert into public.supplier_ocr_template_command_receipts (
    tenant_id,
    operation_id,
    supplier_id,
    request_fingerprint,
    result,
    actor_id
  ) values (
    p_tenant_id,
    p_operation_id,
    p_supplier_id,
    v_request_fingerprint,
    v_result,
    case when v_role = 'service_role' then null else auth.uid() end
  );

  return v_result;
end;
$$;

revoke all on function public.update_supplier_ocr_template(
  uuid, uuid, timestamptz, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.update_supplier_ocr_template(
  uuid, uuid, timestamptz, uuid, jsonb
) to authenticated, service_role;

create or replace function public.create_supplier_engagement(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_engagement jsonb,
  p_initial_version jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_engagement public.supplier_engagements%rowtype;
  v_version public.supplier_engagement_versions%rowtype;
  v_current_version public.supplier_engagement_versions%rowtype;
  v_code text := btrim(coalesce(p_engagement->>'code', ''));
  v_operation_id uuid := nullif(p_engagement->>'operation_id', '')::uuid;
  v_request_fingerprint text;
  v_effective_from date := nullif(
    p_initial_version->>'effective_from', ''
  )::date;
  v_business_date date;
begin
  if v_role <> 'service_role'
     and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required'
      using errcode = '42501';
  end if;

  if v_role <> 'service_role' then
    v_business_date := public.tenant_business_date(p_tenant_id);
  end if;

  if not exists (
    select 1 from public.suppliers supplier
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id
  ) then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  if jsonb_typeof(coalesce(p_engagement->'metadata', '{}'::jsonb))
       <> 'object'
     or jsonb_typeof(coalesce(p_initial_version->'terms', '{}'::jsonb))
       <> 'object'
     or v_effective_from is null
     or v_operation_id is null then
    raise exception 'Engagement metadata, terms, and effective_from are required'
      using errcode = '22023';
  end if;

  v_request_fingerprint := md5(jsonb_build_object(
    'supplier_id', p_supplier_id,
    'engagement', p_engagement - 'operation_id',
    'initial_version', p_initial_version
  )::text);

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_engagement_operation:' || p_tenant_id::text || ':' ||
      v_operation_id::text,
      0
    )
  );

  select engagement.*
  into v_engagement
  from public.supplier_engagements engagement
  where engagement.tenant_id = p_tenant_id
    and engagement.operation_id = v_operation_id
  for update;

  if found then
    if v_engagement.request_fingerprint <> v_request_fingerprint then
      raise exception 'Engagement operation id was reused with different content'
        using errcode = '23505';
    end if;

    select version.*
    into v_version
    from public.supplier_engagement_versions version
    where version.tenant_id = p_tenant_id
      and version.engagement_id = v_engagement.id
      and version.operation_id = v_operation_id;

    select version.*
    into v_current_version
    from public.supplier_engagement_versions version
    where version.tenant_id = p_tenant_id
      and version.engagement_id = v_engagement.id
      and version.effective_to is null;

    return jsonb_build_object(
      'engagement', to_jsonb(v_engagement),
      'applied_version', to_jsonb(v_version),
      'current_version', to_jsonb(v_current_version),
      'idempotent_replay', true
    );
  end if;

  if v_role <> 'service_role'
     and v_effective_from < v_business_date then
    raise exception 'Engagement effective_from cannot precede tenant business date'
      using errcode = '23514';
  end if;

  insert into public.supplier_engagements (
    tenant_id,
    supplier_id,
    site_id,
    engagement_kind,
    code,
    name,
    status,
    starts_on,
    ends_on,
    operation_id,
    request_fingerprint,
    metadata
  ) values (
    p_tenant_id,
    p_supplier_id,
    nullif(p_engagement->>'site_id', '')::uuid,
    lower(btrim(coalesce(p_engagement->>'engagement_kind', ''))),
    v_code,
    btrim(coalesce(p_engagement->>'name', '')),
    lower(btrim(coalesce(p_engagement->>'status', 'draft'))),
    nullif(p_engagement->>'starts_on', '')::date,
    nullif(p_engagement->>'ends_on', '')::date,
    v_operation_id,
    v_request_fingerprint,
    coalesce(p_engagement->'metadata', '{}'::jsonb)
  ) returning * into v_engagement;

  insert into public.supplier_engagement_versions (
    tenant_id,
    engagement_id,
    version_number,
    effective_from,
    external_reference,
    service_identifier,
    billing_cycle,
    currency_code,
    expected_amount,
    due_day,
    portal_url,
    operation_id,
    request_fingerprint,
    terms,
    created_by
  ) values (
    p_tenant_id,
    v_engagement.id,
    1,
    v_effective_from,
    nullif(btrim(p_initial_version->>'external_reference'), ''),
    nullif(btrim(p_initial_version->>'service_identifier'), ''),
    lower(btrim(coalesce(p_initial_version->>'billing_cycle', 'none'))),
    upper(btrim(coalesce(p_initial_version->>'currency_code', 'CLP'))),
    nullif(p_initial_version->>'expected_amount', '')::numeric,
    nullif(p_initial_version->>'due_day', '')::integer,
    nullif(btrim(p_initial_version->>'portal_url'), ''),
    v_operation_id,
    v_request_fingerprint,
    coalesce(p_initial_version->'terms', '{}'::jsonb),
    case when v_role = 'service_role' then null else auth.uid() end
  ) returning * into v_version;

  return jsonb_build_object(
    'engagement', to_jsonb(v_engagement),
    'applied_version', to_jsonb(v_version),
    'current_version', to_jsonb(v_version)
  );
end;
$$;

create or replace function public.update_supplier_engagement_shell(
  p_tenant_id uuid,
  p_engagement_id uuid,
  p_expected_updated_at timestamptz,
  p_engagement jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_engagement public.supplier_engagements%rowtype;
  v_version public.supplier_engagement_versions%rowtype;
begin
  if v_role <> 'service_role'
     and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required'
      using errcode = '42501';
  end if;

  select engagement.*
  into v_engagement
  from public.supplier_engagements engagement
  where engagement.tenant_id = p_tenant_id
    and engagement.id = p_engagement_id
  for update;

  if not found then
    raise exception 'Supplier engagement not found' using errcode = 'P0002';
  end if;

  if v_role <> 'service_role' and p_expected_updated_at is null then
    raise exception 'Expected engagement updated_at is required for update'
      using errcode = '22023';
  end if;

  if p_expected_updated_at is not null
     and v_engagement.updated_at is distinct from p_expected_updated_at then
    raise exception 'Supplier engagement changed concurrently'
      using errcode = '40001';
  end if;

  update public.supplier_engagements engagement
  set site_id = case when p_engagement ? 'site_id'
        then nullif(p_engagement->>'site_id', '')::uuid
        else engagement.site_id end,
      engagement_kind = case when p_engagement ? 'engagement_kind'
        then lower(btrim(p_engagement->>'engagement_kind'))
        else engagement.engagement_kind end,
      code = case when p_engagement ? 'code'
        then btrim(p_engagement->>'code') else engagement.code end,
      name = case when p_engagement ? 'name'
        then btrim(p_engagement->>'name') else engagement.name end,
      status = case when p_engagement ? 'status'
        then lower(btrim(p_engagement->>'status')) else engagement.status end,
      starts_on = case when p_engagement ? 'starts_on'
        then nullif(p_engagement->>'starts_on', '')::date
        else engagement.starts_on end,
      ends_on = case when p_engagement ? 'ends_on'
        then nullif(p_engagement->>'ends_on', '')::date
        else engagement.ends_on end,
      metadata = case when jsonb_typeof(p_engagement->'metadata') = 'object'
        then p_engagement->'metadata' else engagement.metadata end,
      updated_at = clock_timestamp()
  where engagement.tenant_id = p_tenant_id
    and engagement.id = p_engagement_id
  returning * into v_engagement;

  select version.*
  into v_version
  from public.supplier_engagement_versions version
  where version.tenant_id = p_tenant_id
    and version.engagement_id = p_engagement_id
    and version.effective_to is null;

  return jsonb_build_object(
    'engagement', to_jsonb(v_engagement),
    'current_version', to_jsonb(v_version)
  );
end;
$$;

create or replace function public.append_supplier_engagement_version(
  p_tenant_id uuid,
  p_engagement_id uuid,
  p_effective_from date,
  p_version jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_engagement public.supplier_engagements%rowtype;
  v_current public.supplier_engagement_versions%rowtype;
  v_next public.supplier_engagement_versions%rowtype;
  v_actual_current public.supplier_engagement_versions%rowtype;
  v_next_number integer;
  v_operation_id uuid := nullif(p_version->>'operation_id', '')::uuid;
  v_request_fingerprint text;
  v_business_date date;
begin
  if v_role <> 'service_role'
     and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required'
      using errcode = '42501';
  end if;

  if v_role <> 'service_role' then
    v_business_date := public.tenant_business_date(p_tenant_id);
  end if;

  if v_operation_id is null then
    raise exception 'Engagement version operation_id is required'
      using errcode = '22023';
  end if;

  v_request_fingerprint := md5(jsonb_build_object(
    'engagement_id', p_engagement_id,
    'effective_from', p_effective_from,
    'version', p_version - 'operation_id'
  )::text);

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_engagement_version:' || p_tenant_id::text || ':' ||
      p_engagement_id::text,
      0
    )
  );

  select engagement.*
  into v_engagement
  from public.supplier_engagements engagement
  where engagement.tenant_id = p_tenant_id
    and engagement.id = p_engagement_id
  for update;

  if not found then
    raise exception 'Supplier engagement not found' using errcode = 'P0002';
  end if;

  select version.*
  into v_next
  from public.supplier_engagement_versions version
  where version.tenant_id = p_tenant_id
    and version.engagement_id = p_engagement_id
    and version.operation_id = v_operation_id;

  if found then
    if v_next.request_fingerprint <> v_request_fingerprint then
      raise exception 'Engagement version operation id was reused with different content'
        using errcode = '23505';
    end if;

    select version.*
    into v_current
    from public.supplier_engagement_versions version
    where version.tenant_id = p_tenant_id
      and version.engagement_id = p_engagement_id
      and version.effective_to = p_effective_from - 1
    order by version.effective_from desc
    limit 1;

    select version.*
    into v_actual_current
    from public.supplier_engagement_versions version
    where version.tenant_id = p_tenant_id
      and version.engagement_id = p_engagement_id
      and version.effective_to is null;

    return jsonb_build_object(
      'engagement', to_jsonb(v_engagement),
      'closed_version', case when v_current.id is null
        then null else to_jsonb(v_current) end,
      'applied_version', to_jsonb(v_next),
      'current_version', to_jsonb(v_actual_current),
      'idempotent_replay', true
    );
  end if;

  if v_role <> 'service_role'
     and (p_effective_from is null
       or p_effective_from < v_business_date) then
    raise exception 'Engagement effective_from cannot precede tenant business date'
      using errcode = '23514';
  end if;

  select version.*
  into v_current
  from public.supplier_engagement_versions version
  where version.tenant_id = p_tenant_id
    and version.engagement_id = p_engagement_id
    and version.effective_to is null
  for update;

  if not found or p_effective_from is null
     or p_effective_from <= v_current.effective_from then
    raise exception 'Next engagement version must start after current version'
      using errcode = '23514';
  end if;

  select coalesce(max(version.version_number), 0) + 1
  into v_next_number
  from public.supplier_engagement_versions version
  where version.tenant_id = p_tenant_id
    and version.engagement_id = p_engagement_id;

  update public.supplier_engagement_versions version
  set effective_to = p_effective_from - 1,
      updated_at = clock_timestamp()
  where version.id = v_current.id
  returning * into v_current;

  insert into public.supplier_engagement_versions (
    tenant_id,
    engagement_id,
    version_number,
    effective_from,
    external_reference,
    service_identifier,
    billing_cycle,
    currency_code,
    expected_amount,
    due_day,
    portal_url,
    operation_id,
    request_fingerprint,
    terms,
    created_by
  ) values (
    p_tenant_id,
    p_engagement_id,
    v_next_number,
    p_effective_from,
    nullif(btrim(p_version->>'external_reference'), ''),
    nullif(btrim(p_version->>'service_identifier'), ''),
    lower(btrim(coalesce(p_version->>'billing_cycle', 'none'))),
    upper(btrim(coalesce(p_version->>'currency_code', 'CLP'))),
    nullif(p_version->>'expected_amount', '')::numeric,
    nullif(p_version->>'due_day', '')::integer,
    nullif(btrim(p_version->>'portal_url'), ''),
    v_operation_id,
    v_request_fingerprint,
    coalesce(p_version->'terms', '{}'::jsonb),
    case when v_role = 'service_role' then null else auth.uid() end
  ) returning * into v_next;

  update public.supplier_engagements engagement
  set updated_at = clock_timestamp()
  where engagement.id = p_engagement_id
  returning * into v_engagement;

  return jsonb_build_object(
    'engagement', to_jsonb(v_engagement),
    'closed_version', to_jsonb(v_current),
    'applied_version', to_jsonb(v_next),
    'current_version', to_jsonb(v_next)
  );
end;
$$;

revoke all on function public.create_supplier_engagement(
  uuid, uuid, jsonb, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.update_supplier_engagement_shell(
  uuid, uuid, timestamptz, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.append_supplier_engagement_version(
  uuid, uuid, date, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.create_supplier_engagement(
  uuid, uuid, jsonb, jsonb
) to authenticated, service_role;
grant execute on function public.update_supplier_engagement_shell(
  uuid, uuid, timestamptz, jsonb
) to authenticated, service_role;
grant execute on function public.append_supplier_engagement_version(
  uuid, uuid, date, jsonb
) to authenticated, service_role;

create or replace function public.insert_supplier_accounting_rules_internal(
  p_tenant_id uuid,
  p_policy_version_id uuid,
  p_rules jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_rule jsonb;
  v_inserted jsonb := '[]'::jsonb;
  v_row public.supplier_accounting_rules%rowtype;
  v_rule_kind text;
  v_operator text;
  v_operand jsonb;
  v_text text;
  v_priority integer;
  v_is_active boolean;
  v_min numeric;
  v_max numeric;
  v_engagement_id uuid;
  v_policy_supplier_id uuid;
  v_allow_exact_autofill boolean;
begin
  if jsonb_typeof(coalesce(p_rules, '[]'::jsonb)) <> 'array' then
    raise exception 'Accounting rules must be an array'
      using errcode = '22023';
  end if;

  select policy.supplier_id, policy.allow_exact_autofill
  into v_policy_supplier_id, v_allow_exact_autofill
  from public.supplier_accounting_policy_versions version
  join public.supplier_accounting_policies policy
    on policy.tenant_id = version.tenant_id
   and policy.id = version.policy_id
  where version.tenant_id = p_tenant_id
    and version.id = p_policy_version_id;

  if not found then
    raise exception 'Supplier accounting policy version not found in tenant'
      using errcode = 'P0002';
  end if;

  for v_rule in
    select item from jsonb_array_elements(coalesce(p_rules, '[]'::jsonb)) item
  loop
    if jsonb_typeof(v_rule) <> 'object'
       or v_rule - array[
         'rule_kind', 'operator', 'operand', 'priority', 'is_active'
       ] <> '{}'::jsonb then
      raise exception 'Accounting rule contains unsupported fields'
      using errcode = '22023';
    end if;

    v_rule_kind := lower(btrim(coalesce(v_rule->>'rule_kind', '')));
    v_operator := lower(btrim(coalesce(v_rule->>'operator', '')));
    v_operand := coalesce(v_rule->'operand', '{}'::jsonb);

    if jsonb_typeof(v_operand) <> 'object'
       or public.jsonb_contains_sensitive_key(v_operand) then
      raise exception 'Accounting rule operand must be a secret-free object'
        using errcode = '22023';
    end if;

    if v_rule ? 'priority' and (
      jsonb_typeof(v_rule->'priority') <> 'number'
      or (v_rule->>'priority') !~ '^[0-9]+$'
    ) then
      raise exception 'Accounting rule priority must be an integer'
        using errcode = '22023';
    end if;
    v_priority := coalesce((v_rule->>'priority')::integer, 100);
    if v_priority < 0 or v_priority > 10000 then
      raise exception 'Accounting rule priority is outside the supported range'
        using errcode = '22023';
    end if;

    if v_rule ? 'is_active'
       and jsonb_typeof(v_rule->'is_active') <> 'boolean' then
      raise exception 'Accounting rule is_active must be boolean'
        using errcode = '22023';
    end if;
    v_is_active := coalesce((v_rule->>'is_active')::boolean, true);

    if v_rule_kind = 'document_type' and v_operator = 'equals' then
      if v_operand - 'document_type' <> '{}'::jsonb
         or jsonb_typeof(v_operand->'document_type') <> 'string'
         or nullif(btrim(v_operand->>'document_type'), '') is null
         or char_length(btrim(v_operand->>'document_type')) > 64 then
        raise exception 'document_type equals requires only a canonical document_type string'
          using errcode = '22023';
      end if;
      v_operand := jsonb_build_object(
        'document_type', btrim(v_operand->>'document_type')
      );
    elsif v_rule_kind in ('description', 'line_description')
          and v_operator in ('equals', 'contains', 'prefix', 'regex') then
      if v_operand - 'text' <> '{}'::jsonb
         or jsonb_typeof(v_operand->'text') <> 'string'
         or nullif(btrim(v_operand->>'text'), '') is null
         or char_length(btrim(v_operand->>'text')) > 500 then
        raise exception 'Text accounting rule requires only a nonblank text operand'
          using errcode = '22023';
      end if;
      v_text := btrim(v_operand->>'text');
      if v_operator = 'regex' then
        begin
          perform '' ~ v_text;
        exception when invalid_regular_expression then
          raise exception 'Accounting rule regex is invalid'
            using errcode = '22023';
        end;
      end if;
      v_operand := jsonb_build_object('text', v_text);
    elsif v_rule_kind = 'issuer_identifier' and v_operator = 'equals' then
      if v_operand - 'identifier' <> '{}'::jsonb
         or jsonb_typeof(v_operand->'identifier') <> 'string'
         or nullif(
           lower(regexp_replace(
             v_operand->>'identifier', '[^0-9A-Za-z]', '', 'g'
           )),
           ''
         ) is null
         or char_length(btrim(v_operand->>'identifier')) > 128 then
        raise exception 'issuer_identifier equals requires only a canonical identifier string'
          using errcode = '22023';
      end if;
      v_operand := jsonb_build_object(
        'identifier',
        lower(regexp_replace(
          v_operand->>'identifier', '[^0-9A-Za-z]', '', 'g'
        ))
      );
    elsif v_rule_kind = 'engagement' and v_operator = 'equals' then
      if v_operand - 'engagement_id' <> '{}'::jsonb
         or jsonb_typeof(v_operand->'engagement_id') <> 'string'
         or (v_operand->>'engagement_id') !~*
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        raise exception 'engagement equals requires only a canonical engagement_id UUID'
          using errcode = '22023';
      end if;
      v_engagement_id := (v_operand->>'engagement_id')::uuid;
      if not exists (
        select 1
        from public.supplier_engagements engagement
        where engagement.tenant_id = p_tenant_id
          and engagement.id = v_engagement_id
          and engagement.supplier_id = v_policy_supplier_id
      ) then
        raise exception 'Accounting rule engagement must belong to the policy supplier'
          using errcode = '23503';
      end if;
      v_operand := jsonb_build_object(
        'engagement_id', v_engagement_id::text
      );
    elsif v_rule_kind = 'amount_range' and v_operator = 'between' then
      if v_operand - array['min', 'max'] <> '{}'::jsonb
         or jsonb_typeof(v_operand->'min') <> 'number'
         or jsonb_typeof(v_operand->'max') <> 'number' then
        raise exception 'amount_range between requires only numeric min and max operands'
          using errcode = '22023';
      end if;
      v_min := (v_operand->>'min')::numeric;
      v_max := (v_operand->>'max')::numeric;
      if v_min > v_max then
        raise exception 'amount_range minimum cannot exceed maximum'
          using errcode = '22023';
      end if;
      v_operand := jsonb_build_object('min', v_min, 'max', v_max);
    elsif v_rule_kind = 'manual' and v_operator = 'present' then
      if v_operand <> '{}'::jsonb then
        raise exception 'manual present does not accept an operand'
          using errcode = '22023';
      end if;
      if v_allow_exact_autofill then
        raise exception 'Manual accounting rules are incompatible with exact autofill'
          using errcode = '23514';
      end if;
    else
      raise exception 'Unsupported accounting rule kind and operator combination'
        using errcode = '22023';
    end if;

    insert into public.supplier_accounting_rules (
      tenant_id,
      policy_version_id,
      rule_kind,
      operator,
      operand,
      priority,
      is_active
    ) values (
      p_tenant_id,
      p_policy_version_id,
      v_rule_kind,
      v_operator,
      v_operand,
      v_priority,
      v_is_active
    ) returning * into v_row;

    v_inserted := v_inserted || jsonb_build_array(to_jsonb(v_row));
  end loop;

  return v_inserted;
end;
$$;

revoke all on function public.insert_supplier_accounting_rules_internal(
  uuid, uuid, jsonb
) from public, anon, authenticated, service_role;

comment on function public.insert_supplier_accounting_rules_internal(
  uuid, uuid, jsonb
) is
  'Private policy-version writer with a closed kind/operator/operand matrix. It canonicalizes exact operands, validates regex syntax only, rejects secret-bearing or unknown shapes, and keeps manual gates incompatible with exact autofill.';

create or replace function public.create_supplier_accounting_policy(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_policy jsonb,
  p_initial_version jsonb,
  p_rules jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_policy public.supplier_accounting_policies%rowtype;
  v_version public.supplier_accounting_policy_versions%rowtype;
  v_current_version public.supplier_accounting_policy_versions%rowtype;
  v_rules jsonb;
  v_existing_rules jsonb;
  v_code text := btrim(coalesce(p_policy->>'code', ''));
  v_operation_id uuid := nullif(p_policy->>'operation_id', '')::uuid;
  v_request_fingerprint text;
  v_effective_from date := nullif(
    p_initial_version->>'effective_from', ''
  )::date;
  v_nature_code text := lower(btrim(coalesce(
    p_initial_version->>'operational_nature_code', ''
  )));
  v_business_date date;
begin
  if v_role <> 'service_role'
     and not public.can_manage_tenant_accounting(p_tenant_id) then
    raise exception 'Accounting authority required'
      using errcode = '42501';
  end if;

  if v_role <> 'service_role' then
    v_business_date := public.tenant_business_date(p_tenant_id);
  end if;

  if not exists (
    select 1 from public.suppliers supplier
    where supplier.tenant_id = p_tenant_id
      and supplier.id = p_supplier_id
  ) then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  if not exists (
    select 1 from public.operational_nature_definitions nature
    where nature.tenant_id = p_tenant_id
      and nature.code = v_nature_code
      and nature.is_active
  ) then
    raise exception 'Active operational nature not found in tenant'
      using errcode = '23503';
  end if;

  if v_effective_from is null
     or jsonb_typeof(coalesce(p_initial_version->'posture', '{}'::jsonb))
       <> 'object'
     or jsonb_typeof(coalesce(p_rules, '[]'::jsonb)) <> 'array'
     or v_operation_id is null then
    raise exception 'Policy effective_from and posture are required'
      using errcode = '22023';
  end if;

  v_request_fingerprint := md5(jsonb_build_object(
    'supplier_id', p_supplier_id,
    'policy', p_policy - 'operation_id',
    'initial_version', p_initial_version,
    'rules', coalesce(p_rules, '[]'::jsonb)
  )::text);

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_policy_operation:' || p_tenant_id::text || ':' ||
      v_operation_id::text,
      0
    )
  );

  select policy.*
  into v_policy
  from public.supplier_accounting_policies policy
  where policy.tenant_id = p_tenant_id
    and policy.operation_id = v_operation_id
  for update;

  if found then
    if v_policy.request_fingerprint <> v_request_fingerprint then
      raise exception 'Accounting policy operation id was reused with different content'
        using errcode = '23505';
    end if;

    select version.*
    into v_version
    from public.supplier_accounting_policy_versions version
    where version.tenant_id = p_tenant_id
      and version.policy_id = v_policy.id
      and version.operation_id = v_operation_id;

    select version.*
    into v_current_version
    from public.supplier_accounting_policy_versions version
    where version.tenant_id = p_tenant_id
      and version.policy_id = v_policy.id
      and version.effective_to is null;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rule_kind', rule.rule_kind,
          'operator', rule.operator,
          'operand', rule.operand,
          'priority', rule.priority,
          'is_active', rule.is_active
        ) order by rule.priority, rule.rule_kind, rule.operator,
          rule.operand::text
      ),
      '[]'::jsonb
    )
    into v_existing_rules
    from public.supplier_accounting_rules rule
    where rule.tenant_id = p_tenant_id
      and rule.policy_version_id = v_version.id;

    return jsonb_build_object(
      'policy', to_jsonb(v_policy),
      'applied_version', to_jsonb(v_version),
      'current_version', to_jsonb(v_current_version),
      'rules', v_existing_rules,
      'idempotent_replay', true
    );
  end if;

  if v_role <> 'service_role'
     and v_effective_from < v_business_date then
    raise exception 'Policy effective_from cannot precede tenant business date'
      using errcode = '23514';
  end if;

  insert into public.supplier_accounting_policies (
    tenant_id,
    supplier_id,
    engagement_id,
    code,
    name,
    status,
    priority,
    allow_exact_autofill,
    operation_id,
    request_fingerprint
  ) values (
    p_tenant_id,
    p_supplier_id,
    nullif(p_policy->>'engagement_id', '')::uuid,
    v_code,
    btrim(coalesce(p_policy->>'name', '')),
    lower(btrim(coalesce(p_policy->>'status', 'draft'))),
    coalesce((p_policy->>'priority')::integer, 100),
    coalesce((p_policy->>'allow_exact_autofill')::boolean, false),
    v_operation_id,
    v_request_fingerprint
  ) returning * into v_policy;

  insert into public.supplier_accounting_policy_versions (
    tenant_id,
    policy_id,
    version_number,
    effective_from,
    operational_nature_code,
    legacy_expense_category_id,
    debit_account_id,
    liability_account_id,
    tax_treatment,
    expected_document_type,
    currency_code,
    line_nature,
    operation_id,
    request_fingerprint,
    posture,
    created_by
  ) values (
    p_tenant_id,
    v_policy.id,
    1,
    v_effective_from,
    v_nature_code,
    nullif(p_initial_version->>'legacy_expense_category_id', '')::uuid,
    nullif(p_initial_version->>'debit_account_id', '')::uuid,
    nullif(p_initial_version->>'liability_account_id', '')::uuid,
    lower(btrim(coalesce(
      p_initial_version->>'tax_treatment', 'not_applicable'
    ))),
    nullif(btrim(p_initial_version->>'expected_document_type'), ''),
    upper(btrim(coalesce(p_initial_version->>'currency_code', 'CLP'))),
    nullif(lower(btrim(p_initial_version->>'line_nature')), ''),
    v_operation_id,
    v_request_fingerprint,
    coalesce(p_initial_version->'posture', '{}'::jsonb),
    case when v_role = 'service_role' then null else auth.uid() end
  ) returning * into v_version;

  v_rules := public.insert_supplier_accounting_rules_internal(
    p_tenant_id,
    v_version.id,
    coalesce(p_rules, '[]'::jsonb)
  );

  return jsonb_build_object(
    'policy', to_jsonb(v_policy),
    'applied_version', to_jsonb(v_version),
    'current_version', to_jsonb(v_version),
    'rules', v_rules
  );
end;
$$;

create or replace function public.update_supplier_accounting_policy_shell(
  p_tenant_id uuid,
  p_policy_id uuid,
  p_expected_updated_at timestamptz,
  p_policy jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_policy public.supplier_accounting_policies%rowtype;
  v_version public.supplier_accounting_policy_versions%rowtype;
  v_rules jsonb;
begin
  if v_role <> 'service_role'
     and not public.can_manage_tenant_accounting(p_tenant_id) then
    raise exception 'Accounting authority required'
      using errcode = '42501';
  end if;

  select policy.*
  into v_policy
  from public.supplier_accounting_policies policy
  where policy.tenant_id = p_tenant_id
    and policy.id = p_policy_id
  for update;

  if not found then
    raise exception 'Supplier accounting policy not found'
      using errcode = 'P0002';
  end if;

  if v_role <> 'service_role' and p_expected_updated_at is null then
    raise exception 'Expected policy updated_at is required for update'
      using errcode = '22023';
  end if;

  if p_expected_updated_at is not null
     and v_policy.updated_at is distinct from p_expected_updated_at then
    raise exception 'Supplier accounting policy changed concurrently'
      using errcode = '40001';
  end if;

  if p_policy ? 'allow_exact_autofill'
     and coalesce((p_policy->>'allow_exact_autofill')::boolean, false)
     and exists (
       select 1
       from public.supplier_accounting_policy_versions version
       join public.supplier_accounting_rules rule
         on rule.tenant_id = version.tenant_id
        and rule.policy_version_id = version.id
       where version.tenant_id = p_tenant_id
         and version.policy_id = p_policy_id
         and rule.is_active
         and rule.rule_kind = 'manual'
         and rule.operator = 'present'
     ) then
    raise exception 'Manual accounting rules are incompatible with exact autofill'
      using errcode = '23514';
  end if;

  update public.supplier_accounting_policies policy
  set engagement_id = case when p_policy ? 'engagement_id'
        then nullif(p_policy->>'engagement_id', '')::uuid
        else policy.engagement_id end,
      code = case when p_policy ? 'code'
        then btrim(p_policy->>'code') else policy.code end,
      name = case when p_policy ? 'name'
        then btrim(p_policy->>'name') else policy.name end,
      status = case when p_policy ? 'status'
        then lower(btrim(p_policy->>'status')) else policy.status end,
      priority = case when p_policy ? 'priority'
        then (p_policy->>'priority')::integer else policy.priority end,
      allow_exact_autofill = case when p_policy ? 'allow_exact_autofill'
        then (p_policy->>'allow_exact_autofill')::boolean
        else policy.allow_exact_autofill end,
      updated_at = clock_timestamp()
  where policy.tenant_id = p_tenant_id
    and policy.id = p_policy_id
  returning * into v_policy;

  select version.*
  into v_version
  from public.supplier_accounting_policy_versions version
  where version.tenant_id = p_tenant_id
    and version.policy_id = p_policy_id
    and version.effective_to is null;

  select coalesce(jsonb_agg(to_jsonb(rule) order by rule.priority, rule.id), '[]'::jsonb)
  into v_rules
  from public.supplier_accounting_rules rule
  where rule.tenant_id = p_tenant_id
    and rule.policy_version_id = v_version.id;

  return jsonb_build_object(
    'policy', to_jsonb(v_policy),
    'current_version', to_jsonb(v_version),
    'rules', v_rules
  );
end;
$$;

create or replace function public.append_supplier_accounting_policy_version(
  p_tenant_id uuid,
  p_policy_id uuid,
  p_effective_from date,
  p_version jsonb,
  p_rules jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_policy public.supplier_accounting_policies%rowtype;
  v_current public.supplier_accounting_policy_versions%rowtype;
  v_next public.supplier_accounting_policy_versions%rowtype;
  v_actual_current public.supplier_accounting_policy_versions%rowtype;
  v_next_number integer;
  v_nature_code text := lower(btrim(coalesce(
    p_version->>'operational_nature_code', ''
  )));
  v_rules jsonb;
  v_existing_rules jsonb;
  v_operation_id uuid := nullif(p_version->>'operation_id', '')::uuid;
  v_request_fingerprint text;
  v_business_date date;
begin
  if v_role <> 'service_role'
     and not public.can_manage_tenant_accounting(p_tenant_id) then
    raise exception 'Accounting authority required'
      using errcode = '42501';
  end if;

  if v_role <> 'service_role' then
    v_business_date := public.tenant_business_date(p_tenant_id);
  end if;

  if jsonb_typeof(coalesce(p_rules, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_version->'posture', '{}'::jsonb))
       <> 'object'
     or v_operation_id is null then
    raise exception 'Policy posture must be an object and rules an array'
      using errcode = '22023';
  end if;

  v_request_fingerprint := md5(jsonb_build_object(
    'policy_id', p_policy_id,
    'effective_from', p_effective_from,
    'version', p_version - 'operation_id',
    'rules', coalesce(p_rules, '[]'::jsonb)
  )::text);

  perform pg_advisory_xact_lock(
    hashtextextended(
      'supplier_policy_version:' || p_tenant_id::text || ':' ||
      p_policy_id::text,
      0
    )
  );

  select policy.*
  into v_policy
  from public.supplier_accounting_policies policy
  where policy.tenant_id = p_tenant_id
    and policy.id = p_policy_id
  for update;

  if not found then
    raise exception 'Supplier accounting policy not found'
      using errcode = 'P0002';
  end if;

  select version.*
  into v_next
  from public.supplier_accounting_policy_versions version
  where version.tenant_id = p_tenant_id
    and version.policy_id = p_policy_id
    and version.operation_id = v_operation_id;

  if found then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rule_kind', rule.rule_kind,
          'operator', rule.operator,
          'operand', rule.operand,
          'priority', rule.priority,
          'is_active', rule.is_active
        ) order by rule.priority, rule.rule_kind, rule.operator,
          rule.operand::text
      ),
      '[]'::jsonb
    )
    into v_existing_rules
    from public.supplier_accounting_rules rule
    where rule.tenant_id = p_tenant_id
      and rule.policy_version_id = v_next.id;

    if v_next.request_fingerprint <> v_request_fingerprint then
      raise exception 'Policy version operation id was reused with different content'
        using errcode = '23505';
    end if;

    select version.*
    into v_current
    from public.supplier_accounting_policy_versions version
    where version.tenant_id = p_tenant_id
      and version.policy_id = p_policy_id
      and version.effective_to = p_effective_from - 1
    order by version.effective_from desc
    limit 1;

    select version.*
    into v_actual_current
    from public.supplier_accounting_policy_versions version
    where version.tenant_id = p_tenant_id
      and version.policy_id = p_policy_id
      and version.effective_to is null;

    return jsonb_build_object(
      'policy', to_jsonb(v_policy),
      'closed_version', case when v_current.id is null
        then null else to_jsonb(v_current) end,
      'applied_version', to_jsonb(v_next),
      'current_version', to_jsonb(v_actual_current),
      'rules', v_existing_rules,
      'idempotent_replay', true
    );
  end if;

  if v_role <> 'service_role'
     and (p_effective_from is null
       or p_effective_from < v_business_date) then
    raise exception 'Policy effective_from cannot precede tenant business date'
      using errcode = '23514';
  end if;

  if not exists (
    select 1 from public.operational_nature_definitions nature
    where nature.tenant_id = p_tenant_id
      and nature.code = v_nature_code
      and nature.is_active
  ) then
    raise exception 'Active operational nature not found in tenant'
      using errcode = '23503';
  end if;

  select version.*
  into v_current
  from public.supplier_accounting_policy_versions version
  where version.tenant_id = p_tenant_id
    and version.policy_id = p_policy_id
    and version.effective_to is null
  for update;

  if not found or p_effective_from is null
     or p_effective_from <= v_current.effective_from then
    raise exception 'Next policy version must start after current version'
      using errcode = '23514';
  end if;

  select coalesce(max(version.version_number), 0) + 1
  into v_next_number
  from public.supplier_accounting_policy_versions version
  where version.tenant_id = p_tenant_id
    and version.policy_id = p_policy_id;

  update public.supplier_accounting_policy_versions version
  set effective_to = p_effective_from - 1,
      updated_at = clock_timestamp()
  where version.id = v_current.id
  returning * into v_current;

  insert into public.supplier_accounting_policy_versions (
    tenant_id,
    policy_id,
    version_number,
    effective_from,
    operational_nature_code,
    legacy_expense_category_id,
    debit_account_id,
    liability_account_id,
    tax_treatment,
    expected_document_type,
    currency_code,
    line_nature,
    operation_id,
    request_fingerprint,
    posture,
    created_by
  ) values (
    p_tenant_id,
    p_policy_id,
    v_next_number,
    p_effective_from,
    v_nature_code,
    nullif(p_version->>'legacy_expense_category_id', '')::uuid,
    nullif(p_version->>'debit_account_id', '')::uuid,
    nullif(p_version->>'liability_account_id', '')::uuid,
    lower(btrim(coalesce(p_version->>'tax_treatment', 'not_applicable'))),
    nullif(btrim(p_version->>'expected_document_type'), ''),
    upper(btrim(coalesce(p_version->>'currency_code', 'CLP'))),
    nullif(lower(btrim(p_version->>'line_nature')), ''),
    v_operation_id,
    v_request_fingerprint,
    coalesce(p_version->'posture', '{}'::jsonb),
    case when v_role = 'service_role' then null else auth.uid() end
  ) returning * into v_next;

  v_rules := public.insert_supplier_accounting_rules_internal(
    p_tenant_id,
    v_next.id,
    coalesce(p_rules, '[]'::jsonb)
  );

  update public.supplier_accounting_policies policy
  set updated_at = clock_timestamp()
  where policy.id = p_policy_id
  returning * into v_policy;

  return jsonb_build_object(
    'policy', to_jsonb(v_policy),
    'closed_version', to_jsonb(v_current),
    'applied_version', to_jsonb(v_next),
    'current_version', to_jsonb(v_next),
    'rules', v_rules
  );
end;
$$;

revoke all on function public.create_supplier_accounting_policy(
  uuid, uuid, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.update_supplier_accounting_policy_shell(
  uuid, uuid, timestamptz, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.append_supplier_accounting_policy_version(
  uuid, uuid, date, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.create_supplier_accounting_policy(
  uuid, uuid, jsonb, jsonb, jsonb
) to authenticated, service_role;
grant execute on function public.update_supplier_accounting_policy_shell(
  uuid, uuid, timestamptz, jsonb
) to authenticated, service_role;
grant execute on function public.append_supplier_accounting_policy_version(
  uuid, uuid, date, jsonb, jsonb
) to authenticated, service_role;
revoke all on public.supplier_profile_read_model
  from public, anon;
revoke all on public.active_business_site_read_model
  from public, anon, authenticated;
revoke all on public.supplier_classification_candidate_read_model
  from public, anon, authenticated;
revoke all on public.supplier_economic_read_model
  from public, anon;
revoke all on public.supplier_economic_summary_read_model
  from public, anon;
grant select on public.supplier_profile_read_model
  to authenticated;
grant select on public.active_business_site_read_model
  to authenticated;
grant select on public.supplier_classification_candidate_read_model
  to authenticated;
grant select on public.supplier_economic_read_model
  to authenticated;
grant select on public.supplier_economic_summary_read_model
  to authenticated;

commit;
