-- Fail-closed fiscal evidence for Mercado Pago vouchers treated as boletas.
--
-- SII Resolution 176 makes a payment voucher fiscally meaningful only when
-- the taxpayer has declared the corresponding emission model and the voucher
-- itself carries the prescribed merchant, tax, amount, terminal, operation,
-- authorization and timestamp evidence. The document recorder must therefore
-- derive fiscal validity from an independently verified tenant configuration;
-- a webhook caller cannot assert `voucher_valid_as_boleta` by itself.
--
-- This migration intentionally creates no tenant configuration and performs no
-- backfill. Until a verified declaration event is recorded, voucher recording
-- and voucher-email enqueueing fail closed. Official DTE evidence is unchanged.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.normalize_chilean_rut(p_rut text)
returns text
language plpgsql
immutable
strict
set search_path = public
as $$
declare
  v_compact text;
  v_body text;
begin
  v_compact := upper(regexp_replace(p_rut, '[^0-9kK]', '', 'g'));
  if v_compact !~ '^[0-9]{7,8}[0-9K]$' then
    return null;
  end if;

  v_body := ltrim(left(v_compact, length(v_compact) - 1), '0');
  if v_body = '' or length(v_body) not between 7 and 8 then
    return null;
  end if;

  return v_body || '-' || right(v_compact, 1);
end;
$$;

create or replace function public.is_valid_chilean_rut(p_rut text)
returns boolean
language plpgsql
immutable
strict
set search_path = public
as $$
declare
  v_normalized text := public.normalize_chilean_rut(p_rut);
  v_body text;
  v_expected text;
  v_sum integer := 0;
  v_multiplier integer := 2;
  v_index integer;
  v_remainder integer;
begin
  if v_normalized is null then
    return false;
  end if;

  v_body := split_part(v_normalized, '-', 1);
  for v_index in reverse length(v_body)..1 loop
    v_sum := v_sum + substr(v_body, v_index, 1)::integer * v_multiplier;
    v_multiplier := case when v_multiplier = 7 then 2 else v_multiplier + 1 end;
  end loop;

  v_remainder := 11 - (v_sum % 11);
  v_expected := case v_remainder
    when 11 then '0'
    when 10 then 'K'
    else v_remainder::text
  end;

  return split_part(v_normalized, '-', 2) = v_expected;
end;
$$;

revoke all on function public.normalize_chilean_rut(text)
  from public, anon, authenticated, service_role;
revoke all on function public.is_valid_chilean_rut(text)
  from public, anon, authenticated, service_role;
grant execute on function public.normalize_chilean_rut(text) to authenticated;
grant execute on function public.is_valid_chilean_rut(text) to authenticated;

create table if not exists public.tenant_sii_boleta_emission_model_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  model_code text not null check (
    model_code in (
      'no_emito_boleta_pago_electronico',
      'siempre_emito_boleta_pago_electronico'
    )
  ),
  merchant_tax_id text not null check (
    merchant_tax_id = public.normalize_chilean_rut(merchant_tax_id)
    and public.is_valid_chilean_rut(merchant_tax_id)
  ),
  merchant_legal_name text not null check (
    nullif(btrim(merchant_legal_name), '') is not null
    and merchant_legal_name = btrim(merchant_legal_name)
    and length(merchant_legal_name) <= 256
  ),
  merchant_address text not null check (
    nullif(btrim(merchant_address), '') is not null
    and merchant_address = btrim(merchant_address)
    and length(merchant_address) <= 512
  ),
  declared_at timestamp with time zone not null,
  effective_from timestamp with time zone not null,
  verified_at timestamp with time zone not null,
  verification_source text not null check (
    verification_source in (
      'sii_portal_declaration_receipt',
      'sii_portal_manual_review'
    )
  ),
  verification_reference text not null check (
    nullif(btrim(verification_reference), '') is not null
    and verification_reference = btrim(verification_reference)
    and length(verification_reference) <= 256
  ),
  evidence_artifact_url text not null check (
    evidence_artifact_url ~* '^https://[^[:space:]/@]+(/[^[:space:]]*)?$'
  ),
  evidence_artifact_sha256 text not null check (
    evidence_artifact_sha256 ~ '^[0-9a-f]{64}$'
  ),
  source_event_key text not null check (
    nullif(btrim(source_event_key), '') is not null
    and source_event_key = btrim(source_event_key)
    and length(source_event_key) <= 256
  ),
  evidence_fingerprint text not null check (
    evidence_fingerprint ~ '^[0-9a-f]{64}$'
  ),
  verified_by uuid references auth.users(id) on delete restrict,
  recorded_by uuid references auth.users(id) on delete set null,
  recorded_at timestamp with time zone not null default clock_timestamp(),
  constraint tenant_sii_boleta_model_event_timeline check (
    effective_from = declared_at
    and verified_at >= declared_at
  ),
  unique (tenant_id, id),
  unique (tenant_id, source_event_key),
  unique (tenant_id, effective_from)
);

create index if not exists idx_tenant_sii_boleta_model_effective
  on public.tenant_sii_boleta_emission_model_events(
    tenant_id,
    effective_from desc,
    recorded_at desc,
    id desc
  );

alter table public.tenant_sii_boleta_emission_model_events enable row level security;

drop policy if exists tenant_sii_boleta_model_staff_read
  on public.tenant_sii_boleta_emission_model_events;
create policy tenant_sii_boleta_model_staff_read
  on public.tenant_sii_boleta_emission_model_events
  for select to authenticated
  using (public.has_active_official_document_staff_access(tenant_id));

revoke all on public.tenant_sii_boleta_emission_model_events
  from public, anon, authenticated, service_role;
grant select on public.tenant_sii_boleta_emission_model_events to authenticated;

create or replace function public.prevent_tenant_sii_boleta_model_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'SII boleta emission model events are append-only'
    using errcode = '55000';
end;
$$;

revoke all on function public.prevent_tenant_sii_boleta_model_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_tenant_sii_boleta_model_immutable
  on public.tenant_sii_boleta_emission_model_events;
create trigger trg_tenant_sii_boleta_model_immutable
  before update or delete on public.tenant_sii_boleta_emission_model_events
  for each row execute function public.prevent_tenant_sii_boleta_model_mutation();

create or replace function public.record_tenant_sii_boleta_emission_model(
  p_tenant_id uuid,
  p_model_code text,
  p_merchant_tax_id text,
  p_merchant_legal_name text,
  p_merchant_address text,
  p_declared_at timestamp with time zone,
  p_effective_from timestamp with time zone,
  p_verified_at timestamp with time zone,
  p_verification_source text,
  p_verification_reference text,
  p_evidence_artifact_url text,
  p_evidence_artifact_sha256 text,
  p_source_event_key text,
  p_verified_by uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_model_code text := lower(btrim(coalesce(p_model_code, '')));
  v_merchant_tax_id text := public.normalize_chilean_rut(p_merchant_tax_id);
  v_merchant_legal_name text := btrim(coalesce(p_merchant_legal_name, ''));
  v_merchant_address text := btrim(coalesce(p_merchant_address, ''));
  v_verification_source text := lower(btrim(coalesce(p_verification_source, '')));
  v_verification_reference text := btrim(coalesce(p_verification_reference, ''));
  v_artifact_url text := btrim(coalesce(p_evidence_artifact_url, ''));
  v_artifact_sha256 text := lower(btrim(coalesce(p_evidence_artifact_sha256, '')));
  v_source_event_key text := btrim(coalesce(p_source_event_key, ''));
  v_fingerprint text;
  v_existing public.tenant_sii_boleta_emission_model_events%rowtype;
  v_event_id uuid;
begin
  if p_tenant_id is null or not exists (
    select 1 from public.tenants tenant where tenant.id = p_tenant_id
  ) then
    raise exception 'SII boleta model requires an existing tenant'
      using errcode = '23503';
  end if;
  if v_model_code not in (
    'no_emito_boleta_pago_electronico',
    'siempre_emito_boleta_pago_electronico'
  ) then
    raise exception 'Unsupported SII boleta emission model'
      using errcode = '22023';
  end if;
  if v_merchant_tax_id is null
     or not public.is_valid_chilean_rut(v_merchant_tax_id) then
    raise exception 'SII boleta model requires a valid Chilean merchant RUT'
      using errcode = '22023';
  end if;
  if v_merchant_legal_name = '' or length(v_merchant_legal_name) > 256
     or v_merchant_address = '' or length(v_merchant_address) > 512 then
    raise exception 'SII boleta model requires merchant legal name and address'
      using errcode = '22023';
  end if;
  if p_declared_at is null or p_effective_from is null or p_verified_at is null
     or p_effective_from <> p_declared_at
     or p_verified_at < p_declared_at
     or p_verified_at > clock_timestamp() + interval '5 minutes'
     or p_declared_at > clock_timestamp() + interval '5 minutes' then
    raise exception 'SII boleta model declaration timeline is invalid'
      using errcode = '22023';
  end if;
  if v_verification_source not in (
    'sii_portal_declaration_receipt',
    'sii_portal_manual_review'
  ) then
    raise exception 'SII boleta model verification source is invalid'
      using errcode = '22023';
  end if;
  if v_verification_source = 'sii_portal_manual_review'
     and (
       p_verified_by is null
       or not exists (
         select 1
         from public.user_profiles profile
         where profile.user_id = p_verified_by
           and profile.tenant_id = p_tenant_id
           and coalesce(profile.is_active, true)
       )
     ) then
    raise exception 'Manual SII model review requires an active tenant verifier'
      using errcode = '23514';
  end if;
  if v_verification_reference = '' or length(v_verification_reference) > 256
     or v_source_event_key = '' or length(v_source_event_key) > 256 then
    raise exception 'SII boleta model provenance identifiers are invalid'
      using errcode = '22023';
  end if;
  if v_artifact_url !~* '^https://[^[:space:]/@]+(/[^[:space:]]*)?$'
     or v_artifact_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'SII boleta model requires a secure hashed evidence artifact'
      using errcode = '22023';
  end if;

  v_fingerprint := encode(extensions.digest(convert_to(
    jsonb_build_object(
      'tenant_id', p_tenant_id,
      'model_code', v_model_code,
      'merchant_tax_id', v_merchant_tax_id,
      'merchant_legal_name', v_merchant_legal_name,
      'merchant_address', v_merchant_address,
      'declared_at', p_declared_at,
      'effective_from', p_effective_from,
      'verified_at', p_verified_at,
      'verification_source', v_verification_source,
      'verification_reference', v_verification_reference,
      'evidence_artifact_url', v_artifact_url,
      'evidence_artifact_sha256', v_artifact_sha256,
      'verified_by', p_verified_by
    )::text,
    'UTF8'
  ), 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended(
    p_tenant_id::text || ':sii-boleta-model:' || v_source_event_key,
    0
  ));

  select * into v_existing
  from public.tenant_sii_boleta_emission_model_events event
  where event.tenant_id = p_tenant_id
    and (
      event.source_event_key = v_source_event_key
      or event.effective_from = p_effective_from
    )
  order by (event.source_event_key = v_source_event_key) desc
  limit 1;

  if found then
    if v_existing.evidence_fingerprint <> v_fingerprint then
      raise exception 'SII boleta model idempotency key conflicts with different evidence'
        using errcode = '23000';
    end if;
    return v_existing.id;
  end if;

  insert into public.tenant_sii_boleta_emission_model_events (
    tenant_id,
    model_code,
    merchant_tax_id,
    merchant_legal_name,
    merchant_address,
    declared_at,
    effective_from,
    verified_at,
    verification_source,
    verification_reference,
    evidence_artifact_url,
    evidence_artifact_sha256,
    source_event_key,
    evidence_fingerprint,
    verified_by,
    recorded_by
  ) values (
    p_tenant_id,
    v_model_code,
    v_merchant_tax_id,
    v_merchant_legal_name,
    v_merchant_address,
    p_declared_at,
    p_effective_from,
    p_verified_at,
    v_verification_source,
    v_verification_reference,
    v_artifact_url,
    v_artifact_sha256,
    v_source_event_key,
    v_fingerprint,
    p_verified_by,
    auth.uid()
  )
  returning id into v_event_id;

  return v_event_id;
end;
$$;

revoke all on function public.record_tenant_sii_boleta_emission_model(
  uuid,
  text,
  text,
  text,
  text,
  timestamp with time zone,
  timestamp with time zone,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  text,
  uuid
) from public, anon, authenticated, service_role;
grant execute on function public.record_tenant_sii_boleta_emission_model(
  uuid,
  text,
  text,
  text,
  text,
  timestamp with time zone,
  timestamp with time zone,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  text,
  uuid
) to service_role;

alter table public.online_order_official_documents
  add column if not exists sii_emission_model_event_id uuid,
  add column if not exists merchant_tax_id text,
  add column if not exists merchant_legal_name text,
  add column if not exists merchant_address text,
  add column if not exists taxable_net_amount numeric(14,0),
  add column if not exists exempt_amount numeric(14,0),
  add column if not exists vat_rate_percent numeric(5,2),
  add column if not exists vat_amount numeric(14,0),
  add column if not exists other_amount numeric(14,0),
  add column if not exists terminal_id text,
  add column if not exists authorization_code text,
  add column if not exists fiscal_legend text,
  add column if not exists voucher_evidence_fingerprint text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.online_order_official_documents'::regclass
      and conname = 'online_order_documents_sii_model_tenant_fkey'
  ) then
    alter table public.online_order_official_documents
      add constraint online_order_documents_sii_model_tenant_fkey
      foreign key (tenant_id, sii_emission_model_event_id)
      references public.tenant_sii_boleta_emission_model_events(tenant_id, id)
      on delete restrict;
  end if;
end;
$$;

-- NOT VALID deliberately preserves any pre-existing historical row without
-- pretending it meets the new legal-evidence standard. PostgreSQL still
-- enforces this constraint for every row inserted after this migration.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.online_order_official_documents'::regclass
      and conname = 'online_order_official_documents_voucher_fiscal_shape'
  ) then
    alter table public.online_order_official_documents
      add constraint online_order_official_documents_voucher_fiscal_shape check (
        (
          document_kind = 'payment_voucher'
          and sii_emission_model_event_id is not null
          and merchant_tax_id = public.normalize_chilean_rut(merchant_tax_id)
          and public.is_valid_chilean_rut(merchant_tax_id)
          and nullif(btrim(merchant_legal_name), '') is not null
          and length(merchant_legal_name) <= 256
          and nullif(btrim(merchant_address), '') is not null
          and length(merchant_address) <= 512
          and currency = 'CLP'
          and amount = trunc(amount)
          and taxable_net_amount is not null and taxable_net_amount >= 0
          and exempt_amount is not null and exempt_amount >= 0
          and vat_rate_percent = 19
          and vat_amount is not null and vat_amount >= 0
          and other_amount is not null and other_amount >= 0
          and taxable_net_amount + exempt_amount > 0
          and vat_amount = round(taxable_net_amount * vat_rate_percent / 100, 0)
          and amount = taxable_net_amount + exempt_amount + vat_amount + other_amount
          and nullif(btrim(terminal_id), '') is not null
          and length(terminal_id) <= 128
          and nullif(btrim(authorization_code), '') is not null
          and length(authorization_code) <= 128
          and fiscal_legend = 'Válido como Boleta'
          and voucher_evidence_fingerprint ~ '^[0-9a-f]{64}$'
        )
        or (
          document_kind <> 'payment_voucher'
          and sii_emission_model_event_id is null
          and merchant_tax_id is null
          and merchant_legal_name is null
          and merchant_address is null
          and taxable_net_amount is null
          and exempt_amount is null
          and vat_rate_percent is null
          and vat_amount is null
          and other_amount is null
          and terminal_id is null
          and authorization_code is null
          and fiscal_legend is null
          and voucher_evidence_fingerprint is null
        )
      ) not valid;
  end if;
end;
$$;

create or replace function public.official_payment_voucher_fiscal_evidence_fingerprint(
  p_evidence jsonb
)
returns text
language sql
immutable
strict
set search_path = public, extensions
as $$
  -- Numeric typmods add display scale when evidence is reconstructed from the
  -- ledger (for example 19 becomes 19.00). Hash a scale-neutral JSON value so
  -- the pre-insert evidence and immutable stored evidence have one fingerprint.
  select encode(extensions.digest(convert_to((
    p_evidence || jsonb_build_object(
      'amount', trim_scale((p_evidence->>'amount')::numeric),
      'taxable_net_amount', trim_scale(
        (p_evidence->>'taxable_net_amount')::numeric
      ),
      'exempt_amount', trim_scale((p_evidence->>'exempt_amount')::numeric),
      'vat_rate_percent', trim_scale(
        (p_evidence->>'vat_rate_percent')::numeric
      ),
      'vat_amount', trim_scale((p_evidence->>'vat_amount')::numeric),
      'other_amount', trim_scale((p_evidence->>'other_amount')::numeric)
    )
  )::text, 'UTF8'), 'sha256'), 'hex');
$$;

revoke all on function public.official_payment_voucher_fiscal_evidence_fingerprint(jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.apply_official_payment_voucher_fiscal_evidence()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evidence jsonb;
begin
  if new.document_kind <> 'payment_voucher' then
    return new;
  end if;

  begin
    v_evidence := nullif(
      current_setting('app.online_order_voucher_fiscal_evidence', true),
      ''
    )::jsonb;
  exception when others then
    v_evidence := null;
  end;

  if v_evidence is null
     or v_evidence->>'tenant_id' is distinct from new.tenant_id::text
     or v_evidence->>'order_id' is distinct from new.order_id::text
     or v_evidence->>'provider_document_id' is distinct from new.provider_document_id
     or v_evidence->>'payment_operation_id' is distinct from new.payment_operation_id
     or (v_evidence->>'issued_at')::timestamp with time zone is distinct from new.issued_at
     or (v_evidence->>'amount')::numeric is distinct from new.amount
     or v_evidence->>'currency' is distinct from new.currency then
    raise exception 'Voucher fiscal evidence is absent or does not match the document'
      using errcode = '23514';
  end if;

  new.sii_emission_model_event_id := (v_evidence->>'sii_emission_model_event_id')::uuid;
  new.merchant_tax_id := v_evidence->>'merchant_tax_id';
  new.merchant_legal_name := v_evidence->>'merchant_legal_name';
  new.merchant_address := v_evidence->>'merchant_address';
  new.taxable_net_amount := (v_evidence->>'taxable_net_amount')::numeric;
  new.exempt_amount := (v_evidence->>'exempt_amount')::numeric;
  new.vat_rate_percent := (v_evidence->>'vat_rate_percent')::numeric;
  new.vat_amount := (v_evidence->>'vat_amount')::numeric;
  new.other_amount := (v_evidence->>'other_amount')::numeric;
  new.terminal_id := v_evidence->>'terminal_id';
  new.authorization_code := v_evidence->>'authorization_code';
  new.fiscal_legend := v_evidence->>'fiscal_legend';
  new.voucher_evidence_fingerprint :=
    public.official_payment_voucher_fiscal_evidence_fingerprint(v_evidence);

  return new;
end;
$$;

revoke all on function public.apply_official_payment_voucher_fiscal_evidence()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_apply_official_payment_voucher_fiscal_evidence
  on public.online_order_official_documents;
create trigger trg_apply_official_payment_voucher_fiscal_evidence
  before insert on public.online_order_official_documents
  for each row execute function public.apply_official_payment_voucher_fiscal_evidence();

-- Preserve the 150000 implementation as a private primitive. On a complete
-- core-schema replay, 150000 recreates the public 17-argument function; this
-- block replaces the old private copy with that fresh implementation.
do $$
begin
  if to_regprocedure(
    'public.record_online_order_official_document(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb)'
  ) is not null then
    if to_regprocedure(
      'public.record_online_order_official_document_unhardened(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb)'
    ) is not null then
      execute 'drop function public.record_online_order_official_document_unhardened(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb)';
    end if;
    execute 'alter function public.record_online_order_official_document(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb) rename to record_online_order_official_document_unhardened';
  end if;
end;
$$;

revoke all on function public.record_online_order_official_document_unhardened(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  numeric,
  text,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb
) from public, anon, authenticated, service_role;

create or replace function public.record_online_order_official_document(
  p_tenant_id uuid,
  p_order_id uuid,
  p_document_kind text,
  p_provider text,
  p_provider_document_id text,
  p_fiscal_validity text,
  p_amount numeric,
  p_currency text,
  p_issued_at timestamp with time zone,
  p_artifact_url text,
  p_artifact_sha256 text,
  p_status text,
  p_source_event_key text,
  p_payment_operation_id text default null,
  p_document_type text default null,
  p_folio text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_voucher_fiscal_evidence jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_document_kind text := lower(btrim(coalesce(p_document_kind, '')));
  v_currency text := upper(btrim(coalesce(p_currency, '')));
  v_provider_document_id text := btrim(coalesce(p_provider_document_id, ''));
  v_payment_operation_id text := nullif(btrim(coalesce(p_payment_operation_id, '')), '');
  v_model public.tenant_sii_boleta_emission_model_events%rowtype;
  v_merchant_tax_id text;
  v_merchant_legal_name text;
  v_merchant_address text;
  v_taxable_net numeric;
  v_exempt numeric;
  v_vat_rate numeric;
  v_vat numeric;
  v_other numeric;
  v_terminal_id text;
  v_authorization_code text;
  v_fiscal_legend text;
  v_evidence jsonb;
  v_document_id uuid;
  v_stored_fingerprint text;
begin
  if v_document_kind <> 'payment_voucher' then
    if p_voucher_fiscal_evidence is not null then
      raise exception 'Voucher fiscal evidence is only valid for payment vouchers'
        using errcode = '22023';
    end if;

    return public.record_online_order_official_document_unhardened(
      p_tenant_id,
      p_order_id,
      p_document_kind,
      p_provider,
      p_provider_document_id,
      p_fiscal_validity,
      p_amount,
      p_currency,
      p_issued_at,
      p_artifact_url,
      p_artifact_sha256,
      p_status,
      p_source_event_key,
      p_payment_operation_id,
      p_document_type,
      p_folio,
      p_metadata
    );
  end if;

  if p_voucher_fiscal_evidence is null
     or jsonb_typeof(p_voucher_fiscal_evidence) <> 'object' then
    raise exception 'Mercado Pago voucher requires structured fiscal evidence'
      using errcode = '23514';
  end if;

  if not p_voucher_fiscal_evidence ?& array[
    'merchant_tax_id',
    'merchant_legal_name',
    'merchant_address',
    'taxable_net_amount',
    'exempt_amount',
    'vat_rate_percent',
    'vat_amount',
    'other_amount',
    'terminal_id',
    'authorization_code',
    'fiscal_legend'
  ]
  or p_voucher_fiscal_evidence - array[
    'merchant_tax_id',
    'merchant_legal_name',
    'merchant_address',
    'taxable_net_amount',
    'exempt_amount',
    'vat_rate_percent',
    'vat_amount',
    'other_amount',
    'terminal_id',
    'authorization_code',
    'fiscal_legend'
  ] <> '{}'::jsonb then
    raise exception 'Voucher fiscal evidence fields are incomplete or unsupported'
      using errcode = '22023';
  end if;

  if jsonb_typeof(p_voucher_fiscal_evidence->'merchant_tax_id') <> 'string'
     or jsonb_typeof(p_voucher_fiscal_evidence->'merchant_legal_name') <> 'string'
     or jsonb_typeof(p_voucher_fiscal_evidence->'merchant_address') <> 'string'
     or jsonb_typeof(p_voucher_fiscal_evidence->'terminal_id') <> 'string'
     or jsonb_typeof(p_voucher_fiscal_evidence->'authorization_code') <> 'string'
     or jsonb_typeof(p_voucher_fiscal_evidence->'fiscal_legend') <> 'string'
     or jsonb_typeof(p_voucher_fiscal_evidence->'taxable_net_amount') <> 'number'
     or jsonb_typeof(p_voucher_fiscal_evidence->'exempt_amount') <> 'number'
     or jsonb_typeof(p_voucher_fiscal_evidence->'vat_rate_percent') <> 'number'
     or jsonb_typeof(p_voucher_fiscal_evidence->'vat_amount') <> 'number'
     or jsonb_typeof(p_voucher_fiscal_evidence->'other_amount') <> 'number' then
    raise exception 'Voucher fiscal evidence field types are invalid'
      using errcode = '22023';
  end if;

  v_merchant_tax_id := public.normalize_chilean_rut(
    p_voucher_fiscal_evidence->>'merchant_tax_id'
  );
  v_merchant_legal_name := btrim(p_voucher_fiscal_evidence->>'merchant_legal_name');
  v_merchant_address := btrim(p_voucher_fiscal_evidence->>'merchant_address');
  v_taxable_net := (p_voucher_fiscal_evidence->>'taxable_net_amount')::numeric;
  v_exempt := (p_voucher_fiscal_evidence->>'exempt_amount')::numeric;
  v_vat_rate := (p_voucher_fiscal_evidence->>'vat_rate_percent')::numeric;
  v_vat := (p_voucher_fiscal_evidence->>'vat_amount')::numeric;
  v_other := (p_voucher_fiscal_evidence->>'other_amount')::numeric;
  v_terminal_id := btrim(p_voucher_fiscal_evidence->>'terminal_id');
  v_authorization_code := btrim(p_voucher_fiscal_evidence->>'authorization_code');
  v_fiscal_legend := btrim(p_voucher_fiscal_evidence->>'fiscal_legend');

  if v_merchant_tax_id is null
     or not public.is_valid_chilean_rut(v_merchant_tax_id)
     or v_merchant_legal_name = '' or length(v_merchant_legal_name) > 256
     or v_merchant_address = '' or length(v_merchant_address) > 512
     or v_terminal_id = '' or length(v_terminal_id) > 128
     or v_authorization_code = '' or length(v_authorization_code) > 128
     or v_fiscal_legend <> 'Válido como Boleta' then
    raise exception 'Voucher merchant, terminal, authorization or fiscal legend is invalid'
      using errcode = '23514';
  end if;

  if v_currency <> 'CLP'
     or p_amount is null or p_amount <> trunc(p_amount)
     or v_taxable_net < 0 or v_taxable_net <> trunc(v_taxable_net)
     or v_exempt < 0 or v_exempt <> trunc(v_exempt)
     or v_vat_rate <> 19
     or v_vat < 0 or v_vat <> trunc(v_vat)
     or v_other < 0 or v_other <> trunc(v_other)
     or v_taxable_net + v_exempt <= 0
     or v_vat <> round(v_taxable_net * v_vat_rate / 100, 0)
     or p_amount <> v_taxable_net + v_exempt + v_vat + v_other then
    raise exception 'Voucher CLP tax amounts are arithmetically invalid'
      using errcode = '23514';
  end if;

  select * into v_model
  from public.tenant_sii_boleta_emission_model_events event
  where event.tenant_id = p_tenant_id
    and event.effective_from <= p_issued_at
    and event.verified_at is not null
  order by event.effective_from desc, event.recorded_at desc, event.id desc
  limit 1;

  if not found
     or v_model.model_code <> 'no_emito_boleta_pago_electronico' then
    raise exception 'Tenant has no active verified SII model allowing voucher as boleta'
      using errcode = '23514';
  end if;
  if v_merchant_tax_id <> v_model.merchant_tax_id
     or v_merchant_legal_name <> v_model.merchant_legal_name
     or v_merchant_address <> v_model.merchant_address then
    raise exception 'Voucher merchant identity does not match verified SII configuration'
      using errcode = '23514';
  end if;

  v_evidence := jsonb_build_object(
    'schema_version', 1,
    'tenant_id', p_tenant_id,
    'order_id', p_order_id,
    'provider_document_id', v_provider_document_id,
    'payment_operation_id', v_payment_operation_id,
    'issued_at', p_issued_at,
    'amount', p_amount,
    'currency', v_currency,
    'sii_emission_model_event_id', v_model.id,
    'merchant_tax_id', v_merchant_tax_id,
    'merchant_legal_name', v_merchant_legal_name,
    'merchant_address', v_merchant_address,
    'taxable_net_amount', v_taxable_net,
    'exempt_amount', v_exempt,
    'vat_rate_percent', v_vat_rate,
    'vat_amount', v_vat,
    'other_amount', v_other,
    'terminal_id', v_terminal_id,
    'authorization_code', v_authorization_code,
    'fiscal_legend', v_fiscal_legend
  );

  perform set_config(
    'app.online_order_voucher_fiscal_evidence',
    v_evidence::text,
    true
  );

  begin
    v_document_id := public.record_online_order_official_document_unhardened(
      p_tenant_id,
      p_order_id,
      p_document_kind,
      p_provider,
      p_provider_document_id,
      p_fiscal_validity,
      p_amount,
      p_currency,
      p_issued_at,
      p_artifact_url,
      p_artifact_sha256,
      p_status,
      p_source_event_key,
      p_payment_operation_id,
      p_document_type,
      p_folio,
      p_metadata
    );
  exception when others then
    perform set_config('app.online_order_voucher_fiscal_evidence', '', true);
    raise;
  end;

  perform set_config('app.online_order_voucher_fiscal_evidence', '', true);

  select document.voucher_evidence_fingerprint into v_stored_fingerprint
  from public.online_order_official_documents document
  where document.id = v_document_id;

  if v_stored_fingerprint is distinct from
       public.official_payment_voucher_fiscal_evidence_fingerprint(v_evidence) then
    raise exception 'Voucher idempotency identity conflicts with different fiscal evidence'
      using errcode = '23000';
  end if;

  return v_document_id;
end;
$$;

revoke all on function public.record_online_order_official_document(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  numeric,
  text,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.record_online_order_official_document(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  numeric,
  text,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb
) to service_role;

-- The 150000 migration may recreate the unhardened public enqueue function on
-- a complete schema replay. Capture it only when its body is not our hardened
-- wrapper, so rerunning 180000 alone remains idempotent.
do $$
declare
  v_public_body text;
begin
  select routine.prosrc into v_public_body
  from pg_proc routine
  where routine.oid = to_regprocedure(
    'public.enqueue_transactional_email_from_official_document_id(uuid)'
  );

  if v_public_body is not null
     and v_public_body not like '%tenant_sii_boleta_emission_model_events%' then
    if to_regprocedure(
      'public.enqueue_transactional_email_official_document_base(uuid)'
    ) is not null then
      execute 'drop function public.enqueue_transactional_email_official_document_base(uuid)';
    end if;
    execute 'alter function public.enqueue_transactional_email_from_official_document_id(uuid) rename to enqueue_transactional_email_official_document_base';
  end if;
end;
$$;

revoke all on function public.enqueue_transactional_email_official_document_base(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.enqueue_transactional_email_from_official_document_id(
  p_document_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_document public.online_order_official_documents%rowtype;
  v_model public.tenant_sii_boleta_emission_model_events%rowtype;
  v_evidence jsonb;
begin
  select * into v_document
  from public.online_order_official_documents document
  where document.id = p_document_id;

  if not found then
    return null;
  end if;

  if v_document.document_kind = 'payment_voucher' then
    select * into v_model
    from public.tenant_sii_boleta_emission_model_events event
    where event.tenant_id = v_document.tenant_id
      and event.effective_from <= v_document.issued_at
      and event.verified_at is not null
    order by event.effective_from desc, event.recorded_at desc, event.id desc
    limit 1;

    if not found
       or v_model.id is distinct from v_document.sii_emission_model_event_id
       or v_model.model_code <> 'no_emito_boleta_pago_electronico'
       or v_document.merchant_tax_id is distinct from v_model.merchant_tax_id
       or v_document.merchant_legal_name is distinct from v_model.merchant_legal_name
       or v_document.merchant_address is distinct from v_model.merchant_address
       or v_document.currency <> 'CLP'
       or v_document.amount <> trunc(v_document.amount)
       or v_document.taxable_net_amount is null
       or v_document.exempt_amount is null
       or v_document.vat_rate_percent <> 19
       or v_document.vat_amount is null
       or v_document.other_amount is null
       or v_document.taxable_net_amount < 0
       or v_document.exempt_amount < 0
       or v_document.vat_amount < 0
       or v_document.other_amount < 0
       or v_document.taxable_net_amount + v_document.exempt_amount <= 0
       or v_document.vat_amount <>
          round(v_document.taxable_net_amount * v_document.vat_rate_percent / 100, 0)
       or v_document.amount <>
          v_document.taxable_net_amount + v_document.exempt_amount
          + v_document.vat_amount + v_document.other_amount
       or nullif(btrim(v_document.terminal_id), '') is null
       or nullif(btrim(v_document.authorization_code), '') is null
       or v_document.fiscal_legend <> 'Válido como Boleta' then
      return null;
    end if;

    v_evidence := jsonb_build_object(
      'schema_version', 1,
      'tenant_id', v_document.tenant_id,
      'order_id', v_document.order_id,
      'provider_document_id', v_document.provider_document_id,
      'payment_operation_id', v_document.payment_operation_id,
      'issued_at', v_document.issued_at,
      'amount', v_document.amount,
      'currency', v_document.currency,
      'sii_emission_model_event_id', v_document.sii_emission_model_event_id,
      'merchant_tax_id', v_document.merchant_tax_id,
      'merchant_legal_name', v_document.merchant_legal_name,
      'merchant_address', v_document.merchant_address,
      'taxable_net_amount', v_document.taxable_net_amount,
      'exempt_amount', v_document.exempt_amount,
      'vat_rate_percent', v_document.vat_rate_percent,
      'vat_amount', v_document.vat_amount,
      'other_amount', v_document.other_amount,
      'terminal_id', v_document.terminal_id,
      'authorization_code', v_document.authorization_code,
      'fiscal_legend', v_document.fiscal_legend
    );

    if v_document.voucher_evidence_fingerprint is distinct from
         public.official_payment_voucher_fiscal_evidence_fingerprint(v_evidence) then
      return null;
    end if;
  end if;

  return public.enqueue_transactional_email_official_document_base(
    p_document_id
  );
end;
$$;

revoke all on function public.enqueue_transactional_email_from_official_document_id(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.enqueue_transactional_email_from_official_document_id(uuid)
  to service_role;

-- Rebind the row trigger to the hardened public gate. This is explicit because
-- ALTER FUNCTION RENAME preserves OID dependencies on the old implementation.
create or replace function public.enqueue_transactional_email_from_official_document()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.enqueue_transactional_email_from_official_document_id(new.id);
  return new;
end;
$$;

revoke all on function public.enqueue_transactional_email_from_official_document()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_enqueue_transactional_email_from_official_document
  on public.online_order_official_documents;
create trigger trg_enqueue_transactional_email_from_official_document
  after insert on public.online_order_official_documents
  for each row execute function public.enqueue_transactional_email_from_official_document();

comment on table public.tenant_sii_boleta_emission_model_events is
  'Append-only tenant SII boleta-emission declarations with independent verification provenance; absence means unknown and vouchers fail closed.';
comment on column public.online_order_official_documents.sii_emission_model_event_id is
  'Verified tenant SII declaration event effective when this payment voucher was issued.';
comment on column public.online_order_official_documents.voucher_evidence_fingerprint is
  'SHA-256 binding of tenant, order, operation, issue time and every structured fiscal voucher field.';
comment on function public.record_online_order_official_document(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  numeric,
  text,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb,
  jsonb
) is
  'Service-only recorder. Mercado Pago vouchers derive fiscal validity from verified tenant SII configuration and complete Resolution 176 evidence; DTE behavior is preserved.';

commit;
