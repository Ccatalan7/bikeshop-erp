-- Deployment status (2026-08-12): production-applied through the guarded
-- standalone-SQL path. Live read-back proved all five RLS tables/policies,
-- authenticated-only RPCs with fixed search_path, enabled invoice guards,
-- the one-active and globally bound-source uniqueness indexes, and zero
-- unexpected revision/source rows before the separately reviewed seed.
--
-- Purpose:
--   Replace one-product mutable supplier aliases with a revisioned,
--   provenance-bearing resolution graph. One immutable supplier variant may
--   resolve to one catalog product, a homogeneous pack of one product, or an
--   ordered composite of several ordinary catalog products. A source invoice
--   line remains a durable parent even when it expands into N purchase items.
--
-- Forward behavior:
--   Additive tables and authenticated RPCs only. Legacy purchase invoice JSON
--   without supplier-resolution provenance is untouched. New provenance rows
--   are accepted only through replay-safe commands, and provenance-bearing
--   purchase_invoices.items are rejected unless they exactly reproduce the
--   staged revision edge set, quantities, allocation, and source total.
--   Money reconciliation is intentionally CLP-only: the current purchase item
--   model has no currency exponent or FX snapshot from which another currency
--   could be converted without guessing.
--
-- Lock/backfill risk:
--   No data backfill. Creating the purchase-invoice validation triggers takes
--   a brief SHARE ROW EXCLUSIVE lock; lock_timeout keeps this bounded. The
--   existing alias table remains readable as review-only compatibility
--   evidence and is not rewritten.
--
-- Recovery:
--   Stop new callers and revoke EXECUTE from the three new RPCs. If an urgent
--   compatibility rollback is required, disable only
--   trg_validate_purchase_invoice_supplier_resolution and
--   trg_bind_purchase_invoice_supplier_resolution. Preserve all revision,
--   correction, staging, and component rows as audit/idempotency evidence;
--   never drop or rewrite them after production writes have been accepted.
--
-- Required post-deployment read-back:
--   Verify table constraints/FKs, the one-active partial index, trigger
--   enablement, SECURITY DEFINER + fixed search_path, authenticated-only RPC
--   grants, RLS policies, zero provenance-bearing legacy invoice items, and a
--   replay/contradiction/quantity/allocation pgTAP smoke. Reapply this exact
--   file to a production-derived scratch database to prove idempotent DDL.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create unique index if not exists uq_products_tenant_id_id
  on public.products(tenant_id, id);
create unique index if not exists uq_suppliers_tenant_id_id
  on public.suppliers(tenant_id, id);
create unique index if not exists uq_purchase_invoices_tenant_id_id
  on public.purchase_invoices(tenant_id, id);

-- These fields already exist in production and are emitted by
-- PurchaseInvoice.toJson. Keep the additive migration self-contained for the
-- canonical bootstrap as well: the graph header validator must not silently
-- skip a global discount merely because an older bootstrap omitted its input
-- columns.
alter table public.purchase_invoices
  add column if not exists discount_type text default 'percentage',
  add column if not exists discount_value numeric default 0,
  add column if not exists is_discount_before_tax boolean default true;

create table if not exists public.supplier_variant_resolution_revisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  listing_id text not null,
  variant_key text not null,
  revision_number integer not null,
  state text not null,
  resolution_kind text,
  option_evidence_hash text not null,
  option_pack_count integer,
  option_unit_class text not null,
  pack_evidence_conflict boolean not null default false,
  edge_set_hash text not null,
  operation_id uuid not null,
  request_fingerprint text not null,
  supersedes_revision_id uuid,
  correction_reason text,
  decision_source text not null,
  decision_evidence jsonb not null,
  decision_evidence_hash text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, operation_id),
  unique (
    tenant_id, supplier_id, listing_id, variant_key, revision_number
  ),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete restrict,
  foreign key (tenant_id, supersedes_revision_id)
    references public.supplier_variant_resolution_revisions(tenant_id, id)
    on delete restrict,
  check (listing_id = lower(btrim(listing_id))),
  check (listing_id <> '' and length(listing_id) <= 256),
  check (variant_key = lower(btrim(variant_key))),
  check (
    (variant_key like 'sku:%'
      and length(variant_key) between 6 and 512
      and substr(variant_key, 5) ~ '^[a-z0-9][a-z0-9._-]+$'
      and substr(variant_key, 5) !~ '^(default|unknown|none|null)$'
      and substr(variant_key, 5)
        !~ '^(human|image|label|title|color|fallback)([:._-]|$)')
    or variant_key ~ '^props:[a-z0-9._-]+:[a-z0-9._-]+(\|[a-z0-9._-]+:[a-z0-9._-]+)*$'
  ),
  check (revision_number > 0),
  check (state in ('active', 'superseded', 'revoked')),
  check (resolution_kind in ('single', 'homogeneous', 'composite')),
  check (
    (state = 'revoked' and resolution_kind is null)
    or (state <> 'revoked' and resolution_kind is not null)
  ),
  check (option_evidence_hash ~ '^[a-f0-9]{64}$'),
  check (
    option_pack_count is null
    or (option_pack_count > 0 and option_pack_count <= 1000000)
  ),
  check (
    option_unit_class in ('piece', 'pair', 'set', 'unit', 'unknown')
    or (
      option_unit_class like 'supplier:%'
      and length(option_unit_class) between 10 and 41
      and substr(option_unit_class, 10) ~ '^[a-z0-9][a-z0-9_.:-]*$'
    )
  ),
  check (state <> 'active' or pack_evidence_conflict is false),
  check (edge_set_hash ~ '^[a-f0-9]{64}$'),
  check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  check (jsonb_typeof(decision_evidence) = 'object'),
  check (octet_length(decision_evidence::text) <= 16384),
  check (decision_evidence_hash ~ '^[a-f0-9]{64}$'),
  check (
    decision_source in (
      'operator_confirmed',
      'invoice_confirmed',
      'administrative_correction',
      'migration_confirmed'
    )
  ),
  check (
    correction_reason is null
    or (
      correction_reason = btrim(correction_reason)
      and length(correction_reason) between 1 and 1000
    )
  )
);

create unique index if not exists
  uq_supplier_variant_resolution_one_active
on public.supplier_variant_resolution_revisions(
  tenant_id, supplier_id, listing_id, variant_key
)
where state = 'active';

create index if not exists idx_supplier_variant_resolution_lookup
  on public.supplier_variant_resolution_revisions(
    tenant_id,
    supplier_id,
    listing_id,
    variant_key,
    revision_number desc
  );

create table if not exists public.supplier_variant_resolution_edges (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  revision_id uuid not null,
  edge_ordinal integer not null,
  product_id uuid not null,
  catalog_units_per_purchase integer not null,
  allocation_ratio numeric(18,12) not null,
  component_role text not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, revision_id, edge_ordinal),
  foreign key (tenant_id, revision_id)
    references public.supplier_variant_resolution_revisions(tenant_id, id)
    on delete restrict,
  foreign key (tenant_id, product_id)
    references public.products(tenant_id, id) on delete restrict,
  check (edge_ordinal > 0),
  check (
    catalog_units_per_purchase > 0
    and catalog_units_per_purchase <= 1000000
  ),
  check (allocation_ratio > 0 and allocation_ratio <= 1),
  check (
    component_role = lower(btrim(component_role))
    and length(component_role) between 1 and 80
    and component_role ~ '^[a-z0-9][a-z0-9_.:-]*$'
  )
);

create index if not exists idx_supplier_variant_resolution_edges_product
  on public.supplier_variant_resolution_edges(
    tenant_id, product_id, revision_id
  );

create table if not exists public.supplier_variant_resolution_corrections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  prior_revision_id uuid not null,
  replacement_revision_id uuid not null,
  correction_action text not null,
  operation_id uuid not null,
  reason text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, prior_revision_id),
  unique (tenant_id, operation_id),
  foreign key (tenant_id, prior_revision_id)
    references public.supplier_variant_resolution_revisions(tenant_id, id)
    on delete restrict,
  foreign key (tenant_id, replacement_revision_id)
    references public.supplier_variant_resolution_revisions(tenant_id, id)
    on delete restrict,
  check (prior_revision_id <> replacement_revision_id),
  check (
    correction_action in ('correction', 'reactivation', 'revocation')
  ),
  check (
    reason = btrim(reason)
    and length(reason) between 1 and 1000
  )
);

create table if not exists public.purchase_invoice_source_resolutions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_invoice_id uuid,
  source_line_key text not null,
  source_row_index integer not null,
  source_document_date date not null,
  supplier_resolution_revision_id uuid not null,
  supplier_listing_id text not null,
  supplier_variant_key text not null,
  option_evidence_hash text not null,
  edge_set_hash text not null,
  source_order_numbers text[] not null default '{}'::text[],
  source_title text not null,
  selected_option text,
  raw_pack_count integer,
  raw_unit_token text,
  option_unit_class text not null,
  pack_evidence_conflict boolean not null default false,
  source_snapshot jsonb not null,
  source_snapshot_hash text not null,
  source_purchase_quantity numeric(18,6) not null,
  source_line_total_minor bigint not null,
  currency_code text not null default 'CLP',
  operation_id uuid not null,
  request_fingerprint text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  bound_at timestamptz,
  unique (tenant_id, id),
  unique (tenant_id, operation_id),
  foreign key (tenant_id, purchase_invoice_id)
    references public.purchase_invoices(tenant_id, id) on delete restrict,
  foreign key (tenant_id, supplier_resolution_revision_id)
    references public.supplier_variant_resolution_revisions(tenant_id, id)
    on delete restrict,
  check (
    source_line_key = btrim(source_line_key)
    and length(source_line_key) between 1 and 512
  ),
  check (source_row_index >= 0),
  check (
    supplier_listing_id = lower(btrim(supplier_listing_id))
    and supplier_listing_id <> ''
    and length(supplier_listing_id) <= 256
  ),
  check (
    supplier_variant_key = lower(btrim(supplier_variant_key))
    and (
      (supplier_variant_key like 'sku:%'
        and length(supplier_variant_key) between 6 and 512
        and substr(supplier_variant_key, 5) ~ '^[a-z0-9][a-z0-9._-]+$'
        and substr(supplier_variant_key, 5)
          !~ '^(default|unknown|none|null)$'
        and substr(supplier_variant_key, 5)
          !~ '^(human|image|label|title|color|fallback)([:._-]|$)')
      or supplier_variant_key ~ '^props:[a-z0-9._-]+:[a-z0-9._-]+(\|[a-z0-9._-]+:[a-z0-9._-]+)*$'
    )
  ),
  check (
    cardinality(source_order_numbers) between 1 and 64
    and array_position(source_order_numbers, null) is null
  ),
  check (
    source_title = btrim(source_title)
    and length(source_title) between 1 and 2000
  ),
  check (
    selected_option is null
    or (
      selected_option = btrim(selected_option)
      and length(selected_option) between 1 and 1000
    )
  ),
  check (
    raw_pack_count is null
    or (raw_pack_count > 0 and raw_pack_count <= 1000000)
  ),
  check (
    raw_unit_token is null
    or (
      raw_unit_token = lower(btrim(raw_unit_token))
      and length(raw_unit_token) between 1 and 32
      and raw_unit_token ~ '^[a-z0-9][a-z0-9_.:-]*$'
    )
  ),
  check (
    option_unit_class in ('piece', 'pair', 'set', 'unit', 'unknown')
    or (
      option_unit_class like 'supplier:%'
      and length(option_unit_class) between 10 and 41
      and substr(option_unit_class, 10) ~ '^[a-z0-9][a-z0-9_.:-]*$'
    )
  ),
  check (jsonb_typeof(source_snapshot) = 'object'),
  check (octet_length(source_snapshot::text) <= 32768),
  check (source_snapshot_hash ~ '^[a-f0-9]{64}$'),
  check (
    source_purchase_quantity > 0
    and source_purchase_quantity <= 1000000000
  ),
  check (source_line_total_minor >= 0),
  check (currency_code = 'CLP'),
  check (option_evidence_hash ~ '^[a-f0-9]{64}$'),
  check (edge_set_hash ~ '^[a-f0-9]{64}$'),
  check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  check (
    (purchase_invoice_id is null and bound_at is null)
    or (purchase_invoice_id is not null and bound_at is not null)
  )
);

alter table public.purchase_invoice_source_resolutions
  add column if not exists source_document_date date;

alter table public.purchase_invoice_source_resolutions
  alter column source_document_date set not null;

create unique index if not exists
  uq_purchase_invoice_source_resolution_line
on public.purchase_invoice_source_resolutions(
  tenant_id, source_line_key
)
where purchase_invoice_id is not null;

create index if not exists idx_purchase_invoice_source_resolution_revision
  on public.purchase_invoice_source_resolutions(
    tenant_id, supplier_resolution_revision_id, created_at desc
  );

create table if not exists public.purchase_invoice_source_components (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  source_resolution_id uuid not null,
  revision_edge_id uuid not null,
  edge_ordinal integer not null,
  product_id uuid not null,
  catalog_units_per_purchase integer not null,
  resolved_quantity numeric(18,6) not null,
  allocation_ratio numeric(18,12) not null,
  allocated_line_total_minor bigint not null,
  component_role text not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, source_resolution_id, edge_ordinal),
  unique (tenant_id, source_resolution_id, revision_edge_id),
  foreign key (tenant_id, source_resolution_id)
    references public.purchase_invoice_source_resolutions(tenant_id, id)
    on delete restrict,
  foreign key (tenant_id, revision_edge_id)
    references public.supplier_variant_resolution_edges(tenant_id, id)
    on delete restrict,
  foreign key (tenant_id, product_id)
    references public.products(tenant_id, id) on delete restrict,
  check (edge_ordinal > 0),
  check (
    catalog_units_per_purchase > 0
    and catalog_units_per_purchase <= 1000000
  ),
  check (resolved_quantity > 0),
  check (allocation_ratio > 0 and allocation_ratio <= 1),
  check (allocated_line_total_minor >= 0),
  check (
    component_role = lower(btrim(component_role))
    and length(component_role) between 1 and 80
    and component_role ~ '^[a-z0-9][a-z0-9_.:-]*$'
  )
);

alter table public.supplier_variant_resolution_revisions enable row level security;
alter table public.supplier_variant_resolution_edges enable row level security;
alter table public.supplier_variant_resolution_corrections enable row level security;
alter table public.purchase_invoice_source_resolutions enable row level security;
alter table public.purchase_invoice_source_components enable row level security;

drop policy if exists supplier_variant_resolution_revisions_select
  on public.supplier_variant_resolution_revisions;
create policy supplier_variant_resolution_revisions_select
  on public.supplier_variant_resolution_revisions
  for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = auth.uid()
        and profile.tenant_id = supplier_variant_resolution_revisions.tenant_id
        and profile.is_active is true
    )
  );

drop policy if exists supplier_variant_resolution_edges_select
  on public.supplier_variant_resolution_edges;
create policy supplier_variant_resolution_edges_select
  on public.supplier_variant_resolution_edges
  for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = auth.uid()
        and profile.tenant_id = supplier_variant_resolution_edges.tenant_id
        and profile.is_active is true
    )
  );

drop policy if exists supplier_variant_resolution_corrections_select
  on public.supplier_variant_resolution_corrections;
create policy supplier_variant_resolution_corrections_select
  on public.supplier_variant_resolution_corrections
  for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = auth.uid()
        and profile.tenant_id = supplier_variant_resolution_corrections.tenant_id
        and profile.is_active is true
    )
  );

drop policy if exists purchase_invoice_source_resolutions_select
  on public.purchase_invoice_source_resolutions;
create policy purchase_invoice_source_resolutions_select
  on public.purchase_invoice_source_resolutions
  for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = auth.uid()
        and profile.tenant_id = purchase_invoice_source_resolutions.tenant_id
        and profile.is_active is true
    )
  );

drop policy if exists purchase_invoice_source_components_select
  on public.purchase_invoice_source_components;
create policy purchase_invoice_source_components_select
  on public.purchase_invoice_source_components
  for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = auth.uid()
        and profile.tenant_id = purchase_invoice_source_components.tenant_id
        and profile.is_active is true
    )
  );

revoke all on public.supplier_variant_resolution_revisions
  from public, anon, authenticated, service_role;
revoke all on public.supplier_variant_resolution_edges
  from public, anon, authenticated, service_role;
revoke all on public.supplier_variant_resolution_corrections
  from public, anon, authenticated, service_role;
revoke all on public.purchase_invoice_source_resolutions
  from public, anon, authenticated, service_role;
revoke all on public.purchase_invoice_source_components
  from public, anon, authenticated, service_role;

grant select on public.supplier_variant_resolution_revisions to authenticated;
grant select on public.supplier_variant_resolution_edges to authenticated;
grant select on public.supplier_variant_resolution_corrections to authenticated;
grant select on public.purchase_invoice_source_resolutions to authenticated;
grant select on public.purchase_invoice_source_components to authenticated;

create or replace function public.normalize_immutable_supplier_variant_key(
  p_value text
)
returns text
language plpgsql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_value text := lower(btrim(coalesce(p_value, '')));
  v_payload text;
  v_canonical text;
  v_count integer;
  v_distinct_properties integer;
begin
  if length(v_value) > 512 then
    raise exception 'Supplier immutable variant key is too long.'
      using errcode = '22023';
  end if;

  if v_value like 'sku:%'
     and length(v_value) between 6 and 512
     and substr(v_value, 5) ~ '^[a-z0-9][a-z0-9._-]+$'
     and substr(v_value, 5) !~ '^(default|unknown|none|null)$'
     and substr(v_value, 5)
       !~ '^(human|image|label|title|color|fallback)([:._-]|$)' then
    return v_value;
  end if;

  if v_value !~ '^props:[a-z0-9._-]+:[a-z0-9._-]+(\|[a-z0-9._-]+:[a-z0-9._-]+)*$' then
    raise exception 'An immutable sku: or props: supplier variant key is required.'
      using errcode = '22023';
  end if;

  v_payload := substr(v_value, 7);
  select
    string_agg(part, '|' order by split_part(part, ':', 1), split_part(part, ':', 2)),
    count(*)::integer,
    count(distinct split_part(part, ':', 1))::integer
  into v_canonical, v_count, v_distinct_properties
  from unnest(string_to_array(v_payload, '|')) part;

  if v_count <> v_distinct_properties then
    raise exception 'Immutable props: keys cannot repeat a property ID.'
      using errcode = '22023';
  end if;

  return 'props:' || v_canonical;
end;
$$;

create or replace function public.supplier_resolution_sha256(
  p_payload jsonb
)
returns text
language sql
immutable
set search_path = pg_catalog, public, extensions
as $$
  select encode(extensions.digest(coalesce(p_payload, 'null'::jsonb)::text, 'sha256'), 'hex');
$$;

create or replace function public.normalize_supplier_option_unit_class(
  p_value text
)
returns text
language plpgsql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_value text := nullif(lower(btrim(coalesce(p_value, ''))), '');
begin
  if v_value is null then return 'unknown'; end if;
  if v_value in ('pc', 'pcs', 'piece', 'pieces', 'pieza', 'piezas', 'pz', 'pzs') then
    return 'piece';
  end if;
  if v_value in ('pair', 'pairs', 'par', 'pares') then return 'pair'; end if;
  if v_value in ('set', 'sets', 'juego', 'juegos', 'kit', 'kits') then
    return 'set';
  end if;
  if v_value in ('unit', 'units', 'unidad', 'unidades', 'un') then
    return 'unit';
  end if;
  if v_value in ('piece', 'pair', 'set', 'unit', 'unknown') then return v_value; end if;
  if length(v_value) > 32 or v_value !~ '^[a-z0-9][a-z0-9_.:-]*$' then
    raise exception 'Supplier option unit token is invalid.'
      using errcode = '22023';
  end if;
  if v_value like 'supplier:%' then return v_value; end if;
  return 'supplier:' || v_value;
end;
$$;

create or replace function public.supplier_option_evidence_v1_hash(
  p_variant_key text,
  p_pack_count integer,
  p_unit_class text,
  p_pack_evidence_conflict boolean
)
returns text
language plpgsql
immutable
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  v_variant_key text := public.normalize_immutable_supplier_variant_key(
    p_variant_key
  );
  v_unit_class text := public.normalize_supplier_option_unit_class(p_unit_class);
  v_wire text;
begin
  if p_pack_count is not null and (p_pack_count < 1 or p_pack_count > 1000000) then
    raise exception 'Supplier option pack count is invalid.'
      using errcode = '22023';
  end if;
  v_wire := '{"schema":"supplier_option_evidence_v1","variant_key":"'
    || v_variant_key
    || '","pack_count":'
    || coalesce(p_pack_count::text, 'null')
    || ',"unit_class":"'
    || v_unit_class
    || '","pack_evidence_conflict":'
    || case when coalesce(p_pack_evidence_conflict, false) then 'true' else 'false' end
    || '}';
  return encode(extensions.digest(convert_to(v_wire, 'UTF8'), 'sha256'), 'hex');
end;
$$;

revoke all on function public.normalize_immutable_supplier_variant_key(text)
  from public, anon, authenticated, service_role;
revoke all on function public.supplier_resolution_sha256(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.normalize_supplier_option_unit_class(text)
  from public, anon, authenticated, service_role;
revoke all on function public.supplier_option_evidence_v1_hash(
  text, integer, text, boolean
) from public, anon, authenticated, service_role;

create or replace function public.supplier_resolution_product_target_is_valid(
  p_tenant_id uuid,
  p_product_id uuid,
  p_resolution_kind text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.products product
    where product.tenant_id = p_tenant_id
      and product.id = p_product_id
      and product.is_active is true
      and product.product_type = 'product'
      and (
        product.is_set is false
        or (
          product.is_set is true
          and p_resolution_kind in ('single', 'homogeneous')
          and product.parent_set_id is null
          and product.track_stock is true
          and product.purchase_treatment = 'inventory'
          and exists (
            select 1
            from public.product_set_components component
            where component.tenant_id = p_tenant_id
              and component.set_product_id = product.id
          )
          and not exists (
            select 1
            from public.product_set_components component
            left join public.products child
              on child.tenant_id = component.tenant_id
             and child.id = component.component_product_id
            where component.tenant_id = p_tenant_id
              and component.set_product_id = product.id
              and (
                component.quantity_in_set <= 0
                or child.id is null
                or child.is_active is not true
                or child.product_type <> 'product'
                or child.is_set is not false
                or child.parent_set_id is distinct from product.id
              )
          )
        )
      )
  );
$$;

revoke all on function public.supplier_resolution_product_target_is_valid(
  uuid, uuid, text
) from public, anon, authenticated, service_role;

create or replace function public.guard_supplier_resolution_evidence_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_guard text := coalesce(
    current_setting('app.supplier_resolution_write_guard', true),
    ''
  );
  v_expected text := txid_current()::text;
begin
  if tg_table_name = 'supplier_variant_resolution_revisions' then
    if tg_op = 'UPDATE'
       and v_guard = v_expected
       and old.state = 'active'
       and new.state = 'superseded'
       and (to_jsonb(new) - 'state') = (to_jsonb(old) - 'state') then
      return new;
    end if;
  end if;

  if tg_table_name = 'purchase_invoice_source_resolutions' then
    if tg_op = 'UPDATE'
       and v_guard = v_expected
       and old.purchase_invoice_id is null
       and old.bound_at is null
       and new.purchase_invoice_id is not null
       and new.bound_at is not null
       and (to_jsonb(new) - array['purchase_invoice_id', 'bound_at'])
         = (to_jsonb(old) - array['purchase_invoice_id', 'bound_at']) then
      return new;
    end if;
  end if;

  raise exception '% rows are append-only evidence', tg_table_name
    using errcode = '55000';
end;
$$;

revoke all on function public.guard_supplier_resolution_evidence_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_supplier_variant_resolution_revisions_immutable
  on public.supplier_variant_resolution_revisions;
create trigger trg_supplier_variant_resolution_revisions_immutable
  before update or delete on public.supplier_variant_resolution_revisions
  for each row execute function
    public.guard_supplier_resolution_evidence_mutation();

drop trigger if exists trg_supplier_variant_resolution_edges_immutable
  on public.supplier_variant_resolution_edges;
create trigger trg_supplier_variant_resolution_edges_immutable
  before update or delete on public.supplier_variant_resolution_edges
  for each row execute function
    public.guard_supplier_resolution_evidence_mutation();

drop trigger if exists trg_supplier_variant_resolution_corrections_immutable
  on public.supplier_variant_resolution_corrections;
create trigger trg_supplier_variant_resolution_corrections_immutable
  before update or delete on public.supplier_variant_resolution_corrections
  for each row execute function
    public.guard_supplier_resolution_evidence_mutation();

drop trigger if exists trg_purchase_invoice_source_resolutions_immutable
  on public.purchase_invoice_source_resolutions;
create trigger trg_purchase_invoice_source_resolutions_immutable
  before update or delete on public.purchase_invoice_source_resolutions
  for each row execute function
    public.guard_supplier_resolution_evidence_mutation();

drop trigger if exists trg_purchase_invoice_source_components_immutable
  on public.purchase_invoice_source_components;
create trigger trg_purchase_invoice_source_components_immutable
  before update or delete on public.purchase_invoice_source_components
  for each row execute function
    public.guard_supplier_resolution_evidence_mutation();

create or replace function public.remember_supplier_variant_resolution(
  p_operation_id uuid,
  p_supplier_id uuid,
  p_item_id text,
  p_product_url text,
  p_variant_key text,
  p_option_evidence_hash text,
  p_option_pack_count integer,
  p_option_unit_class text,
  p_pack_evidence_conflict boolean,
  p_action text,
  p_resolution_kind text,
  p_edges jsonb,
  p_expected_prior_revision_id uuid,
  p_correction_reason text,
  p_decision_source text,
  p_decision_evidence jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_listing_id text;
  v_variant_key text;
  v_option_hash text := lower(regexp_replace(
    btrim(coalesce(p_option_evidence_hash, '')),
    '^sha-?256:',
    ''
  ));
  v_option_unit_class text;
  v_pack_conflict boolean := coalesce(p_pack_evidence_conflict, false);
  v_action text := lower(btrim(coalesce(p_action, 'activate')));
  v_kind text := nullif(lower(btrim(coalesce(p_resolution_kind, ''))), '');
  v_reason text := nullif(btrim(coalesce(p_correction_reason, '')), '');
  v_decision_source text := lower(btrim(coalesce(p_decision_source, '')));
  v_decision_evidence jsonb := p_decision_evidence;
  v_decision_evidence_hash text;
  v_edges jsonb := '[]'::jsonb;
  v_edge_count integer := 0;
  v_distinct_ordinals integer := 0;
  v_min_ordinal integer;
  v_max_ordinal integer;
  v_allocation_sum numeric := 0;
  v_edge_set_hash text;
  v_request_fingerprint text;
  v_existing_operation public.supplier_variant_resolution_revisions%rowtype;
  v_active public.supplier_variant_resolution_revisions%rowtype;
  v_latest public.supplier_variant_resolution_revisions%rowtype;
  v_new public.supplier_variant_resolution_revisions%rowtype;
  v_revision_number integer;
  v_prior_id uuid;
  v_correction_action text;
begin
  if v_tenant_id is null or auth.uid() is null then
    raise exception 'Authenticated tenant context is required.'
      using errcode = '42501';
  end if;
  if p_operation_id is null or p_supplier_id is null then
    raise exception 'Operation and supplier are required.'
      using errcode = '22004';
  end if;
  perform public.assert_supplier_product_identity_access(v_tenant_id, true);

  v_listing_id := public.normalize_supplier_listing_id(p_item_id, p_product_url);
  v_variant_key := public.normalize_immutable_supplier_variant_key(p_variant_key);

  if v_option_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'Option evidence must be a SHA-256 hex digest.'
      using errcode = '22023';
  end if;
  v_option_unit_class := public.normalize_supplier_option_unit_class(
    p_option_unit_class
  );
  if v_option_hash <> public.supplier_option_evidence_v1_hash(
    v_variant_key,
    p_option_pack_count,
    v_option_unit_class,
    v_pack_conflict
  ) then
    raise exception 'Option evidence hash does not match its canonical v1 fields.'
      using errcode = '23514';
  end if;
  if v_action = 'activate' and v_pack_conflict then
    raise exception 'Conflicting pack evidence cannot activate a supplier resolution.'
      using errcode = '23514';
  end if;
  if v_action not in ('activate', 'revoke') then
    raise exception 'Resolution action must be activate or revoke.'
      using errcode = '22023';
  end if;
  if v_decision_source not in (
    'operator_confirmed',
    'invoice_confirmed',
    'administrative_correction',
    'migration_confirmed'
  ) then
    raise exception 'Resolution decision source is not authoritative.'
      using errcode = '22023';
  end if;
  if v_decision_evidence is null
     or jsonb_typeof(v_decision_evidence) <> 'object'
     or octet_length(v_decision_evidence::text) > 16384 then
    raise exception 'A bounded decision evidence object is required.'
      using errcode = '22023';
  end if;
  if jsonb_path_exists(
    v_decision_evidence,
    '$.** ? (@.type() == "object").keyvalue() ? (@.key like_regex "^(email|phone|address|recipient|buyer|credential|cookie|token|authorization|payment|card)$" flag "i")'
  ) then
    raise exception 'Decision evidence contains a forbidden sensitive field.'
      using errcode = '22023';
  end if;
  if v_decision_evidence ? 'model_version' and (
    coalesce(jsonb_typeof(v_decision_evidence->'model_version'), '') <> 'string'
    or length(btrim(v_decision_evidence->>'model_version')) not between 1 and 128
  ) then
    raise exception 'Decision evidence model_version is invalid.'
      using errcode = '22023';
  end if;
  if v_decision_source in ('operator_confirmed', 'invoice_confirmed') then
    if not (v_decision_evidence ?& array[
      'source_line_key',
      'source_document_date',
      'supplier_order_numbers',
      'source_purchase_quantity',
      'persisted_quantity',
      'source_total_minor',
      'persisted_total_minor',
      'currency_code'
    ])
       or coalesce(jsonb_typeof(v_decision_evidence->'source_line_key'), '') <> 'string'
       or coalesce(jsonb_typeof(v_decision_evidence->'source_document_date'), '') <> 'string'
       or coalesce(jsonb_typeof(v_decision_evidence->'supplier_order_numbers'), '') <> 'array'
       or coalesce(jsonb_typeof(v_decision_evidence->'source_purchase_quantity'), '') <> 'number'
       or coalesce(jsonb_typeof(v_decision_evidence->'persisted_quantity'), '') <> 'number'
       or coalesce(jsonb_typeof(v_decision_evidence->'source_total_minor'), '') <> 'number'
       or coalesce(jsonb_typeof(v_decision_evidence->'persisted_total_minor'), '') <> 'number'
       or coalesce(jsonb_typeof(v_decision_evidence->'currency_code'), '') <> 'string' then
      raise exception 'Confirmed decision evidence has missing or mistyped source fields.'
        using errcode = '22023';
    end if;
    if length(btrim(v_decision_evidence->>'source_line_key')) not between 1 and 512
       or coalesce(v_decision_evidence->>'source_document_date', '')
         !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
       or jsonb_array_length(v_decision_evidence->'supplier_order_numbers')
         not between 1 and 64
       or coalesce(v_decision_evidence->>'source_purchase_quantity', '')
         !~ '^[0-9]+(\.[0-9]{1,6})?$'
       or coalesce(v_decision_evidence->>'persisted_quantity', '')
         !~ '^[0-9]+(\.[0-9]{1,6})?$'
       or coalesce(v_decision_evidence->>'source_total_minor', '')
         !~ '^[0-9]{1,18}$'
       or coalesce(v_decision_evidence->>'persisted_total_minor', '')
         !~ '^[0-9]{1,18}$'
       or coalesce(v_decision_evidence->>'currency_code', '') <> 'CLP' then
      raise exception 'Confirmed decision evidence has an invalid source date, quantity, total, or non-CLP currency.'
        using errcode = '22023';
    end if;
    begin
      perform (v_decision_evidence->>'source_document_date')::date;
    exception when datetime_field_overflow then
      raise exception 'Confirmed decision evidence source date is invalid.'
        using errcode = '22023';
    end;
    if (v_decision_evidence->>'source_purchase_quantity')::numeric <= 0
       or (v_decision_evidence->>'persisted_quantity')::numeric <= 0 then
      raise exception 'Confirmed decision evidence quantities must be positive.'
        using errcode = '22023';
    end if;
    if exists (
      select 1
      from jsonb_array_elements(
        v_decision_evidence->'supplier_order_numbers'
      ) value
      where jsonb_typeof(value) <> 'string'
        or length(btrim(value #>> '{}')) not between 1 and 128
    ) or (
      select count(*) <> count(distinct btrim(value #>> '{}'))
      from jsonb_array_elements(
        v_decision_evidence->'supplier_order_numbers'
      ) value
    ) then
      raise exception 'Decision evidence supplier order numbers must be distinct bounded strings.'
        using errcode = '22023';
    end if;
  end if;
  if v_decision_source = 'operator_confirmed' and (
    coalesce(jsonb_typeof(v_decision_evidence->'confirmation_surface'), '') <> 'string'
    or length(btrim(v_decision_evidence->>'confirmation_surface')) not between 1 and 128
  ) then
    raise exception 'Operator confirmation surface is required.'
      using errcode = '22023';
  end if;
  if v_decision_source = 'invoice_confirmed' and coalesce(
    v_decision_evidence->>'purchase_invoice_id', ''
  ) !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' then
    raise exception 'Invoice-confirmed evidence requires a purchase invoice ID.'
      using errcode = '22023';
  end if;
  if v_decision_source = 'administrative_correction' and (
    coalesce(jsonb_typeof(v_decision_evidence->'actor_note'), '') <> 'string'
    or length(btrim(v_decision_evidence->>'actor_note')) not between 1 and 2000
  ) then
    raise exception 'Administrative correction requires an actor note.'
      using errcode = '22023';
  end if;
  if v_decision_source = 'migration_confirmed' and (
    coalesce(v_decision_evidence->>'migration_version', '') !~ '^[0-9]{14}$'
    or coalesce(jsonb_typeof(v_decision_evidence->'source_reference'), '') <> 'string'
    or length(btrim(v_decision_evidence->>'source_reference')) not between 1 and 512
    or coalesce(jsonb_typeof(v_decision_evidence->'actor_note'), '') <> 'string'
    or length(btrim(v_decision_evidence->>'actor_note')) not between 1 and 2000
  ) then
    raise exception 'Migration confirmation requires version, source reference, and actor note.'
      using errcode = '22023';
  end if;
  v_decision_evidence_hash := public.supplier_resolution_sha256(
    v_decision_evidence
  );
  if v_reason is not null and length(v_reason) > 1000 then
    raise exception 'Resolution correction reason is too long.'
      using errcode = '22023';
  end if;

  if v_action = 'revoke' then
    if v_kind is not null
       or coalesce(jsonb_array_length(coalesce(p_edges, '[]'::jsonb)), 0) <> 0 then
      raise exception 'A revoked revision cannot carry a kind or product edges.'
        using errcode = '22023';
    end if;
  else
    if v_kind not in ('single', 'homogeneous', 'composite') then
      raise exception 'Resolution kind must be single, homogeneous, or composite.'
        using errcode = '22023';
    end if;
    if p_edges is null or jsonb_typeof(p_edges) <> 'array' then
      raise exception 'Resolution edges must be a JSON array.'
        using errcode = '22023';
    end if;
    if jsonb_array_length(p_edges) < 1 or jsonb_array_length(p_edges) > 32 then
      raise exception 'A resolution requires between 1 and 32 product edges.'
        using errcode = '22023';
    end if;

    if exists (
      select 1
      from jsonb_array_elements(p_edges) edge(value)
      where jsonb_typeof(edge.value) <> 'object'
        or coalesce(edge.value->>'edge_ordinal', '') !~ '^[1-9][0-9]*$'
        or coalesce(edge.value->>'product_id', '')
          !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
        or coalesce(edge.value->>'catalog_units_per_purchase', '')
          !~ '^[1-9][0-9]{0,6}$'
        or coalesce(edge.value->>'allocation_ratio', '')
          !~ '^(0(\.[0-9]{1,12})?|1(\.0{1,12})?)$'
        or lower(btrim(coalesce(edge.value->>'component_role', '')))
          !~ '^[a-z0-9][a-z0-9_.:-]*$'
    ) then
      raise exception 'Resolution edge shape is invalid.'
        using errcode = '22023';
    end if;
    if exists (
      select 1
      from jsonb_array_elements(p_edges) edge(value)
      where (edge.value->>'catalog_units_per_purchase')::integer > 1000000
    ) then
      raise exception 'Catalog units per supplier purchase exceed the supported limit.'
        using errcode = '22023';
    end if;

    select
      jsonb_agg(
        jsonb_build_object(
          'edge_ordinal', (edge.value->>'edge_ordinal')::integer,
          'product_id', lower(edge.value->>'product_id'),
          'catalog_units_per_purchase',
            (edge.value->>'catalog_units_per_purchase')::integer,
          'allocation_ratio',
            (edge.value->>'allocation_ratio')::numeric(18,12),
          'component_role', lower(btrim(edge.value->>'component_role'))
        )
        order by (edge.value->>'edge_ordinal')::integer
      ),
      count(*)::integer,
      count(distinct (edge.value->>'edge_ordinal')::integer)::integer,
      min((edge.value->>'edge_ordinal')::integer),
      max((edge.value->>'edge_ordinal')::integer),
      sum((edge.value->>'allocation_ratio')::numeric(18,12))
    into
      v_edges,
      v_edge_count,
      v_distinct_ordinals,
      v_min_ordinal,
      v_max_ordinal,
      v_allocation_sum
    from jsonb_array_elements(p_edges) edge(value);

    if v_distinct_ordinals <> v_edge_count
       or v_min_ordinal <> 1
       or v_max_ordinal <> v_edge_count then
      raise exception 'Resolution edge ordinals must be unique and contiguous from 1.'
        using errcode = '22023';
    end if;
    if v_allocation_sum <> 1::numeric then
      raise exception 'Resolution allocation ratios must sum exactly to 1.'
        using errcode = '22023';
    end if;
    if v_kind in ('single', 'homogeneous') and v_edge_count <> 1 then
      raise exception 'Single and homogeneous resolutions require exactly one edge.'
        using errcode = '22023';
    end if;
    if v_kind = 'single' and (
      (v_edges->0->>'catalog_units_per_purchase')::integer <> 1
      or (v_edges->0->>'allocation_ratio')::numeric <> 1
    ) then
      raise exception 'A single resolution must contain one catalog unit at ratio 1.'
        using errcode = '22023';
    end if;
    if v_kind = 'composite' and v_edge_count < 2 then
      raise exception 'A composite resolution requires at least two edges.'
        using errcode = '22023';
    end if;

  end if;

  v_edge_set_hash := public.supplier_resolution_sha256(v_edges);
  v_request_fingerprint := public.supplier_resolution_sha256(
    jsonb_build_object(
      'supplier_id', p_supplier_id,
      'listing_id', v_listing_id,
      'variant_key', v_variant_key,
      'option_evidence_hash', v_option_hash,
      'option_pack_count', p_option_pack_count,
      'option_unit_class', v_option_unit_class,
      'pack_evidence_conflict', v_pack_conflict,
      'action', v_action,
      'resolution_kind', v_kind,
      'edges', v_edges,
      'expected_prior_revision_id', p_expected_prior_revision_id,
      'correction_reason', v_reason,
      'decision_source', v_decision_source,
      'decision_evidence_hash', v_decision_evidence_hash
    )
  );

  select
    revision.id, revision.tenant_id, revision.supplier_id,
    revision.listing_id, revision.variant_key, revision.revision_number,
    revision.state, revision.resolution_kind, revision.option_evidence_hash,
    revision.option_pack_count, revision.option_unit_class,
    revision.pack_evidence_conflict, revision.edge_set_hash,
    revision.operation_id, revision.request_fingerprint,
    revision.supersedes_revision_id, revision.correction_reason,
    revision.decision_source, revision.decision_evidence,
    revision.decision_evidence_hash, revision.created_by, revision.created_at
  into v_existing_operation
  from public.supplier_variant_resolution_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.operation_id = p_operation_id;
  if found then
    if v_existing_operation.request_fingerprint <> v_request_fingerprint then
      raise exception 'Resolution operation ID belongs to another request.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_existing_operation)
      || jsonb_build_object(
        'edges', coalesce((
          select jsonb_agg(to_jsonb(edge) order by edge.edge_ordinal)
          from public.supplier_variant_resolution_edges edge
          where edge.tenant_id = v_tenant_id
            and edge.revision_id = v_existing_operation.id
        ), '[]'::jsonb),
        'replayed', true
      );
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':' || p_supplier_id::text || ':'
      || v_listing_id || ':' || v_variant_key,
    0
  ));

  select
    revision.id, revision.tenant_id, revision.supplier_id,
    revision.listing_id, revision.variant_key, revision.revision_number,
    revision.state, revision.resolution_kind, revision.option_evidence_hash,
    revision.option_pack_count, revision.option_unit_class,
    revision.pack_evidence_conflict, revision.edge_set_hash,
    revision.operation_id, revision.request_fingerprint,
    revision.supersedes_revision_id, revision.correction_reason,
    revision.decision_source, revision.decision_evidence,
    revision.decision_evidence_hash, revision.created_by, revision.created_at
  into v_existing_operation
  from public.supplier_variant_resolution_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.operation_id = p_operation_id;
  if found then
    if v_existing_operation.request_fingerprint <> v_request_fingerprint then
      raise exception 'Resolution operation ID belongs to another request.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_existing_operation)
      || jsonb_build_object(
        'edges', coalesce((
          select jsonb_agg(to_jsonb(edge) order by edge.edge_ordinal)
          from public.supplier_variant_resolution_edges edge
          where edge.tenant_id = v_tenant_id
            and edge.revision_id = v_existing_operation.id
        ), '[]'::jsonb),
        'replayed', true
      );
  end if;

  if not exists (
    select 1
    from public.suppliers supplier
    where supplier.tenant_id = v_tenant_id
      and supplier.id = p_supplier_id
      and supplier.is_active is true
  ) then
    raise exception 'An active supplier was not found in the authenticated tenant.'
      using errcode = 'P0002';
  end if;
  if v_action = 'activate' and (
    select count(*)
    from jsonb_array_elements(v_edges) edge(value)
    where public.supplier_resolution_product_target_is_valid(
      v_tenant_id,
      (edge.value->>'product_id')::uuid,
      v_kind
    )
  ) <> v_edge_count then
    raise exception 'Every resolution edge must reference an active non-service valid catalog target; composite edges cannot target sets.'
      using errcode = '23514';
  end if;

  select
    revision.id, revision.tenant_id, revision.supplier_id,
    revision.listing_id, revision.variant_key, revision.revision_number,
    revision.state, revision.resolution_kind, revision.option_evidence_hash,
    revision.option_pack_count, revision.option_unit_class,
    revision.pack_evidence_conflict, revision.edge_set_hash,
    revision.operation_id, revision.request_fingerprint,
    revision.supersedes_revision_id, revision.correction_reason,
    revision.decision_source, revision.decision_evidence,
    revision.decision_evidence_hash, revision.created_by, revision.created_at
  into v_active
  from public.supplier_variant_resolution_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.supplier_id = p_supplier_id
    and revision.listing_id = v_listing_id
    and revision.variant_key = v_variant_key
    and revision.state = 'active'
  for update;

  select
    revision.id, revision.tenant_id, revision.supplier_id,
    revision.listing_id, revision.variant_key, revision.revision_number,
    revision.state, revision.resolution_kind, revision.option_evidence_hash,
    revision.option_pack_count, revision.option_unit_class,
    revision.pack_evidence_conflict, revision.edge_set_hash,
    revision.operation_id, revision.request_fingerprint,
    revision.supersedes_revision_id, revision.correction_reason,
    revision.decision_source, revision.decision_evidence,
    revision.decision_evidence_hash, revision.created_by, revision.created_at
  into v_latest
  from public.supplier_variant_resolution_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.supplier_id = p_supplier_id
    and revision.listing_id = v_listing_id
    and revision.variant_key = v_variant_key
  order by revision.revision_number desc
  limit 1;

  if v_action = 'revoke' then
    if v_active.id is null
       or p_expected_prior_revision_id is distinct from v_active.id
       or v_reason is null then
      raise exception 'Revocation requires the exact active revision and a reason.'
        using errcode = '40001';
    end if;
    v_prior_id := v_active.id;
    v_correction_action := 'revocation';
  elsif v_active.id is not null then
    if p_expected_prior_revision_id is distinct from v_active.id
       or v_reason is null then
      raise exception 'Replacing an active resolution requires its exact revision and a reason.'
        using errcode = '40001';
    end if;
    v_prior_id := v_active.id;
    v_correction_action := 'correction';
  elsif v_latest.id is not null then
    if p_expected_prior_revision_id is distinct from v_latest.id
       or v_reason is null then
      raise exception 'Reactivation requires the exact latest revision and a reason.'
        using errcode = '40001';
    end if;
    v_prior_id := v_latest.id;
    v_correction_action := 'reactivation';
  elsif p_expected_prior_revision_id is not null then
    raise exception 'No prior supplier resolution exists for the expected revision.'
      using errcode = '40001';
  end if;

  v_revision_number := coalesce(v_latest.revision_number, 0) + 1;

  if v_active.id is not null then
    perform set_config(
      'app.supplier_resolution_write_guard',
      txid_current()::text,
      true
    );
    update public.supplier_variant_resolution_revisions revision
    set state = 'superseded'
    where revision.tenant_id = v_tenant_id
      and revision.id = v_active.id;
    perform set_config('app.supplier_resolution_write_guard', '', true);
  end if;

  insert into public.supplier_variant_resolution_revisions (
    tenant_id,
    supplier_id,
    listing_id,
    variant_key,
    revision_number,
    state,
    resolution_kind,
    option_evidence_hash,
    option_pack_count,
    option_unit_class,
    pack_evidence_conflict,
    edge_set_hash,
    operation_id,
    request_fingerprint,
    supersedes_revision_id,
    correction_reason,
    decision_source,
    decision_evidence,
    decision_evidence_hash,
    created_by
  ) values (
    v_tenant_id,
    p_supplier_id,
    v_listing_id,
    v_variant_key,
    v_revision_number,
    case when v_action = 'revoke' then 'revoked' else 'active' end,
    case when v_action = 'revoke' then null else v_kind end,
    v_option_hash,
    p_option_pack_count,
    v_option_unit_class,
    v_pack_conflict,
    v_edge_set_hash,
    p_operation_id,
    v_request_fingerprint,
    v_prior_id,
    v_reason,
    v_decision_source,
    v_decision_evidence,
    v_decision_evidence_hash,
    auth.uid()
  ) returning * into v_new;

  if v_action = 'activate' then
    insert into public.supplier_variant_resolution_edges (
      tenant_id,
      revision_id,
      edge_ordinal,
      product_id,
      catalog_units_per_purchase,
      allocation_ratio,
      component_role
    )
    select
      v_tenant_id,
      v_new.id,
      (edge.value->>'edge_ordinal')::integer,
      (edge.value->>'product_id')::uuid,
      (edge.value->>'catalog_units_per_purchase')::integer,
      (edge.value->>'allocation_ratio')::numeric(18,12),
      edge.value->>'component_role'
    from jsonb_array_elements(v_edges) edge(value)
    order by (edge.value->>'edge_ordinal')::integer;
  end if;

  if v_prior_id is not null then
    insert into public.supplier_variant_resolution_corrections (
      tenant_id,
      prior_revision_id,
      replacement_revision_id,
      correction_action,
      operation_id,
      reason,
      created_by
    ) values (
      v_tenant_id,
      v_prior_id,
      v_new.id,
      v_correction_action,
      p_operation_id,
      v_reason,
      auth.uid()
    );
  end if;

  return to_jsonb(v_new)
    || jsonb_build_object(
      'edges', coalesce((
        select jsonb_agg(to_jsonb(edge) order by edge.edge_ordinal)
        from public.supplier_variant_resolution_edges edge
        where edge.tenant_id = v_tenant_id
          and edge.revision_id = v_new.id
      ), '[]'::jsonb),
      'replayed', false
    );
end;
$$;

create or replace function public.resolve_supplier_variant_resolution(
  p_supplier_id uuid,
  p_item_id text,
  p_product_url text,
  p_variant_key text,
  p_option_evidence_hash text,
  p_option_pack_count integer,
  p_option_unit_class text,
  p_pack_evidence_conflict boolean
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_listing_id text;
  v_variant_key text;
  v_option_hash text := lower(regexp_replace(
    btrim(coalesce(p_option_evidence_hash, '')),
    '^sha-?256:',
    ''
  ));
  v_option_unit_class text;
  v_pack_conflict boolean := coalesce(p_pack_evidence_conflict, false);
  v_latest public.supplier_variant_resolution_revisions%rowtype;
  v_edges jsonb;
  v_edge_count integer;
  v_active_product_count integer;
  v_allocation_sum numeric;
  v_legacy_id uuid;
  v_legacy_product_id uuid;
begin
  if v_tenant_id is null or auth.uid() is null then
    raise exception 'Authenticated tenant context is required.'
      using errcode = '42501';
  end if;
  if p_supplier_id is null then
    raise exception 'Supplier is required.' using errcode = '22004';
  end if;
  perform public.assert_supplier_product_identity_access(v_tenant_id, false);

  v_listing_id := public.normalize_supplier_listing_id(p_item_id, p_product_url);
  v_variant_key := public.normalize_immutable_supplier_variant_key(p_variant_key);
  if v_option_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'Option evidence must be a SHA-256 hex digest.'
      using errcode = '22023';
  end if;
  v_option_unit_class := public.normalize_supplier_option_unit_class(
    p_option_unit_class
  );

  if not exists (
    select 1
    from public.suppliers supplier
    where supplier.tenant_id = v_tenant_id
      and supplier.id = p_supplier_id
      and supplier.is_active is true
  ) then
    return jsonb_build_object(
      'status', 'supplier_inactive',
      'authoritative', false,
      'edges', '[]'::jsonb
    );
  end if;

  if v_option_hash <> public.supplier_option_evidence_v1_hash(
    v_variant_key,
    p_option_pack_count,
    v_option_unit_class,
    v_pack_conflict
  ) then
    return jsonb_build_object(
      'status', 'invalid_option_evidence',
      'authoritative', false,
      'edges', '[]'::jsonb
    );
  end if;
  if v_pack_conflict then
    return jsonb_build_object(
      'status', 'pack_evidence_conflict',
      'authoritative', false,
      'edges', '[]'::jsonb
    );
  end if;

  select
    revision.id, revision.tenant_id, revision.supplier_id,
    revision.listing_id, revision.variant_key, revision.revision_number,
    revision.state, revision.resolution_kind, revision.option_evidence_hash,
    revision.option_pack_count, revision.option_unit_class,
    revision.pack_evidence_conflict, revision.edge_set_hash,
    revision.operation_id, revision.request_fingerprint,
    revision.supersedes_revision_id, revision.correction_reason,
    revision.decision_source, revision.decision_evidence,
    revision.decision_evidence_hash, revision.created_by, revision.created_at
  into v_latest
  from public.supplier_variant_resolution_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.supplier_id = p_supplier_id
    and revision.listing_id = v_listing_id
    and revision.variant_key = v_variant_key
  order by revision.revision_number desc
  limit 1;

  if v_latest.id is not null then
    if v_latest.state = 'revoked' then
      return jsonb_build_object(
        'status', 'revoked',
        'authoritative', false,
        'revision_id', v_latest.id,
        'edges', '[]'::jsonb
      );
    end if;
    if v_latest.state <> 'active' then
      return jsonb_build_object(
        'status', 'contradictory_revision_state',
        'authoritative', false,
        'revision_id', v_latest.id,
        'edges', '[]'::jsonb
      );
    end if;
    if v_latest.option_evidence_hash <> v_option_hash
       or v_latest.option_pack_count is distinct from p_option_pack_count
       or v_latest.option_unit_class <> v_option_unit_class
       or v_latest.pack_evidence_conflict <> v_pack_conflict then
      return jsonb_build_object(
        'status', 'option_evidence_changed',
        'authoritative', false,
        'revision_id', v_latest.id,
        'edges', '[]'::jsonb
      );
    end if;

    select
      coalesce(jsonb_agg(
        jsonb_build_object(
          'edge_id', edge.id,
          'edge_ordinal', edge.edge_ordinal,
          'product_id', edge.product_id,
          'catalog_units_per_purchase', edge.catalog_units_per_purchase,
          'allocation_ratio', edge.allocation_ratio,
          'component_role', edge.component_role
        ) order by edge.edge_ordinal
      ), '[]'::jsonb),
      count(*)::integer,
      count(*) filter (
        where public.supplier_resolution_product_target_is_valid(
          v_tenant_id,
          edge.product_id,
          v_latest.resolution_kind
        )
      )::integer,
      coalesce(sum(edge.allocation_ratio), 0)
    into v_edges, v_edge_count, v_active_product_count, v_allocation_sum
    from public.supplier_variant_resolution_edges edge
    where edge.tenant_id = v_tenant_id
      and edge.revision_id = v_latest.id;

    if v_active_product_count <> v_edge_count
       or v_edge_count = 0
       or v_allocation_sum <> 1::numeric
       or (v_latest.resolution_kind in ('single', 'homogeneous') and v_edge_count <> 1)
       or (v_latest.resolution_kind = 'composite' and v_edge_count < 2) then
      return jsonb_build_object(
        'status', 'inactive_or_contradictory_edges',
        'authoritative', false,
        'revision_id', v_latest.id,
        'edges', '[]'::jsonb
      );
    end if;

    -- Rebuild exactly the canonical edge payload used by the revision hash.
    if public.supplier_resolution_sha256(coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'edge_ordinal', edge.edge_ordinal,
          'product_id', edge.product_id::text,
          'catalog_units_per_purchase', edge.catalog_units_per_purchase,
          'allocation_ratio', edge.allocation_ratio,
          'component_role', edge.component_role
        ) order by edge.edge_ordinal
      )
      from public.supplier_variant_resolution_edges edge
      where edge.tenant_id = v_tenant_id
        and edge.revision_id = v_latest.id
    ), '[]'::jsonb)) <> v_latest.edge_set_hash then
      return jsonb_build_object(
        'status', 'edge_snapshot_mismatch',
        'authoritative', false,
        'revision_id', v_latest.id,
        'edges', '[]'::jsonb
      );
    end if;

    return to_jsonb(v_latest)
      || jsonb_build_object(
        'status', 'resolved',
        'authoritative', true,
        'edges', v_edges
      );
  end if;

  select alias.id, alias.product_id
  into v_legacy_id, v_legacy_product_id
  from public.supplier_product_aliases alias
  join public.products product
    on product.tenant_id = alias.tenant_id
   and product.id = alias.product_id
   and product.is_active is true
   and product.product_type = 'product'
  where alias.tenant_id = v_tenant_id
    and alias.supplier_id = p_supplier_id
    and alias.listing_id = v_listing_id
    and alias.variant_key = v_variant_key;

  if v_legacy_id is not null then
    return jsonb_build_object(
      'status', 'legacy_candidate',
      'authoritative', false,
      'requires_confirmation', true,
      'legacy_alias_id', v_legacy_id,
      'listing_id', v_listing_id,
      'variant_key', v_variant_key,
      'edges', jsonb_build_array(jsonb_build_object(
        'edge_ordinal', 1,
        'product_id', v_legacy_product_id,
        'catalog_units_per_purchase', 1,
        'allocation_ratio', 1,
        'component_role', 'legacy_candidate'
      ))
    );
  end if;

  return null;
end;
$$;

create or replace function public.prepare_purchase_invoice_source_resolution(
  p_operation_id uuid,
  p_revision_id uuid,
  p_source_line_key text,
  p_source_row_index integer,
  p_source_purchase_quantity numeric,
  p_source_line_total_minor bigint,
  p_currency_code text,
  p_source_order_numbers text[],
  p_source_title text,
  p_selected_option text,
  p_raw_pack_count integer,
  p_raw_unit_token text,
  p_pack_evidence_conflict boolean,
  p_source_snapshot jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_source_line_key text := btrim(coalesce(p_source_line_key, ''));
  v_currency text := upper(btrim(coalesce(p_currency_code, 'CLP')));
  v_source_orders text[];
  v_source_title text := btrim(coalesce(p_source_title, ''));
  v_source_document_date date;
  v_selected_option text := nullif(btrim(coalesce(p_selected_option, '')), '');
  v_raw_unit_token text := nullif(
    lower(btrim(coalesce(p_raw_unit_token, ''))),
    ''
  );
  v_option_unit_class text;
  v_pack_conflict boolean := coalesce(p_pack_evidence_conflict, false);
  v_source_snapshot jsonb;
  v_source_snapshot_hash text;
  v_revision public.supplier_variant_resolution_revisions%rowtype;
  v_existing public.purchase_invoice_source_resolutions%rowtype;
  v_source public.purchase_invoice_source_resolutions%rowtype;
  v_request_fingerprint text;
  v_edge_count integer;
  v_compatible_edge_count integer;
begin
  if v_tenant_id is null or auth.uid() is null then
    raise exception 'Authenticated tenant context is required.'
      using errcode = '42501';
  end if;
  if p_operation_id is null or p_revision_id is null then
    raise exception 'Operation and supplier resolution revision are required.'
      using errcode = '22004';
  end if;
  perform public.assert_supplier_product_identity_access(v_tenant_id, true);

  if length(v_source_line_key) < 1 or length(v_source_line_key) > 512 then
    raise exception 'A stable source line key is required.'
      using errcode = '22023';
  end if;
  if p_source_row_index is null or p_source_row_index < 0 then
    raise exception 'A non-negative source row index is required.'
      using errcode = '22023';
  end if;
  if p_source_purchase_quantity is null
     or p_source_purchase_quantity <= 0
     or p_source_purchase_quantity > 1000000000
     or round(p_source_purchase_quantity, 6) <> p_source_purchase_quantity then
    raise exception 'Source purchase quantity must be positive with at most 6 decimals.'
      using errcode = '22023';
  end if;
  if p_source_line_total_minor is null or p_source_line_total_minor < 0 then
    raise exception 'Source line total in minor units cannot be negative.'
      using errcode = '22023';
  end if;
  if v_currency <> 'CLP' then
    raise exception 'Supplier-resolution invoice provenance supports CLP only.'
      using errcode = '22023';
  end if;
  if v_source_title = '' or length(v_source_title) > 2000 then
    raise exception 'A bounded supplier source title is required.'
      using errcode = '22023';
  end if;
  if v_selected_option is not null and length(v_selected_option) > 1000 then
    raise exception 'Selected supplier option is too long.'
      using errcode = '22023';
  end if;
  if p_raw_pack_count is not null and (
    p_raw_pack_count <= 0 or p_raw_pack_count > 1000000
  ) then
    raise exception 'Raw pack count is invalid.'
      using errcode = '22023';
  end if;
  if v_raw_unit_token is not null and (
    length(v_raw_unit_token) > 32
    or v_raw_unit_token !~ '^[a-z0-9][a-z0-9_.:-]*$'
  ) then
    raise exception 'Raw supplier unit token is invalid.'
      using errcode = '22023';
  end if;
  v_option_unit_class := public.normalize_supplier_option_unit_class(
    v_raw_unit_token
  );
  if p_source_order_numbers is null
     or cardinality(p_source_order_numbers) < 1
     or cardinality(p_source_order_numbers) > 64
     or array_position(p_source_order_numbers, null) is not null then
    raise exception 'At least one bounded supplier order number is required.'
      using errcode = '22023';
  end if;

  select array_agg(value order by value)
  into v_source_orders
  from (
    select distinct btrim(source_order) as value
    from unnest(p_source_order_numbers) source_order
    where length(btrim(source_order)) between 1 and 128
  ) normalized_orders;
  if coalesce(cardinality(v_source_orders), 0) < 1
     or cardinality(v_source_orders) <> cardinality(p_source_order_numbers) then
    raise exception 'Supplier order numbers must be distinct, non-empty, and bounded.'
      using errcode = '22023';
  end if;

  if p_source_snapshot is null
     or jsonb_typeof(p_source_snapshot) <> 'object'
     or octet_length(p_source_snapshot::text) > 32768 then
    raise exception 'A bounded sanitized source snapshot object is required.'
      using errcode = '22023';
  end if;
  if jsonb_path_exists(
    p_source_snapshot,
    '$.** ? (@.type() == "object").keyvalue() ? (@.key like_regex "^(email|phone|address|recipient|buyer|credential|cookie|token|authorization|payment|card)$" flag "i")'
  ) then
    raise exception 'Source snapshot contains a forbidden sensitive field.'
      using errcode = '22023';
  end if;

  select
    revision.id, revision.tenant_id, revision.supplier_id,
    revision.listing_id, revision.variant_key, revision.revision_number,
    revision.state, revision.resolution_kind, revision.option_evidence_hash,
    revision.option_pack_count, revision.option_unit_class,
    revision.pack_evidence_conflict, revision.edge_set_hash,
    revision.operation_id, revision.request_fingerprint,
    revision.supersedes_revision_id, revision.correction_reason,
    revision.decision_source, revision.decision_evidence,
    revision.decision_evidence_hash, revision.created_by, revision.created_at
  into v_revision
  from public.supplier_variant_resolution_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.id = p_revision_id
  for share;
  if not found then
    raise exception 'A supplier resolution revision is required.'
      using errcode = 'P0002';
  end if;
  if v_pack_conflict then
    raise exception 'Conflicting pack evidence cannot be staged on an invoice.'
      using errcode = '23514';
  end if;
  if v_revision.option_pack_count is distinct from p_raw_pack_count
     or v_revision.option_unit_class <> v_option_unit_class
     or v_revision.pack_evidence_conflict <> v_pack_conflict then
    raise exception 'Raw pack evidence does not match the resolution revision.'
      using errcode = '23514';
  end if;

  if not (p_source_snapshot ?& array[
    'listing_id',
    'variant_key',
    'option_evidence_hash',
    'source_row_index',
    'source_document_date',
    'source_line_key',
    'source_order_numbers',
    'source_title',
    'selected_option',
    'raw_pack_count',
    'raw_unit_code',
    'option_unit_class',
    'pack_evidence_conflict',
    'source_purchase_quantity',
    'source_line_total_minor',
    'currency_code'
  ]) then
    raise exception 'Source snapshot is missing canonical provenance fields.'
      using errcode = '23514';
  end if;
  if coalesce(jsonb_typeof(p_source_snapshot->'source_document_date'), '')
       <> 'string'
     or coalesce(p_source_snapshot->>'source_document_date', '')
       !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception 'Source snapshot document date must be an ISO civil date.'
      using errcode = '23514';
  end if;
  begin
    v_source_document_date :=
      (p_source_snapshot->>'source_document_date')::date;
  exception
    when datetime_field_overflow or invalid_datetime_format then
      raise exception 'Source snapshot document date is invalid.'
        using errcode = '23514';
  end;
  if to_char(v_source_document_date, 'YYYY-MM-DD')
       <> p_source_snapshot->>'source_document_date' then
    raise exception 'Source snapshot document date is not canonical.'
      using errcode = '23514';
  end if;
  if p_source_snapshot->'listing_id' <> to_jsonb(v_revision.listing_id)
     or p_source_snapshot->'variant_key' <> to_jsonb(v_revision.variant_key) then
    raise exception 'Source snapshot listing/variant does not match the resolution revision.'
      using errcode = '23514';
  end if;
  if p_source_snapshot->'option_evidence_hash'
       <> to_jsonb(v_revision.option_evidence_hash) then
    raise exception 'Source snapshot option evidence does not match the resolution revision.'
      using errcode = '23514';
  end if;
  if public.supplier_option_evidence_v1_hash(
    v_revision.variant_key,
    p_raw_pack_count,
    v_option_unit_class,
    v_pack_conflict
  ) <> v_revision.option_evidence_hash then
    raise exception 'Raw pack evidence does not reproduce the resolution option hash.'
      using errcode = '23514';
  end if;
  if p_source_snapshot->'source_row_index' <> to_jsonb(p_source_row_index)
     or p_source_snapshot->'source_document_date'
       <> to_jsonb(to_char(v_source_document_date, 'YYYY-MM-DD'))
     or p_source_snapshot->'source_line_key' <> to_jsonb(v_source_line_key)
     or p_source_snapshot->'source_order_numbers' <> to_jsonb(v_source_orders)
     or p_source_snapshot->'source_title' <> to_jsonb(v_source_title)
     or p_source_snapshot->'selected_option' is distinct from
       coalesce(to_jsonb(v_selected_option), 'null'::jsonb)
     or p_source_snapshot->'raw_pack_count' is distinct from
       coalesce(to_jsonb(p_raw_pack_count), 'null'::jsonb)
     or p_source_snapshot->'raw_unit_code' is distinct from
       coalesce(to_jsonb(v_raw_unit_token), 'null'::jsonb)
     or p_source_snapshot->'option_unit_class' <> to_jsonb(v_option_unit_class)
     or p_source_snapshot->'pack_evidence_conflict' <> to_jsonb(v_pack_conflict)
     or p_source_snapshot->'source_purchase_quantity'
       <> to_jsonb(p_source_purchase_quantity)
     or p_source_snapshot->'source_line_total_minor'
       <> to_jsonb(p_source_line_total_minor)
     or p_source_snapshot->'currency_code' <> to_jsonb(v_currency) then
    raise exception 'Source snapshot does not exactly reproduce its staged source fields.'
      using errcode = '23514';
  end if;

  v_source_snapshot := p_source_snapshot
    || jsonb_build_object(
      'listing_id', v_revision.listing_id,
      'variant_key', v_revision.variant_key,
      'option_evidence_hash', v_revision.option_evidence_hash,
      'source_row_index', p_source_row_index,
      'source_document_date', to_char(v_source_document_date, 'YYYY-MM-DD'),
      'source_line_key', v_source_line_key,
      'source_order_numbers', to_jsonb(v_source_orders),
      'source_title', v_source_title,
      'selected_option', v_selected_option,
      'raw_pack_count', p_raw_pack_count,
      'raw_unit_code', v_raw_unit_token,
      'option_unit_class', v_option_unit_class,
      'pack_evidence_conflict', v_pack_conflict,
      'source_purchase_quantity', p_source_purchase_quantity,
      'source_line_total_minor', p_source_line_total_minor,
      'currency_code', v_currency
    );
  if octet_length(v_source_snapshot::text) > 32768 then
    raise exception 'Canonical source snapshot exceeds the size limit.'
      using errcode = '22023';
  end if;
  v_source_snapshot_hash := public.supplier_resolution_sha256(v_source_snapshot);

  v_request_fingerprint := public.supplier_resolution_sha256(
    jsonb_build_object(
      'revision_id', p_revision_id,
      'source_line_key', v_source_line_key,
      'source_row_index', p_source_row_index,
      'source_document_date', to_char(v_source_document_date, 'YYYY-MM-DD'),
      'source_purchase_quantity', p_source_purchase_quantity::numeric(18,6),
      'source_line_total_minor', p_source_line_total_minor,
      'currency_code', v_currency,
      'source_snapshot_hash', v_source_snapshot_hash
    )
  );

  select
    source.id, source.tenant_id, source.purchase_invoice_id,
    source.source_line_key, source.source_row_index,
    source.source_document_date, source.supplier_resolution_revision_id,
    source.supplier_listing_id, source.supplier_variant_key,
    source.option_evidence_hash, source.edge_set_hash,
    source.source_order_numbers, source.source_title, source.selected_option,
    source.raw_pack_count, source.raw_unit_token, source.option_unit_class,
    source.pack_evidence_conflict, source.source_snapshot,
    source.source_snapshot_hash, source.source_purchase_quantity,
    source.source_line_total_minor, source.currency_code, source.operation_id,
    source.request_fingerprint, source.created_by, source.created_at,
    source.bound_at
  into v_existing
  from public.purchase_invoice_source_resolutions source
  where source.tenant_id = v_tenant_id
    and source.operation_id = p_operation_id;
  if found then
    if v_existing.request_fingerprint <> v_request_fingerprint then
      raise exception 'Source-resolution operation ID belongs to another request.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_existing)
      || jsonb_build_object(
        'components', coalesce((
          select jsonb_agg(to_jsonb(component) order by component.edge_ordinal)
          from public.purchase_invoice_source_components component
          where component.tenant_id = v_tenant_id
            and component.source_resolution_id = v_existing.id
        ), '[]'::jsonb),
        'replayed', true
      );
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':purchase-source:' || p_operation_id::text,
    0
  ));

  select
    source.id, source.tenant_id, source.purchase_invoice_id,
    source.source_line_key, source.source_row_index,
    source.source_document_date, source.supplier_resolution_revision_id,
    source.supplier_listing_id, source.supplier_variant_key,
    source.option_evidence_hash, source.edge_set_hash,
    source.source_order_numbers, source.source_title, source.selected_option,
    source.raw_pack_count, source.raw_unit_token, source.option_unit_class,
    source.pack_evidence_conflict, source.source_snapshot,
    source.source_snapshot_hash, source.source_purchase_quantity,
    source.source_line_total_minor, source.currency_code, source.operation_id,
    source.request_fingerprint, source.created_by, source.created_at,
    source.bound_at
  into v_existing
  from public.purchase_invoice_source_resolutions source
  where source.tenant_id = v_tenant_id
    and source.operation_id = p_operation_id;
  if found then
    if v_existing.request_fingerprint <> v_request_fingerprint then
      raise exception 'Source-resolution operation ID belongs to another request.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_existing)
      || jsonb_build_object(
        'components', coalesce((
          select jsonb_agg(to_jsonb(component) order by component.edge_ordinal)
          from public.purchase_invoice_source_components component
          where component.tenant_id = v_tenant_id
            and component.source_resolution_id = v_existing.id
        ), '[]'::jsonb),
        'replayed', true
      );
  end if;

  if v_revision.state <> 'active' or not exists (
    select 1
    from public.suppliers supplier
    where supplier.tenant_id = v_tenant_id
      and supplier.id = v_revision.supplier_id
      and supplier.is_active is true
  ) then
    raise exception 'An active supplier resolution revision and supplier are required.'
      using errcode = 'P0002';
  end if;
  select
    count(*)::integer,
    count(*) filter (
      where public.supplier_resolution_product_target_is_valid(
        v_tenant_id,
        edge.product_id,
        v_revision.resolution_kind
      )
    )::integer
  into v_edge_count, v_compatible_edge_count
  from public.supplier_variant_resolution_edges edge
  where edge.tenant_id = v_tenant_id
    and edge.revision_id = v_revision.id;

  if v_compatible_edge_count <> v_edge_count
     or v_edge_count = 0
     or (v_revision.resolution_kind in ('single', 'homogeneous') and v_edge_count <> 1)
     or (v_revision.resolution_kind = 'composite' and v_edge_count < 2) then
    raise exception 'Resolution edge set is inactive or contradictory.'
      using errcode = '23514';
  end if;
  if exists (
    select 1
    from public.supplier_variant_resolution_edges edge
    where edge.tenant_id = v_tenant_id
      and edge.revision_id = v_revision.id
      and p_source_purchase_quantity * edge.catalog_units_per_purchase
        > 999999999999.999999::numeric
  ) then
    raise exception 'Resolved component quantity exceeds the supported precision.'
      using errcode = '22003';
  end if;

  insert into public.purchase_invoice_source_resolutions (
    tenant_id,
    purchase_invoice_id,
    source_line_key,
    source_row_index,
    source_document_date,
    supplier_resolution_revision_id,
    supplier_listing_id,
    supplier_variant_key,
    option_evidence_hash,
    edge_set_hash,
    source_order_numbers,
    source_title,
    selected_option,
    raw_pack_count,
    raw_unit_token,
    option_unit_class,
    pack_evidence_conflict,
    source_snapshot,
    source_snapshot_hash,
    source_purchase_quantity,
    source_line_total_minor,
    currency_code,
    operation_id,
    request_fingerprint,
    created_by,
    bound_at
  ) values (
    v_tenant_id,
    null,
    v_source_line_key,
    p_source_row_index,
    v_source_document_date,
    v_revision.id,
    v_revision.listing_id,
    v_revision.variant_key,
    v_revision.option_evidence_hash,
    v_revision.edge_set_hash,
    v_source_orders,
    v_source_title,
    v_selected_option,
    p_raw_pack_count,
    v_raw_unit_token,
    v_option_unit_class,
    v_pack_conflict,
    v_source_snapshot,
    v_source_snapshot_hash,
    p_source_purchase_quantity::numeric(18,6),
    p_source_line_total_minor,
    v_currency,
    p_operation_id,
    v_request_fingerprint,
    auth.uid(),
    null
  ) returning * into v_source;

  insert into public.purchase_invoice_source_components (
    tenant_id,
    source_resolution_id,
    revision_edge_id,
    edge_ordinal,
    product_id,
    catalog_units_per_purchase,
    resolved_quantity,
    allocation_ratio,
    allocated_line_total_minor,
    component_role
  )
  with allocation_basis as (
    select
      edge.id,
      edge.edge_ordinal,
      edge.product_id,
      edge.catalog_units_per_purchase,
      edge.allocation_ratio,
      edge.component_role,
      floor(p_source_line_total_minor * edge.allocation_ratio)::bigint
        as base_minor,
      (p_source_line_total_minor * edge.allocation_ratio)
        - floor(p_source_line_total_minor * edge.allocation_ratio)
        as fractional_minor
    from public.supplier_variant_resolution_edges edge
    where edge.tenant_id = v_tenant_id
      and edge.revision_id = v_revision.id
  ), ranked as (
    select
      allocation_basis.id,
      allocation_basis.edge_ordinal,
      allocation_basis.product_id,
      allocation_basis.catalog_units_per_purchase,
      allocation_basis.allocation_ratio,
      allocation_basis.component_role,
      allocation_basis.base_minor,
      allocation_basis.fractional_minor,
      row_number() over (
        order by fractional_minor desc, edge_ordinal
      ) as remainder_rank,
      sum(base_minor) over () as base_total
    from allocation_basis
  )
  select
    v_tenant_id,
    v_source.id,
    ranked.id,
    ranked.edge_ordinal,
    ranked.product_id,
    ranked.catalog_units_per_purchase,
    (p_source_purchase_quantity * ranked.catalog_units_per_purchase)::numeric(18,6),
    ranked.allocation_ratio,
    ranked.base_minor + case
      when ranked.remainder_rank <= p_source_line_total_minor - ranked.base_total
        then 1
      else 0
    end,
    ranked.component_role
  from ranked
  order by ranked.edge_ordinal;

  return to_jsonb(v_source)
    || jsonb_build_object(
      'components', coalesce((
        select jsonb_agg(to_jsonb(component) order by component.edge_ordinal)
        from public.purchase_invoice_source_components component
        where component.tenant_id = v_tenant_id
          and component.source_resolution_id = v_source.id
      ), '[]'::jsonb),
      'replayed', false
    );
end;
$$;

create or replace function public.validate_purchase_invoice_supplier_resolution()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_item jsonb;
  v_has_provenance boolean := false;
  v_application_id uuid;
  v_revision_id uuid;
  v_product_id uuid;
  v_edge_ordinal integer;
  v_source public.purchase_invoice_source_resolutions%rowtype;
  v_revision public.supplier_variant_resolution_revisions%rowtype;
  v_component public.purchase_invoice_source_components%rowtype;
  v_item_quantity numeric;
  v_item_units integer;
  v_item_ratio numeric;
  v_item_source_quantity numeric;
  v_item_source_total bigint;
  v_item_allocated_total bigint;
  v_unit_cost numeric;
  v_discount numeric;
  v_calculated_total numeric;
  v_invoice_items_total numeric;
  v_required_keys text[] := array[
    'supplier_resolution_application_id',
    'supplier_resolution_revision_id',
    'source_line_key',
    'supplier_resolution_edge_ordinal',
    'supplier_resolution_component_role',
    'source_purchase_quantity',
    'catalog_units_per_purchase',
    'allocation_ratio',
    'source_line_total_minor',
    'allocated_line_total_minor',
    'source_row_index',
    'source_order_numbers',
    'supplier_listing_id',
    'supplier_variant_key',
    'option_evidence_hash',
    'source_title',
    'pack_evidence_conflict',
    'source_snapshot',
    'product_id',
    'quantity',
    'unit_cost'
  ];
  v_reserved_keys text[] := array[
    'supplier_resolution_application_id',
    'supplier_resolution_revision_id',
    'source_line_key',
    'supplier_resolution_edge_ordinal',
    'supplier_resolution_component_role',
    'source_purchase_quantity',
    'catalog_units_per_purchase',
    'allocation_ratio',
    'source_line_total_minor',
    'allocated_line_total_minor',
    'source_row_index',
    'source_order_numbers',
    'supplier_listing_id',
    'supplier_variant_key',
    'option_evidence_hash',
    'source_title',
    'selected_option',
    'raw_pack_count',
    'raw_unit_code',
    'pack_evidence_conflict',
    'source_snapshot'
  ];
begin
  if jsonb_typeof(new.items) <> 'array' then
    raise exception 'Purchase invoice items must be a JSON array.'
      using errcode = '22023';
  end if;

  select exists (
    select 1
    from jsonb_array_elements(new.items) item(value)
    where item.value ?| v_reserved_keys
  ) into v_has_provenance;

  if not v_has_provenance then
    if exists (
      select 1
      from public.purchase_invoice_source_resolutions source
      where source.tenant_id = new.tenant_id
        and source.purchase_invoice_id = new.id
    ) then
      raise exception 'A purchase invoice cannot discard bound supplier-resolution provenance.'
        using errcode = '23514';
    end if;
    return new;
  end if;

  if new.tenant_id is null then
    raise exception 'Supplier-resolution provenance requires an invoice tenant.'
      using errcode = '23514';
  end if;

  -- Supplier source totals are already landed CLP amounts. Reapplying tax,
  -- document-level discounts, or additional costs would account for money a
  -- second time. These checks cover the whole invoice, including ordinary
  -- (non-graph) lines in the same all-resolved OCR draft.
  if new.tax_treatment is distinct from 'no_tax'
     or coalesce(new.tax, 0) <> 0
     or coalesce(new.iva_amount, 0) <> 0 then
    raise exception 'Supplier-resolution invoices must use no-tax semantics.'
      using errcode = '23514';
  end if;
  if coalesce(new.discount_value, 0) <> 0
     or coalesce(new.discount_amount, 0) <> 0 then
    raise exception 'Supplier-resolution invoices cannot apply a global discount.'
      using errcode = '23514';
  end if;
  if jsonb_typeof(new.additional_costs) <> 'array'
     or new.additional_costs <> '[]'::jsonb then
    raise exception 'Supplier-resolution invoices cannot apply additional costs twice.'
      using errcode = '23514';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(new.items) item(value)
    where jsonb_typeof(item.value) <> 'object'
      or coalesce(item.value->>'quantity', '')
        !~ '^[0-9]+(\.[0-9]{1,6})?$'
      or coalesce(item.value->>'unit_cost', '')
        !~ '^[0-9]+(\.[0-9]+)?$'
      or coalesce(item.value->>'discount', '0')
        !~ '^[0-9]+(\.[0-9]+)?$'
      or (item.value->>'quantity')::numeric <= 0
      or (item.value->>'unit_cost')::numeric < 0
      or coalesce((item.value->>'discount')::numeric, 0) < 0
      or coalesce((item.value->>'discount')::numeric, 0)
        > (item.value->>'quantity')::numeric
          * (item.value->>'unit_cost')::numeric
  ) then
    raise exception 'Supplier-resolution invoice lines have invalid money inputs.'
      using errcode = '23514';
  end if;
  select round(coalesce(sum(
    (item.value->>'quantity')::numeric
      * (item.value->>'unit_cost')::numeric
      - coalesce((item.value->>'discount')::numeric, 0)
  ), 0))
  into v_invoice_items_total
  from jsonb_array_elements(new.items) item(value);
  if new.total is distinct from v_invoice_items_total
     or new.subtotal is distinct from v_invoice_items_total
     or new.net_amount is distinct from v_invoice_items_total then
    raise exception 'Supplier-resolution invoice header does not reconcile to its lines.'
      using errcode = '23514';
  end if;

  for v_item in
    select item.value
    from jsonb_array_elements(new.items) item(value)
    where item.value ?| v_reserved_keys
  loop
    if jsonb_typeof(v_item) <> 'object' or not (v_item ?& v_required_keys) then
      raise exception 'Supplier-resolution invoice provenance is incomplete.'
        using errcode = '23514';
    end if;
    if coalesce(v_item->>'supplier_resolution_application_id', '')
         !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
       or coalesce(v_item->>'supplier_resolution_revision_id', '')
         !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
       or coalesce(v_item->>'product_id', '')
         !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
       or coalesce(v_item->>'supplier_resolution_edge_ordinal', '')
         !~ '^[1-9][0-9]*$'
       or coalesce(v_item->>'supplier_resolution_component_role', '')
         !~ '^[a-z0-9][a-z0-9_.:-]*$'
       or coalesce(v_item->>'quantity', '') !~ '^[0-9]+(\.[0-9]{1,6})?$'
       or coalesce(v_item->>'source_purchase_quantity', '')
         !~ '^[0-9]+(\.[0-9]{1,6})?$'
       or coalesce(v_item->>'catalog_units_per_purchase', '')
         !~ '^[1-9][0-9]{0,6}$'
       or coalesce(v_item->>'allocation_ratio', '')
         !~ '^(0(\.[0-9]{1,12})?|1(\.0{1,12})?)$'
       or coalesce(v_item->>'source_line_total_minor', '') !~ '^[0-9]+$'
       or coalesce(v_item->>'allocated_line_total_minor', '') !~ '^[0-9]+$'
       or coalesce(v_item->>'source_row_index', '') !~ '^[0-9]+$'
       or jsonb_typeof(v_item->'source_order_numbers') <> 'array'
       or coalesce(v_item->>'supplier_listing_id', '') = ''
       or coalesce(v_item->>'supplier_variant_key', '') = ''
       or coalesce(v_item->>'option_evidence_hash', '') !~ '^[a-f0-9]{64}$'
       or coalesce(v_item->>'source_title', '') = ''
       or jsonb_typeof(v_item->'pack_evidence_conflict') <> 'boolean'
       or jsonb_typeof(v_item->'source_snapshot') <> 'object'
       or coalesce(v_item->>'unit_cost', '') !~ '^[0-9]+(\.[0-9]+)?$'
       or coalesce(v_item->>'source_line_key', '') = '' then
      raise exception 'Supplier-resolution invoice provenance has an invalid value.'
        using errcode = '23514';
    end if;

    v_application_id := (v_item->>'supplier_resolution_application_id')::uuid;
    v_revision_id := (v_item->>'supplier_resolution_revision_id')::uuid;
    v_product_id := (v_item->>'product_id')::uuid;
    v_edge_ordinal := (v_item->>'supplier_resolution_edge_ordinal')::integer;
    v_item_quantity := (v_item->>'quantity')::numeric;
    v_item_source_quantity := (v_item->>'source_purchase_quantity')::numeric;
    v_item_units := (v_item->>'catalog_units_per_purchase')::integer;
    v_item_ratio := (v_item->>'allocation_ratio')::numeric;
    v_item_source_total := (v_item->>'source_line_total_minor')::bigint;
    v_item_allocated_total := (v_item->>'allocated_line_total_minor')::bigint;
    v_unit_cost := (v_item->>'unit_cost')::numeric;
    v_discount := coalesce(nullif(v_item->>'discount', '')::numeric, 0);

    select
      source.id, source.tenant_id, source.purchase_invoice_id,
      source.source_line_key, source.source_row_index,
      source.source_document_date, source.supplier_resolution_revision_id,
      source.supplier_listing_id, source.supplier_variant_key,
      source.option_evidence_hash, source.edge_set_hash,
      source.source_order_numbers, source.source_title, source.selected_option,
      source.raw_pack_count, source.raw_unit_token, source.option_unit_class,
      source.pack_evidence_conflict, source.source_snapshot,
      source.source_snapshot_hash, source.source_purchase_quantity,
      source.source_line_total_minor, source.currency_code, source.operation_id,
      source.request_fingerprint, source.created_by, source.created_at,
      source.bound_at
    into v_source
    from public.purchase_invoice_source_resolutions source
    where source.tenant_id = new.tenant_id
      and source.id = v_application_id;
    if not found
       or (v_source.purchase_invoice_id is not null
           and v_source.purchase_invoice_id <> new.id) then
      raise exception 'Supplier-resolution source application is missing or bound elsewhere.'
        using errcode = '23514';
    end if;
    if (new.date at time zone 'UTC')::date
         is distinct from v_source.source_document_date
       or (
         new.supplier_invoice_date is not null
         and (new.supplier_invoice_date at time zone 'UTC')::date
           <> v_source.source_document_date
       ) then
      raise exception 'Invoice date does not match its staged supplier source date.'
        using errcode = '23514';
    end if;
    if v_source.purchase_invoice_id is null and new.status <> 'draft' then
      raise exception 'Unbound supplier-resolution evidence can only enter a draft invoice.'
        using errcode = '23514';
    end if;
    select
      revision.id, revision.tenant_id, revision.supplier_id,
      revision.listing_id, revision.variant_key, revision.revision_number,
      revision.state, revision.resolution_kind, revision.option_evidence_hash,
      revision.option_pack_count, revision.option_unit_class,
      revision.pack_evidence_conflict, revision.edge_set_hash,
      revision.operation_id, revision.request_fingerprint,
      revision.supersedes_revision_id, revision.correction_reason,
      revision.decision_source, revision.decision_evidence,
      revision.decision_evidence_hash, revision.created_by, revision.created_at
    into v_revision
    from public.supplier_variant_resolution_revisions revision
    where revision.tenant_id = new.tenant_id
      and revision.id = v_source.supplier_resolution_revision_id;
    if not found or new.supplier_id is distinct from v_revision.supplier_id then
      raise exception 'Invoice supplier does not match the supplier resolution.'
        using errcode = '23514';
    end if;
    if v_source.purchase_invoice_id is null and (
      v_revision.state <> 'active'
      or v_revision.option_evidence_hash <> v_source.option_evidence_hash
      or v_revision.edge_set_hash <> v_source.edge_set_hash
    ) then
      raise exception 'Only the exact active supplier resolution can be bound.'
        using errcode = '23514';
    end if;

    select
      component.id, component.tenant_id, component.source_resolution_id,
      component.revision_edge_id, component.edge_ordinal,
      component.product_id, component.catalog_units_per_purchase,
      component.resolved_quantity, component.allocation_ratio,
      component.allocated_line_total_minor, component.component_role,
      component.created_at
    into v_component
    from public.purchase_invoice_source_components component
    join public.supplier_variant_resolution_edges edge
      on edge.tenant_id = component.tenant_id
     and edge.id = component.revision_edge_id
     and edge.revision_id = v_source.supplier_resolution_revision_id
     and edge.edge_ordinal = component.edge_ordinal
     and edge.product_id = component.product_id
     and edge.catalog_units_per_purchase = component.catalog_units_per_purchase
     and edge.allocation_ratio = component.allocation_ratio
     and edge.component_role = component.component_role
    where component.tenant_id = new.tenant_id
      and component.source_resolution_id = v_source.id
      and component.edge_ordinal = v_edge_ordinal;
    if not found then
      raise exception 'Invoice component does not exist in the staged resolution edge set.'
        using errcode = '23514';
    end if;
    if v_source.purchase_invoice_id is null and not
      public.supplier_resolution_product_target_is_valid(
        new.tenant_id,
        v_component.product_id,
        v_revision.resolution_kind
      ) then
      raise exception 'Only active non-service resolution targets can be bound.'
        using errcode = '23514';
    end if;

    if v_revision_id <> v_source.supplier_resolution_revision_id
       or v_item->>'source_line_key' <> v_source.source_line_key
       or (v_item->>'source_row_index')::integer <> v_source.source_row_index
       or v_item->'source_order_numbers'
         is distinct from to_jsonb(v_source.source_order_numbers)
       or v_item->>'supplier_listing_id' <> v_source.supplier_listing_id
       or v_item->>'supplier_variant_key' <> v_source.supplier_variant_key
       or v_item->>'option_evidence_hash' <> v_source.option_evidence_hash
       or v_item->>'source_title' <> v_source.source_title
       or coalesce(v_item->'selected_option', 'null'::jsonb)
         <> coalesce(to_jsonb(v_source.selected_option), 'null'::jsonb)
       or coalesce(v_item->'raw_pack_count', 'null'::jsonb)
         <> coalesce(to_jsonb(v_source.raw_pack_count), 'null'::jsonb)
       or coalesce(v_item->'raw_unit_code', 'null'::jsonb)
         <> coalesce(to_jsonb(v_source.raw_unit_token), 'null'::jsonb)
       or (v_item->>'pack_evidence_conflict')::boolean
         <> v_source.pack_evidence_conflict
       or v_item->'source_snapshot' <> v_source.source_snapshot
       or v_product_id <> v_component.product_id
       or v_item->>'supplier_resolution_component_role'
         <> v_component.component_role
       or v_item_source_quantity <> v_source.source_purchase_quantity
       or v_item_units <> v_component.catalog_units_per_purchase
       or v_item_quantity <> v_component.resolved_quantity
       or v_item_quantity <> v_item_source_quantity * v_item_units
       or v_item_ratio <> v_component.allocation_ratio
       or v_item_source_total <> v_source.source_line_total_minor
       or v_item_allocated_total <> v_component.allocated_line_total_minor then
      raise exception 'Invoice item drifted from its staged supplier-resolution snapshot.'
        using errcode = '23514';
    end if;

    if v_discount < 0 or v_discount > v_item_quantity * v_unit_cost then
      raise exception 'Supplier-resolution invoice discount is invalid.'
        using errcode = '23514';
    end if;
    v_calculated_total := round(
      v_item_quantity * v_unit_cost - v_discount
    );
    if abs(v_calculated_total - v_item_allocated_total) > 1 then
      raise exception 'Invoice item cost does not reconcile to its allocated source total.'
        using errcode = '23514';
    end if;
  end loop;

  if exists (
    select 1
    from (
      select
        (item.value->>'supplier_resolution_application_id')::uuid as application_id,
        (item.value->>'supplier_resolution_edge_ordinal')::integer as edge_ordinal,
        count(*) as occurrences
      from jsonb_array_elements(new.items) item(value)
      where item.value ? 'supplier_resolution_application_id'
      group by 1, 2
    ) duplicate
    where duplicate.occurrences <> 1
  ) then
    raise exception 'Each supplier-resolution edge must appear exactly once per source line.'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from (
      select
        item.value->>'source_line_key' as source_line_key,
        count(distinct item.value->>'supplier_resolution_application_id')
          as application_count
      from jsonb_array_elements(new.items) item(value)
      where item.value ? 'supplier_resolution_application_id'
      group by 1
    ) source_group
    where source_group.application_count <> 1
  ) then
    raise exception 'One source line key cannot refer to multiple resolution applications.'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from (
      select
        source.id,
        count(component.id) as expected_components,
        source.source_line_total_minor,
        coalesce(sum(component.allocated_line_total_minor), 0) as allocated_total,
        (
          select count(*)
          from jsonb_array_elements(new.items) invoice_item(value)
          where invoice_item.value->>'supplier_resolution_application_id'
            = source.id::text
        ) as observed_components
      from public.purchase_invoice_source_resolutions source
      join public.purchase_invoice_source_components component
        on component.tenant_id = source.tenant_id
       and component.source_resolution_id = source.id
      where source.tenant_id = new.tenant_id
        and exists (
          select 1
          from jsonb_array_elements(new.items) invoice_item(value)
          where invoice_item.value->>'supplier_resolution_application_id'
            = source.id::text
        )
      group by source.id, source.source_line_total_minor
    ) source_check
    where source_check.expected_components <> source_check.observed_components
       or source_check.allocated_total <> source_check.source_line_total_minor
  ) then
    raise exception 'Supplier-resolution components or source allocation are incomplete.'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.purchase_invoice_source_resolutions source
    where source.tenant_id = new.tenant_id
      and source.purchase_invoice_id = new.id
      and not exists (
        select 1
        from jsonb_array_elements(new.items) item(value)
        where item.value->>'supplier_resolution_application_id' = source.id::text
      )
  ) then
    raise exception 'A purchase invoice cannot omit a bound supplier source line.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace function public.bind_purchase_invoice_supplier_resolution()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform set_config(
    'app.supplier_resolution_write_guard',
    txid_current()::text,
    true
  );
  update public.purchase_invoice_source_resolutions source
  set purchase_invoice_id = new.id,
      bound_at = clock_timestamp()
  where source.tenant_id = new.tenant_id
    and source.purchase_invoice_id is null
    and exists (
      select 1
      from jsonb_array_elements(new.items) item(value)
      where item.value->>'supplier_resolution_application_id' = source.id::text
    );
  if exists (
    select 1
    from jsonb_array_elements(new.items) item(value)
    join public.purchase_invoice_source_resolutions source
      on source.tenant_id = new.tenant_id
     and source.id = (item.value->>'supplier_resolution_application_id')::uuid
    where item.value ? 'supplier_resolution_application_id'
      and source.purchase_invoice_id is distinct from new.id
  ) then
    perform set_config('app.supplier_resolution_write_guard', '', true);
    raise exception 'Supplier-resolution source application was bound concurrently elsewhere.'
      using errcode = '40001';
  end if;
  perform set_config('app.supplier_resolution_write_guard', '', true);
  return new;
end;
$$;

revoke all on function public.validate_purchase_invoice_supplier_resolution()
  from public, anon, authenticated, service_role;
revoke all on function public.bind_purchase_invoice_supplier_resolution()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_validate_purchase_invoice_supplier_resolution
  on public.purchase_invoices;
create trigger trg_validate_purchase_invoice_supplier_resolution
  before insert or update of
    tenant_id, supplier_id, date, supplier_invoice_date, items, status,
    subtotal, tax, iva_amount, total, net_amount, discount_value,
    discount_amount, tax_treatment, additional_costs
  on public.purchase_invoices
  for each row execute function
    public.validate_purchase_invoice_supplier_resolution();

drop trigger if exists trg_bind_purchase_invoice_supplier_resolution
  on public.purchase_invoices;
create trigger trg_bind_purchase_invoice_supplier_resolution
  after insert or update of tenant_id, items, status
  on public.purchase_invoices
  for each row execute function
    public.bind_purchase_invoice_supplier_resolution();

-- Harden the legacy read boundary without rewriting legacy rows. Only a
-- prefix that the current client already proved immutable may retain legacy
-- single-product compatibility; translated labels, image keys and `default`
-- return no authority. The versioned resolver above exposes even immutable
-- legacy rows as review-only candidates until they are confirmed into a
-- revision with an option-evidence snapshot.
create or replace function public.resolve_supplier_product_alias(
  p_supplier_id uuid,
  p_product_url text default null,
  p_item_id text default null,
  p_variant_key text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
begin
  -- A legacy one-target row cannot prove whether the supplier purchase is a
  -- physical pack or a multi-product composite. Returning it as exact would
  -- let an old client silently discard units/components. The versioned
  -- resolver above exposes immutable legacy rows as review-only candidates.
  if v_tenant_id is null or auth.uid() is null then
    raise exception 'Authenticated tenant context is required.'
      using errcode = '42501';
  end if;
  if p_supplier_id is null then
    raise exception 'Supplier is required.' using errcode = '22004';
  end if;
  perform public.assert_supplier_product_identity_access(v_tenant_id, false);
  return null;
end;
$$;

revoke all on function public.remember_supplier_variant_resolution(
  uuid, uuid, text, text, text, text, integer, text, boolean, text, text,
  jsonb, uuid, text, text, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.resolve_supplier_variant_resolution(
  uuid, text, text, text, text, integer, text, boolean
) from public, anon, authenticated, service_role;
revoke all on function public.prepare_purchase_invoice_source_resolution(
  uuid, uuid, text, integer, numeric, bigint, text, text[], text, text,
  integer, text, boolean, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.resolve_supplier_product_alias(
  uuid, text, text, text
) from public, anon, authenticated, service_role;

grant execute on function public.remember_supplier_variant_resolution(
  uuid, uuid, text, text, text, text, integer, text, boolean, text, text,
  jsonb, uuid, text, text, jsonb
) to authenticated;
grant execute on function public.resolve_supplier_variant_resolution(
  uuid, text, text, text, text, integer, text, boolean
) to authenticated;
grant execute on function public.prepare_purchase_invoice_source_resolution(
  uuid, uuid, text, integer, numeric, bigint, text, text[], text, text,
  integer, text, boolean, jsonb
) to authenticated;
grant execute on function public.resolve_supplier_product_alias(
  uuid, text, text, text
) to authenticated;

comment on table public.supplier_variant_resolution_revisions is
  'Revisioned authority for one immutable tenant+supplier+listing+variant identity. Corrections append a replacement and a negative correction edge.';
comment on table public.supplier_variant_resolution_edges is
  'Ordered product resolution edges. The same product may repeat under distinct physical roles/ordinals. Units are catalog units per one supplier purchase; allocation_ratio apportions source money, not identity.';
comment on table public.supplier_variant_resolution_corrections is
  'Append-only negative provenance from a rejected/superseded revision to its correction, reactivation, or revocation revision.';
comment on table public.purchase_invoice_source_resolutions is
  'Durable CLP source-line parent keyed independently of normalized purchase item ordinality. It binds once to a purchase invoice; other currencies require a future exponent/FX contract.';
comment on table public.purchase_invoice_source_components is
  'Immutable invoice component snapshot derived from one supplier resolution edge set, including resolved quantity and exact minor-unit allocation.';
comment on function public.remember_supplier_variant_resolution(
  uuid, uuid, text, text, text, text, integer, text, boolean, text, text,
  jsonb, uuid, text, text, jsonb
) is
  'Replay-safe atomic initial decision/correction/revocation for immutable supplier identity. Product activity, one-active revision, edge cardinality, and negative provenance fail closed.';
comment on function public.resolve_supplier_variant_resolution(
  uuid, text, text, text, text, integer, text, boolean
) is
  'Returns authoritative ordered edges only for the exact active immutable variant plus option-evidence hash. Inactive, changed, contradictory, revoked, and legacy states cannot auto-link.';
comment on function public.prepare_purchase_invoice_source_resolution(
  uuid, uuid, text, integer, numeric, bigint, text, text[], text, text,
  integer, text, boolean, jsonb
) is
  'Stages a stable invoice source-line parent and derives its complete component quantities and largest-remainder minor-unit allocation from an active revision.';
comment on function public.validate_purchase_invoice_supplier_resolution() is
  'Leaves legacy JSON untouched; rejects any provenance-bearing item set that differs from its staged source parent, revision edge set, quantity, allocation, or source total.';

notify pgrst, 'reload schema';

commit;
