-- Deployment status: NOT DEPLOYED.
--
-- Purpose:
--   Persist exact supplier-listing -> ERP-product links, resolve supplier codes
--   only inside the authenticated tenant and selected supplier, and reserve the
--   globally unique AE#### SKU namespace through one replay-safe transaction.
--
-- Forward plan:
--   Additive tables and authenticated-only RPCs. Existing products, supplier
--   codes and SKUs are not rewritten or backfilled.
--
-- Deployment precondition:
--   Every application path that assigns an AE-prefixed product SKU must use
--   reserve_aliexpress_skus. The receipt allocator serializes its own callers,
--   but cannot make a legacy client-side max()+insert sequence atomic.
--
-- Recovery:
--   Stop callers and revoke EXECUTE from the public RPCs. Preserve alias and
--   reservation rows as committed identity/idempotency evidence; do not drop
--   the tables after they have accepted production writes.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- Composite keys make the tenant graph enforceable by foreign keys. The
-- product index already exists in production, but retaining IF NOT EXISTS
-- keeps this migration safe on a fresh canonical-schema build.
create unique index if not exists uq_products_tenant_id_id
  on public.products(tenant_id, id);
create unique index if not exists uq_suppliers_tenant_id_id
  on public.suppliers(tenant_id, id);

create table if not exists public.supplier_product_aliases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  product_id uuid not null,
  listing_id text not null,
  variant_key text not null,
  normalized_title text,
  normalized_model text,
  image_url text,
  image_content_hash text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, supplier_id, listing_id, variant_key),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade,
  foreign key (tenant_id, product_id)
    references public.products(tenant_id, id) on delete cascade,
  check (listing_id = lower(btrim(listing_id))),
  check (listing_id <> '' and length(listing_id) <= 256),
  check (variant_key = lower(btrim(variant_key))),
  check (variant_key <> '' and length(variant_key) <= 512),
  check (normalized_title is null or (
    normalized_title = lower(btrim(normalized_title))
    and length(normalized_title) <= 512
  )),
  check (normalized_model is null or (
    normalized_model = lower(btrim(normalized_model))
    and length(normalized_model) <= 256
  )),
  check (image_url is null or (
    length(image_url) <= 2048
    and image_url ~* '^https?://'
  )),
  check (image_content_hash is null or
    image_content_hash ~ '^[a-f0-9]{64}$'),
  check (image_url is null or image_content_hash is null)
);

create index if not exists idx_supplier_product_aliases_product
  on public.supplier_product_aliases(
    tenant_id, product_id, updated_at desc, id desc
  );

create table if not exists public.aliexpress_sku_reservation_receipts (
  id uuid primary key default gen_random_uuid(),
  -- These UUIDs are immutable identity evidence rather than live parent links.
  -- Keeping them denormalized lets supplier/user/tenant cleanup proceed while
  -- preserving the committed allocation receipt for forensic recovery.
  tenant_id uuid not null,
  supplier_id uuid not null,
  supplier_name text not null,
  operation_key text not null,
  requested_count integer not null,
  first_sequence bigint not null,
  last_sequence bigint not null,
  skus text[] not null,
  request_snapshot jsonb not null,
  response_snapshot jsonb not null,
  actor_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_key),
  check (supplier_name = btrim(supplier_name) and supplier_name <> ''),
  check (length(operation_key) between 1 and 200),
  check (operation_key = btrim(operation_key)),
  check (requested_count between 1 and 100),
  check (first_sequence > 0),
  check (last_sequence = first_sequence + requested_count - 1),
  check (cardinality(skus) = requested_count),
  check (jsonb_typeof(request_snapshot) = 'object'),
  check (jsonb_typeof(response_snapshot) = 'object')
);

create index if not exists idx_aliexpress_sku_receipts_supplier
  on public.aliexpress_sku_reservation_receipts(
    tenant_id, supplier_id, created_at desc, id desc
  );

alter table public.supplier_product_aliases enable row level security;
alter table public.aliexpress_sku_reservation_receipts
  enable row level security;

drop policy if exists supplier_product_aliases_select
  on public.supplier_product_aliases;
create policy supplier_product_aliases_select
  on public.supplier_product_aliases
  for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = auth.uid()
        and profile.tenant_id = supplier_product_aliases.tenant_id
        and profile.is_active is true
    )
  );

drop policy if exists aliexpress_sku_reservation_receipts_select
  on public.aliexpress_sku_reservation_receipts;
create policy aliexpress_sku_reservation_receipts_select
  on public.aliexpress_sku_reservation_receipts
  for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = auth.uid()
        and profile.tenant_id = aliexpress_sku_reservation_receipts.tenant_id
        and profile.is_active is true
    )
  );

revoke all on public.supplier_product_aliases
  from public, anon, authenticated, service_role;
revoke all on public.aliexpress_sku_reservation_receipts
  from public, anon, authenticated, service_role;
grant select on public.supplier_product_aliases to authenticated;
grant select on public.aliexpress_sku_reservation_receipts to authenticated;

create or replace function public.validate_aliexpress_sku_receipt_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.suppliers supplier
    where supplier.tenant_id = new.tenant_id
      and supplier.id = new.supplier_id
  ) or not exists (
    select 1 from auth.users actor where actor.id = new.actor_id
  ) then
    raise exception 'Receipt tenant/supplier/actor identity was not valid at allocation time.'
      using errcode = '23503';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_aliexpress_sku_receipt_identity()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_aliexpress_sku_receipts_validate_identity
  on public.aliexpress_sku_reservation_receipts;
create trigger trg_aliexpress_sku_receipts_validate_identity
  before insert on public.aliexpress_sku_reservation_receipts
  for each row execute function
    public.validate_aliexpress_sku_receipt_identity();

create or replace function public.prevent_aliexpress_sku_receipt_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'AliExpress SKU reservation receipts are append-only'
    using errcode = '55000';
end;
$$;

revoke all on function public.prevent_aliexpress_sku_receipt_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_aliexpress_sku_reservation_receipts_immutable
  on public.aliexpress_sku_reservation_receipts;
create trigger trg_aliexpress_sku_reservation_receipts_immutable
  before update or delete
  on public.aliexpress_sku_reservation_receipts
  for each row execute function
    public.prevent_aliexpress_sku_receipt_mutation();

create or replace function public.normalize_supplier_identity_text(
  p_value text
)
returns text
language sql
immutable
set search_path = public
as $$
  select nullif(
    lower(regexp_replace(btrim(coalesce(p_value, '')), '\s+', ' ', 'g')),
    ''
  );
$$;

create or replace function public.normalize_supplier_listing_id(
  p_item_id text,
  p_product_url text
)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_candidate text := nullif(btrim(coalesce(p_item_id, '')), '');
  v_url text := nullif(btrim(coalesce(p_product_url, '')), '');
begin
  if v_candidate is null and v_url is not null then
    v_candidate := substring(lower(v_url) from '/item/([0-9]+)');
    v_candidate := coalesce(
      v_candidate,
      substring(lower(v_url) from '/i/([0-9]+)')
    );
    v_candidate := coalesce(
      v_candidate,
      substring(lower(v_url) from '[?&]itemid=([0-9]+)')
    );
    v_candidate := coalesce(
      v_candidate,
      substring(lower(v_url) from '[?&]productid=([0-9]+)')
    );
  end if;

  v_candidate := lower(btrim(coalesce(v_candidate, '')));
  if v_candidate = '' then
    raise exception 'AliExpress itemId or a URL containing the item ID is required.'
      using errcode = '22023';
  end if;
  if length(v_candidate) > 256
     or v_candidate !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'Supplier listing ID is invalid.' using errcode = '22023';
  end if;

  return v_candidate;
end;
$$;

revoke all on function public.normalize_supplier_identity_text(text)
  from public, anon, authenticated, service_role;
revoke all on function public.normalize_supplier_listing_id(text, text)
  from public, anon, authenticated, service_role;

create or replace function public.assert_supplier_product_identity_access(
  p_tenant_id uuid,
  p_write boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_permissions jsonb := '{}'::jsonb;
  v_active_profile_count integer;
begin
  if auth.uid() is null or p_tenant_id is null then
    raise exception 'Authenticated tenant context is required.'
      using errcode = '42501';
  end if;

  select count(*)::integer into v_active_profile_count
  from public.user_profiles profile
  where profile.user_id = auth.uid()
    and profile.is_active is true;
  if v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee profile is required.'
      using errcode = '42501';
  end if;

  select profile.role, coalesce(profile.permissions, '{}'::jsonb)
    into v_role, v_permissions
  from public.user_profiles profile
  where profile.user_id = auth.uid()
    and profile.tenant_id = p_tenant_id
    and profile.is_active is true;
  if not found then
    raise exception 'The active employee profile does not belong to this tenant.'
      using errcode = '42501';
  end if;

  if p_write
     and v_role not in ('admin', 'manager', 'accountant')
     and lower(coalesce(v_permissions->>'edit_prices', 'false')) <> 'true'
     and lower(coalesce(v_permissions->>'access_accounting', 'false')) <> 'true'
  then
    raise exception 'The active employee cannot manage supplier product identity.'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.assert_supplier_product_identity_access(
  uuid, boolean
) from public, anon, authenticated, service_role;

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
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_listing_id text;
  v_variant_key text := public.normalize_supplier_identity_text(p_variant_key);
  v_supplier_name text;
  v_alias public.supplier_product_aliases%rowtype;
begin
  if v_tenant_id is null or auth.uid() is null then
    raise exception 'Authenticated tenant context is required.'
      using errcode = '42501';
  end if;
  if p_supplier_id is null then
    raise exception 'Supplier is required.' using errcode = '22004';
  end if;
  perform public.assert_supplier_product_identity_access(v_tenant_id, false);
  if v_variant_key is null or length(v_variant_key) > 512 then
    raise exception 'A valid supplier listing variant key is required.'
      using errcode = '22023';
  end if;

  select supplier.name into v_supplier_name
  from public.suppliers supplier
  where supplier.id = p_supplier_id
    and supplier.tenant_id = v_tenant_id;
  if not found then
    raise exception 'Supplier was not found in the authenticated tenant.'
      using errcode = 'P0002';
  end if;

  v_listing_id := public.normalize_supplier_listing_id(
    p_item_id,
    p_product_url
  );

  select alias.* into v_alias
  from public.supplier_product_aliases alias
  where alias.tenant_id = v_tenant_id
    and alias.supplier_id = p_supplier_id
    and alias.listing_id = v_listing_id
    and alias.variant_key = v_variant_key;
  if not found then
    return null;
  end if;

  return to_jsonb(v_alias)
    || jsonb_build_object('supplier_name', v_supplier_name);
end;
$$;

create or replace function public.remember_supplier_product_alias(
  p_supplier_id uuid,
  p_product_id uuid,
  p_product_url text default null,
  p_item_id text default null,
  p_variant_key text default null,
  p_original_title text default null,
  p_model text default null,
  p_image_url text default null,
  p_image_content_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_supplier public.suppliers%rowtype;
  v_product public.products%rowtype;
  v_alias public.supplier_product_aliases%rowtype;
  v_listing_id text;
  v_variant_key text := public.normalize_supplier_identity_text(p_variant_key);
  v_title text := public.normalize_supplier_identity_text(p_original_title);
  v_model text := public.normalize_supplier_identity_text(p_model);
  v_image_url text := nullif(btrim(coalesce(p_image_url, '')), '');
  v_image_hash text := nullif(
    regexp_replace(
      lower(btrim(coalesce(p_image_content_hash, ''))),
      '^sha-?256:',
      ''
    ),
    ''
  );
  v_final_title text;
  v_final_model text;
  v_final_image_url text;
  v_final_image_hash text;
  v_alias_exists boolean;
  v_changed boolean;
begin
  if v_tenant_id is null or auth.uid() is null then
    raise exception 'Authenticated tenant context is required.'
      using errcode = '42501';
  end if;
  if p_supplier_id is null or p_product_id is null then
    raise exception 'Supplier and product are required.' using errcode = '22004';
  end if;
  perform public.assert_supplier_product_identity_access(v_tenant_id, true);
  if v_variant_key is null or length(v_variant_key) > 512 then
    raise exception 'A valid supplier listing variant key is required.'
      using errcode = '22023';
  end if;
  if v_title is not null and length(v_title) > 512 then
    raise exception 'Supplier title is too long.' using errcode = '22023';
  end if;
  if v_model is not null and length(v_model) > 256 then
    raise exception 'Supplier model is too long.' using errcode = '22023';
  end if;
  if v_image_url is not null and (
    length(v_image_url) > 2048 or v_image_url !~* '^https?://'
  ) then
    raise exception 'Supplier image URL is invalid.' using errcode = '22023';
  end if;
  if v_image_hash is not null and v_image_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'Supplier image hash must be a SHA-256 hex digest.'
      using errcode = '22023';
  end if;

  v_listing_id := public.normalize_supplier_listing_id(
    p_item_id,
    p_product_url
  );

  select supplier.* into v_supplier
  from public.suppliers supplier
  where supplier.id = p_supplier_id
    and supplier.tenant_id = v_tenant_id
  for share;
  if not found then
    raise exception 'Supplier was not found in the authenticated tenant.'
      using errcode = 'P0002';
  end if;

  select product.* into v_product
  from public.products product
  where product.id = p_product_id
    and product.tenant_id = v_tenant_id
  for update;
  if not found then
    raise exception 'Product was not found in the authenticated tenant.'
      using errcode = 'P0002';
  end if;

  -- Serialize one exact tenant/supplier/listing/variant key. This avoids a
  -- concurrent first-link race while permitting unrelated variants to proceed.
  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':' || p_supplier_id::text || ':' || v_listing_id
      || ':' || v_variant_key,
    0
  ));

  select alias.* into v_alias
  from public.supplier_product_aliases alias
  where alias.tenant_id = v_tenant_id
    and alias.supplier_id = p_supplier_id
    and alias.listing_id = v_listing_id
    and alias.variant_key = v_variant_key
  for update;
  v_alias_exists := found;

  if v_alias_exists
     and v_alias.product_id is distinct from v_product.id then
    raise exception 'Supplier listing is already linked to another product.'
      using errcode = '23505';
  end if;

  v_final_title := coalesce(v_title, v_alias.normalized_title);
  v_final_model := coalesce(v_model, v_alias.normalized_model);
  v_final_image_hash := coalesce(v_image_hash, v_alias.image_content_hash);
  v_final_image_url := case
    when v_final_image_hash is not null then null
    else coalesce(v_image_url, v_alias.image_url)
  end;

  v_changed := not v_alias_exists
    or v_alias.normalized_title is distinct from v_final_title
    or v_alias.normalized_model is distinct from v_final_model
    or v_alias.image_url is distinct from v_final_image_url
    or v_alias.image_content_hash is distinct from v_final_image_hash;

  -- An alias records where this listing was observed; it does not redefine the
  -- product's primary supplier. A product normally sourced from a local/MKR
  -- supplier may still be bought from AliExpress. New products must set their
  -- own supplier_id + supplier_name together in the product-creation command.

  if not v_alias_exists then
    insert into public.supplier_product_aliases (
      tenant_id,
      supplier_id,
      product_id,
      listing_id,
      variant_key,
      normalized_title,
      normalized_model,
      image_url,
      image_content_hash,
      created_by,
      updated_by
    ) values (
      v_tenant_id,
      v_supplier.id,
      v_product.id,
      v_listing_id,
      v_variant_key,
      v_final_title,
      v_final_model,
      v_final_image_url,
      v_final_image_hash,
      auth.uid(),
      auth.uid()
    ) returning * into v_alias;
  elsif v_changed then
    update public.supplier_product_aliases alias
    set normalized_title = v_final_title,
        normalized_model = v_final_model,
        image_url = v_final_image_url,
        image_content_hash = v_final_image_hash,
        updated_by = auth.uid(),
        updated_at = clock_timestamp()
    where alias.id = v_alias.id
    returning * into v_alias;
  end if;

  return to_jsonb(v_alias)
    || jsonb_build_object(
      'supplier_name', v_supplier.name,
      'replayed', not v_changed
    );
end;
$$;

create or replace function public.resolve_product_by_supplier_code(
  p_supplier_id uuid,
  p_supplier_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_code text := lower(btrim(coalesce(p_supplier_code, '')));
  v_product_ids uuid[];
begin
  if v_tenant_id is null or auth.uid() is null then
    raise exception 'Authenticated tenant context is required.'
      using errcode = '42501';
  end if;
  if p_supplier_id is null or v_code = '' then
    raise exception 'Supplier and supplier code are required.'
      using errcode = '22023';
  end if;
  perform public.assert_supplier_product_identity_access(v_tenant_id, false);
  if length(v_code) > 256 then
    raise exception 'Supplier code is too long.' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.suppliers supplier
    where supplier.id = p_supplier_id
      and supplier.tenant_id = v_tenant_id
  ) then
    raise exception 'Supplier was not found in the authenticated tenant.'
      using errcode = 'P0002';
  end if;

  select array_agg(candidate.id order by candidate.id)
    into v_product_ids
  from (
    select product.id
    from public.products product
    where product.tenant_id = v_tenant_id
      and product.supplier_id = p_supplier_id
      and lower(btrim(product.supplier_code)) = v_code
    order by product.created_at nulls last, product.id
    limit 2
  ) candidate;

  if coalesce(cardinality(v_product_ids), 0) = 0 then
    return null;
  end if;
  if cardinality(v_product_ids) > 1 then
    raise exception 'Supplier code is ambiguous for the selected supplier.'
      using errcode = '21000';
  end if;

  return jsonb_build_object(
    'product_id', v_product_ids[1],
    'supplier_id', p_supplier_id,
    'supplier_code', v_code
  );
end;
$$;

create or replace function public.reserve_aliexpress_skus(
  p_count integer,
  p_operation_key text,
  p_supplier_id uuid,
  p_supplier_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_requested_supplier_name text := btrim(coalesce(p_supplier_name, ''));
  v_supplier public.suppliers%rowtype;
  v_supplier_name text;
  v_receipt public.aliexpress_sku_reservation_receipts%rowtype;
  v_max_sequence bigint;
  v_first_sequence bigint;
  v_last_sequence bigint;
  v_skus text[];
  v_request jsonb;
  v_response jsonb;
  v_is_aliexpress boolean;
begin
  if v_tenant_id is null or auth.uid() is null then
    raise exception 'Authenticated tenant context is required.'
      using errcode = '42501';
  end if;
  if p_supplier_id is null then
    raise exception 'Supplier is required.' using errcode = '22004';
  end if;
  if p_count is null or p_count < 1 or p_count > 100 then
    raise exception 'AliExpress SKU reservation count must be between 1 and 100.'
      using errcode = '22023';
  end if;
  if v_operation_key = '' or length(v_operation_key) > 200 then
    raise exception 'A valid SKU reservation operation key is required.'
      using errcode = '22023';
  end if;
  if v_requested_supplier_name = '' then
    raise exception 'Supplier name is required.' using errcode = '22023';
  end if;

  perform public.assert_supplier_product_identity_access(v_tenant_id, true);

  -- Replay is resolved from immutable request evidence before consulting the
  -- mutable supplier row. An acknowledged allocation remains replayable after
  -- a supplier rename or deletion, and only the exact original request matches.
  select receipt.* into v_receipt
  from public.aliexpress_sku_reservation_receipts receipt
  where receipt.tenant_id = v_tenant_id
    and receipt.operation_key = v_operation_key;
  if found then
    if v_receipt.supplier_id is distinct from p_supplier_id
       or v_receipt.supplier_name is distinct from v_requested_supplier_name
       or v_receipt.requested_count is distinct from p_count then
      raise exception 'SKU reservation operation key belongs to another request.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_receipt)
      || v_receipt.response_snapshot
      || jsonb_build_object('replayed', true);
  end if;

  select supplier.* into v_supplier
  from public.suppliers supplier
  where supplier.id = p_supplier_id
    and supplier.tenant_id = v_tenant_id
  for share;
  if not found then
    raise exception 'Supplier was not found in the authenticated tenant.'
      using errcode = 'P0002';
  end if;
  v_supplier_name := btrim(v_supplier.name);
  if v_supplier_name is distinct from v_requested_supplier_name then
    raise exception 'Supplier ID and supplier name do not identify the same supplier.'
      using errcode = '23514';
  end if;

  select
    regexp_replace(lower(coalesce(v_supplier.name, '')), '[^a-z0-9]+', '', 'g')
      like '%aliexpress%'
    or exists (
      select 1
      from unnest(coalesce(v_supplier.aliases, '{}'::text[])) alias(value)
      where regexp_replace(lower(alias.value), '[^a-z0-9]+', '', 'g')
        like '%aliexpress%'
    )
  into v_is_aliexpress;
  if not coalesce(v_is_aliexpress, false) then
    raise exception 'The selected supplier is not configured as AliExpress.'
      using errcode = '23514';
  end if;

  v_request := jsonb_build_object(
    'supplier_id', v_supplier.id,
    'supplier_name', v_supplier_name,
    'requested_count', p_count
  );

  -- products.sku is globally unique in the live contract, so the AE namespace
  -- must use one global lock even though receipts and authorization are tenant
  -- scoped. Only this RPC can write receipt ranges.
  perform pg_advisory_xact_lock(
    hashtextextended('public.products.sku:AE', 0)
  );

  select receipt.* into v_receipt
  from public.aliexpress_sku_reservation_receipts receipt
  where receipt.tenant_id = v_tenant_id
    and receipt.operation_key = v_operation_key;
  if found then
    if v_receipt.supplier_id is distinct from p_supplier_id
       or v_receipt.supplier_name is distinct from v_requested_supplier_name
       or v_receipt.requested_count is distinct from p_count then
      raise exception 'SKU reservation operation key belongs to another request.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_receipt)
      || v_receipt.response_snapshot
      || jsonb_build_object('replayed', true);
  end if;

  select greatest(
    coalesce((
      select max((regexp_match(upper(product.sku), '^AE([0-9]+)$'))[1]::bigint)
      from public.products product
      where upper(product.sku) ~ '^AE[0-9]+$'
    ), 0),
    coalesce((
      select max(receipt.last_sequence)
      from public.aliexpress_sku_reservation_receipts receipt
    ), 0)
  ) into v_max_sequence;

  v_first_sequence := v_max_sequence + 1;
  v_last_sequence := v_first_sequence + p_count - 1;

  select array_agg(
    'AE' || lpad(
      series.value::text,
      greatest(4, length(series.value::text)),
      '0'
    )
    order by series.value
  ) into v_skus
  from generate_series(v_first_sequence, v_last_sequence) series(value);

  v_response := jsonb_build_object(
    'supplier_id', v_supplier.id,
    'supplier_name', v_supplier_name,
    'operation_key', v_operation_key,
    'requested_count', p_count,
    'first_sequence', v_first_sequence,
    'last_sequence', v_last_sequence,
    'skus', v_skus
  );

  insert into public.aliexpress_sku_reservation_receipts (
    tenant_id,
    supplier_id,
    supplier_name,
    operation_key,
    requested_count,
    first_sequence,
    last_sequence,
    skus,
    request_snapshot,
    response_snapshot,
    actor_id
  ) values (
    v_tenant_id,
    v_supplier.id,
    v_supplier_name,
    v_operation_key,
    p_count,
    v_first_sequence,
    v_last_sequence,
    v_skus,
    v_request,
    v_response,
    auth.uid()
  ) returning * into v_receipt;

  return to_jsonb(v_receipt)
    || v_response
    || jsonb_build_object('replayed', false);
end;
$$;

revoke all on function public.resolve_supplier_product_alias(
  uuid, text, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.remember_supplier_product_alias(
  uuid, uuid, text, text, text, text, text, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.resolve_product_by_supplier_code(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.reserve_aliexpress_skus(
  integer, text, uuid, text
) from public, anon, authenticated, service_role;

grant execute on function public.resolve_supplier_product_alias(
  uuid, text, text, text
) to authenticated;
grant execute on function public.remember_supplier_product_alias(
  uuid, uuid, text, text, text, text, text, text, text
) to authenticated;
grant execute on function public.resolve_product_by_supplier_code(uuid, text)
  to authenticated;
grant execute on function public.reserve_aliexpress_skus(
  integer, text, uuid, text
) to authenticated;

comment on table public.supplier_product_aliases is
  'Exact tenant+supplier+listing+variant aliases linked to an ERP product. Stores only canonical identity and minimal review evidence.';
comment on table public.aliexpress_sku_reservation_receipts is
  'Append-only replay receipts for globally serialized AE SKU range allocation.';
comment on function public.remember_supplier_product_alias(
  uuid, uuid, text, text, text, text, text, text, text
) is
  'Persists one explicit tenant+supplier+listing+variant alias without changing the linked product primary supplier_id/supplier_name pair; a blank variant fails closed.';
comment on function public.resolve_product_by_supplier_code(uuid, text) is
  'Exact supplier-code lookup bounded by authenticated tenant and explicit supplier; ambiguous matches fail closed.';
comment on function public.reserve_aliexpress_skus(integer, text, uuid, text) is
  'Serializes AE#### allocation receipts against products and earlier receipts, and replays the exact committed request by tenant operation key. Every AE SKU writer must use this allocator.';

notify pgrst, 'reload schema';

commit;
