-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-22
-- Apply only after production-derived schema validation and
-- explicit production authorization under docs/runbooks/STAGING_SUPABASE.md.
-- Requires the reservation-aware canonical public RPC installed by
-- 20260718290000_add_online_inventory_reservations.sql; the focused pgTAP
-- contract refuses a baseline where that prerequisite is absent.
--
-- Additive public-catalog facade for server-backed visitor facets. The
-- installed get_public_products() RPC remains the sole publication,
-- visibility, search-ranking and reservation-aware availability owner. These
-- functions only filter that canonical result and page it afterwards, so a
-- browser never filters only the rows already loaded on screen.

begin;

-- Production already treats the brand catalog as a global canonical registry.
-- Keep the bootstrap snapshot and any stale disposable/local database aligned
-- before facet labels resolve a global brand through tenant_id IS NULL.
alter table public.product_brands
  alter column tenant_id drop not null;
alter table public.product_brands
  drop constraint if exists product_brands_tenant_id_name_key;
do $$
declare
  v_name_attnum smallint;
  v_constraint_type "char";
  v_constraint_key smallint[];
  v_named_constraint_exists boolean;
begin
  select attribute.attnum
  into v_name_attnum
  from pg_attribute attribute
  where attribute.attrelid = 'public.product_brands'::regclass
    and attribute.attname = 'name'
    and not attribute.attisdropped;

  if v_name_attnum is null then
    raise exception 'product_brands.name is required by the canonical brand contract'
      using errcode = 'check_violation';
  end if;

  select constraint_record.contype, constraint_record.conkey
  into v_constraint_type, v_constraint_key
  from pg_constraint constraint_record
  where constraint_record.conrelid = 'public.product_brands'::regclass
    and constraint_record.conname = 'product_brands_name_key';
  v_named_constraint_exists := found;

  if v_named_constraint_exists
     and (
       v_constraint_type is distinct from 'u'
       or v_constraint_key is distinct from array[v_name_attnum]::smallint[]
     ) then
    raise exception
      'product_brands_name_key has an unexpected shape: type %, key %',
      v_constraint_type,
      v_constraint_key
      using errcode = 'check_violation';
  end if;

  if exists (
    select 1
    from public.product_brands brand
    group by brand.name
    having count(*) > 1
  ) then
    raise exception
      'Cannot install canonical brand uniqueness: duplicate product_brands.name rows exist'
      using errcode = 'unique_violation';
  end if;

  if not v_named_constraint_exists then
    alter table public.product_brands
      add constraint product_brands_name_key unique (name);
  end if;
end;
$$;

create or replace function public.get_public_products_faceted_v1(
  p_tenant_id uuid,
  p_category_ids uuid[] default null,
  p_search_term text default null,
  p_product_type text default null,
  p_only_in_stock boolean default true,
  p_brand_ids uuid[] default null,
  p_min_price numeric default null,
  p_max_price numeric default null,
  p_sort_by text default 'name',
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid,
  tenant_id uuid,
  name text,
  sku text,
  barcode text,
  price numeric,
  cost numeric,
  inventory_qty integer,
  stock_quantity integer,
  image_url text,
  image_url_optimized text,
  image_urls text[],
  description text,
  website_description text,
  category text,
  category_id uuid,
  category_name text,
  brand_id uuid,
  brand text,
  model text,
  manufacturer text,
  manufacturer_sku text,
  gtin text,
  product_type text,
  track_stock boolean,
  is_active boolean,
  is_published boolean,
  show_on_website boolean,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with args as (
    select
      case
        when p_min_price is null then null
        when p_min_price >= 0 then p_min_price
        else null
      end as min_price,
      case
        when p_max_price is null then null
        when p_max_price >= 0 then p_max_price
        else null
      end as max_price,
      (
        (p_min_price is null or p_min_price >= 0)
        and (p_max_price is null or p_max_price >= 0)
        and (
          p_min_price is null
          or p_max_price is null
          or p_min_price <= p_max_price
        )
      ) as is_valid
  ), base_rows as (
    select product.*
    from public.get_public_products(
      p_tenant_id := p_tenant_id,
      p_category_ids := p_category_ids,
      p_search_term := p_search_term,
      p_product_type := p_product_type,
      -- The canonical RPC applies the site's publication stock policy first.
      -- Request its rule-allowed universe here, then apply the visitor's
      -- optional availability facet to the reservation-aware quantities it
      -- returns. A visitor can narrow a rule, never widen it.
      p_only_in_stock := true,
      p_sort_by := p_sort_by,
      p_limit := 2147483647,
      p_offset := 0
    ) with ordinality as product
  ), available_rows as (
    select base.*
    from base_rows base
    where not coalesce(p_only_in_stock, true)
      or base.product_type = 'service'
      or not coalesce(base.track_stock, true)
      or coalesce(base.stock_quantity, base.inventory_qty, 0) > 0
  ), filtered as (
    select base.*
    from available_rows base
    cross join args
    where args.is_valid
      and (
        p_brand_ids is null
        or cardinality(p_brand_ids) = 0
        or base.brand_id = any(p_brand_ids)
      )
      and (args.min_price is null or base.price >= args.min_price)
      and (args.max_price is null or base.price <= args.max_price)
  ), page_contract as (
    select
      least(greatest(coalesce(p_limit, 20), 1), 100)::bigint as page_limit,
      greatest(coalesce(p_offset, 0), 0)::bigint as requested_offset,
      count(*)::bigint as total_count
    from filtered
  ), page_window as (
    -- The row contract carries total_count, so a non-empty result can never
    -- disappear solely because limit is zero or the requested offset is stale.
    -- Clamp to at least one row and to the start of the final valid page.
    select
      contract.page_limit,
      contract.total_count,
      case
        when contract.total_count = 0 then 0::bigint
        else least(
          contract.requested_offset,
          (
            (contract.total_count - 1) / contract.page_limit
          ) * contract.page_limit
        )
      end as page_offset
    from page_contract contract
  ), paged as (
    select filtered.*, page.total_count as filtered_total
    from filtered
    cross join page_window page
    order by filtered.ordinality
    limit (select page_limit from page_window)
    offset (select page_offset from page_window)
  )
  select
    paged.id,
    paged.tenant_id,
    paged.name,
    paged.sku,
    paged.barcode,
    paged.price,
    paged.cost,
    paged.inventory_qty,
    paged.stock_quantity,
    paged.image_url,
    paged.image_url_optimized,
    paged.image_urls,
    paged.description,
    paged.website_description,
    paged.category,
    paged.category_id,
    paged.category_name,
    paged.brand_id,
    paged.brand,
    paged.model,
    paged.manufacturer,
    paged.manufacturer_sku,
    paged.gtin,
    paged.product_type,
    paged.track_stock,
    paged.is_active,
    paged.is_published,
    paged.show_on_website,
    paged.created_at,
    paged.updated_at,
    paged.filtered_total
  from paged
  order by paged.ordinality;
$$;

comment on function public.get_public_products_faceted_v1(
  uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, text, integer,
  integer
) is
  'Server-paged public catalog facade. Applies stable brand IDs and effective storefront price filters after canonical public eligibility and reservation-aware availability. Clamps page size to 1..100 and stale offsets to the final valid page so every non-empty response carries total_count.';

revoke all on function public.get_public_products_faceted_v1(
  uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, text, integer,
  integer
) from public, anon, authenticated, service_role;
grant execute on function public.get_public_products_faceted_v1(
  uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, text, integer,
  integer
) to anon, authenticated;

create or replace function public.get_public_product_facets_v1(
  p_tenant_id uuid,
  p_category_ids uuid[] default null,
  p_search_term text default null,
  p_product_type text default null,
  p_only_in_stock boolean default true,
  p_brand_ids uuid[] default null,
  p_min_price numeric default null,
  p_max_price numeric default null
)
returns table (
  facet_key text,
  value_id text,
  value_label text,
  item_count bigint,
  range_min numeric,
  range_max numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with args as (
    select
      case
        when p_min_price is null then null
        when p_min_price >= 0 then p_min_price
        else null
      end as min_price,
      case
        when p_max_price is null then null
        when p_max_price >= 0 then p_max_price
        else null
      end as max_price,
      (
        (p_min_price is null or p_min_price >= 0)
        and (p_max_price is null or p_max_price >= 0)
        and (
          p_min_price is null
          or p_max_price is null
          or p_min_price <= p_max_price
        )
      ) as is_valid
  ), canonical_universe as materialized (
    -- Load the canonical search/type/publication/site-stock universe exactly
    -- once. Every facet projection below is derived from this same
    -- reservation-aware snapshot, preventing duplicate full catalog scans.
    select product.*
    from public.get_public_products(
      p_tenant_id := p_tenant_id,
      p_category_ids := null,
      p_search_term := p_search_term,
      p_product_type := p_product_type,
      p_only_in_stock := true,
      p_sort_by := 'name',
      p_limit := 2147483647,
      p_offset := 0
    ) product
  ), available_universe as materialized (
    select base.*
    from canonical_universe base
    where not coalesce(p_only_in_stock, true)
      or base.product_type = 'service'
      or not coalesce(base.track_stock, true)
      or coalesce(base.stock_quantity, base.inventory_qty, 0) > 0
  ), selected_category_rows as materialized (
    -- Brand and price metadata respect the active category selection. This is
    -- the exact direct-ID predicate owned by the canonical product RPC, now
    -- applied after its single unselected-universe call.
    select base.*
    from available_universe base
    where p_category_ids is null
      or cardinality(p_category_ids) = 0
      or base.category_id = any(p_category_ids)
  ), category_filtered_rows as materialized (
    -- Category options and the summary deliberately exclude the current
    -- category selection while respecting every other active facet.
    select base.*
    from available_universe base
    cross join args
    where args.is_valid
      and (
        p_brand_ids is null
        or cardinality(p_brand_ids) = 0
        or base.brand_id = any(p_brand_ids)
      )
      and (args.min_price is null or base.price >= args.min_price)
      and (args.max_price is null or base.price <= args.max_price)
  ), category_rows as (
    -- Keep direct counts for every active canonical category. The category
    -- publication owner decides which IDs become visible filter options, so a
    -- hidden descendant can still roll up into its visible published ancestor.
    select
      'category'::text as facet_key,
      base.category_id::text as value_id,
      nullif(btrim(canonical_category.name), '') as value_label,
      count(*)::bigint as item_count,
      null::numeric as range_min,
      null::numeric as range_max
    from category_filtered_rows base
    join public.product_categories canonical_category
      on canonical_category.id = base.category_id
     and canonical_category.tenant_id = p_tenant_id
     and canonical_category.is_active = true
    group by base.category_id, canonical_category.name
  ), summary_rows as (
    -- This is the exact total for the category-option universe. It includes
    -- uncategorized products, so consumers must not derive "Todas" by summing
    -- only the category rows.
    select
      'summary'::text as facet_key,
      null::text as value_id,
      null::text as value_label,
      count(*)::bigint as item_count,
      null::numeric as range_min,
      null::numeric as range_max
    from category_filtered_rows
  ), brand_rows as (
    -- Brand counts exclude the current brand selection, but respect every
    -- other active facet so alternatives remain useful and truthful.
    select
      'brand'::text as facet_key,
      base.brand_id::text as value_id,
      coalesce(nullif(btrim(canonical_brand.name), ''), nullif(btrim(base.brand), ''))
        as value_label,
      count(*)::bigint as item_count,
      null::numeric as range_min,
      null::numeric as range_max
    from selected_category_rows base
    cross join args
    left join public.product_brands canonical_brand
      on canonical_brand.id = base.brand_id
     and (
       canonical_brand.tenant_id is null
       or canonical_brand.tenant_id = p_tenant_id
     )
    where args.is_valid
      and base.brand_id is not null
      and (args.min_price is null or base.price >= args.min_price)
      and (args.max_price is null or base.price <= args.max_price)
    group by
      base.brand_id,
      coalesce(nullif(btrim(canonical_brand.name), ''), nullif(btrim(base.brand), ''))
  ), price_rows as (
    -- Price bounds exclude the current price range, but respect the selected
    -- brands and every route/publication/availability filter.
    select
      'price'::text as facet_key,
      null::text as value_id,
      null::text as value_label,
      count(*)::bigint as item_count,
      min(base.price)::numeric as range_min,
      max(base.price)::numeric as range_max
    from selected_category_rows base
    cross join args
    where args.is_valid
      and (
        p_brand_ids is null
        or cardinality(p_brand_ids) = 0
        or base.brand_id = any(p_brand_ids)
      )
  )
  select * from category_rows
  where value_label is not null
  union all
  select * from brand_rows
  where value_label is not null
  union all
  select * from price_rows
  union all
  select * from summary_rows
  order by facet_key, value_label nulls first, value_id nulls first;
$$;

comment on function public.get_public_product_facets_v1(
  uuid, uuid[], text, text, boolean, uuid[], numeric, numeric
) is
  'Public category, brand, price and total-summary facet metadata derived from the complete canonical eligible catalog. Counts exclude their own facet and respect all other filters.';

revoke all on function public.get_public_product_facets_v1(
  uuid, uuid[], text, text, boolean, uuid[], numeric, numeric
) from public, anon, authenticated, service_role;
grant execute on function public.get_public_product_facets_v1(
  uuid, uuid[], text, text, boolean, uuid[], numeric, numeric
) to anon, authenticated;

notify pgrst, 'reload schema';

commit;
