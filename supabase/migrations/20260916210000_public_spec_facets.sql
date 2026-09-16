-- Storefront filters by technical spec: the customer narrows tubes by wheel
-- size and valve, tyres by wheel size and width, cassettes by speeds. The
-- filterable flags published on 2026-09-16 get their first consumer.
-- v2 of the faceted product page and the facet snapshot add `p_spec_filters`
-- (`{"valve_standard": ["Francesa (Presta)"]}`; every key must match, any
-- listed value matches) and the snapshot returns one row per spec value as
-- `spec:<key>:<data_type>:<unit>`. v1 stays for clients built before it.
-- Rerunnable: create or replace only.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';

-- Every technical-spec value a visitor may filter by: filterable and
-- customer-visible definitions of the product's resolved template, never a
-- retired (`legacy`) field, never an unconfirmed inference. Numbers are
-- rendered without trailing zeros, booleans as «Sí»/«No», options by label.
create or replace function public.spec_public_facet_values_internal_v1(p_tenant_id uuid)
returns table(product_id uuid, spec_key text, spec_label text, data_type text, unit text, value_text text)
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select f.subject_id, d.key,
    coalesce(t.form_contract->'labels'->>d.key, d.label),
    d.data_type, d.unit,
    case d.data_type
      when 'number' then trim_scale(f.value_number)::text
      when 'boolean' then case when f.value_boolean then 'Sí' else 'No' end
      else v.label end
  from public.spec_facts f
  join public.product_spec_bindings_internal_v1 b on b.product_id = f.subject_id and b.tenant_id = f.tenant_id
  join public.spec_templates t on t.id = b.template_id and t.is_active and (t.tenant_id is null or t.tenant_id = p_tenant_id)
  join public.spec_template_fields tf on tf.template_id = t.id and tf.spec_definition_id = f.spec_definition_id
  join public.spec_definitions d on d.id = f.spec_definition_id
    and d.is_filterable and d.is_customer_visible
    and d.data_type in ('single_select','number','boolean')
  left join public.spec_fact_values fv on fv.fact_id = f.id
  left join public.spec_definition_values v on v.id = fv.value_id and v.is_active
  where f.tenant_id = p_tenant_id and f.subject_type = 'product' and f.subject_scope is null
    and coalesce(t.form_contract->'roles'->>d.key, 'primary') <> 'legacy'
    and not (f.source = 'inferred' and not coalesce(f.confirmed, false))
    and (d.data_type <> 'single_select' or v.label is not null)
    and (d.data_type <> 'number' or f.value_number is not null)
    and (d.data_type <> 'boolean' or f.value_boolean is not null)
$$;
revoke all on function public.spec_public_facet_values_internal_v1(uuid) from public, anon, authenticated, service_role;

-- Products that satisfy every key of `p_filters` (`{"key": ["v1","v2"]}`),
-- except `p_exclude_key`, which lets a facet count its own alternatives.
-- With no key left to apply, every product of the tenant qualifies.
create or replace function public.spec_public_facet_matches_internal_v1(p_tenant_id uuid, p_filters jsonb, p_exclude_key text default null)
returns table(product_id uuid)
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  with keys as (
    select e.key, e.value as wanted
    from jsonb_each(coalesce(p_filters, '{}'::jsonb)) e
    where e.key is distinct from p_exclude_key
      and jsonb_typeof(e.value) = 'array' and jsonb_array_length(e.value) > 0
  ), matched as (
    select v.product_id
    from public.spec_public_facet_values_internal_v1(p_tenant_id) v
    join keys k on k.key = v.spec_key and k.wanted ? v.value_text
    group by v.product_id
    having count(distinct v.spec_key) = (select count(*) from keys)
  )
  select p.id from public.products p
  where p.tenant_id = p_tenant_id
    and (not exists (select 1 from keys) or p.id in (select product_id from matched))
$$;
revoke all on function public.spec_public_facet_matches_internal_v1(uuid, jsonb, text) from public, anon, authenticated, service_role;

create or replace function public.get_public_products_faceted_v2(p_tenant_id uuid, p_category_ids uuid[] DEFAULT NULL::uuid[], p_search_term text DEFAULT NULL::text, p_product_type text DEFAULT NULL::text, p_only_in_stock boolean DEFAULT true, p_brand_ids uuid[] DEFAULT NULL::uuid[], p_min_price numeric DEFAULT NULL::numeric, p_max_price numeric DEFAULT NULL::numeric, p_spec_filters jsonb DEFAULT NULL::jsonb, p_sort_by text DEFAULT 'name'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, tenant_id uuid, name text, sku text, barcode text, price numeric, cost numeric, inventory_qty integer, stock_quantity integer, image_url text, image_url_optimized text, image_urls text[], description text, website_description text, category text, category_id uuid, category_name text, brand_id uuid, brand text, model text, manufacturer text, manufacturer_sku text, gtin text, product_type text, track_stock boolean, is_active boolean, is_published boolean, show_on_website boolean, created_at timestamp with time zone, updated_at timestamp with time zone, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  ), spec_scope as (
    -- Technical-spec filters narrow the universe to the products that carry
    -- every requested value. Null means «no spec filter».
    select case
      when p_spec_filters is null or jsonb_typeof(p_spec_filters) <> 'object'
        or not exists (select 1 from jsonb_each(p_spec_filters) e where jsonb_typeof(e.value) = 'array' and jsonb_array_length(e.value) > 0)
      then null::uuid[]
      else coalesce((select array_agg(m.product_id) from public.spec_public_facet_matches_internal_v1(p_tenant_id, p_spec_filters) m), '{}'::uuid[])
    end as ids
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
    cross join spec_scope
    where args.is_valid
      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
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
$function$;
revoke all on function public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer) from public, service_role;
grant execute on function public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer) to anon, authenticated;

create or replace function public.get_public_product_facets_v2(p_tenant_id uuid, p_category_ids uuid[] DEFAULT NULL::uuid[], p_search_term text DEFAULT NULL::text, p_product_type text DEFAULT NULL::text, p_only_in_stock boolean DEFAULT true, p_brand_ids uuid[] DEFAULT NULL::uuid[], p_min_price numeric DEFAULT NULL::numeric, p_max_price numeric DEFAULT NULL::numeric, p_spec_filters jsonb DEFAULT NULL::jsonb)
 RETURNS TABLE(facet_key text, value_id text, value_label text, item_count bigint, range_min numeric, range_max numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  ), spec_filters as materialized (
    select e.key
    from jsonb_each(coalesce(p_spec_filters, '{}'::jsonb)) e
    where jsonb_typeof(e.value) = 'array' and jsonb_array_length(e.value) > 0
  ), spec_scope as materialized (
    -- Products satisfying every spec filter; null when there is none.
    select case when exists (select 1 from spec_filters)
      then coalesce((select array_agg(m.product_id) from public.spec_public_facet_matches_internal_v1(p_tenant_id, p_spec_filters) m), '{}'::uuid[])
      else null::uuid[] end as ids
  ), spec_values as materialized (
    select * from public.spec_public_facet_values_internal_v1(p_tenant_id)
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
    cross join spec_scope
    where args.is_valid
      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
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
    cross join spec_scope
    left join public.product_brands canonical_brand
      on canonical_brand.id = base.brand_id
     and (
       canonical_brand.tenant_id is null
       or canonical_brand.tenant_id = p_tenant_id
     )
    where args.is_valid
      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
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
    cross join spec_scope
    where args.is_valid
      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
      and (
        p_brand_ids is null
        or cardinality(p_brand_ids) = 0
        or base.brand_id = any(p_brand_ids)
      )
  ), spec_matches_by_key as materialized (
    -- For a key the visitor already filters on, its alternatives are counted
    -- against the other keys only (as brands do with the brand selection).
    select k.key as excluded_key, m.product_id
    from spec_filters k
    cross join lateral public.spec_public_facet_matches_internal_v1(p_tenant_id, p_spec_filters, k.key) m
  ), spec_scope_rows as materialized (
    -- The products the visitor is looking at once every non-spec facet and
    -- the spec filters apply: the denominator that says whether a spec facet
    -- describes this collection or only a corner of it.
    select base.id
    from selected_category_rows base
    cross join args
    cross join spec_scope
    where args.is_valid
      and (
        p_brand_ids is null
        or cardinality(p_brand_ids) = 0
        or base.brand_id = any(p_brand_ids)
      )
      and (args.min_price is null or base.price >= args.min_price)
      and (args.max_price is null or base.price <= args.max_price)
      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
  ), spec_coverage as materialized (
    select v.spec_key, count(distinct s.id)::numeric as covered
    from spec_scope_rows s
    join spec_values v on v.product_id = s.id
    group by v.spec_key
  ), spec_rows as (
    -- One row per value. range_min carries how many products of the scope
    -- have this key at all, range_max how many products the scope holds, so
    -- the client can hide a facet that describes a small corner only.
    select
      ('spec:' || v.spec_key || ':' || v.data_type || ':' || coalesce(v.unit, ''))::text as facet_key,
      v.value_text as value_id,
      v.spec_label as value_label,
      count(distinct base.id)::bigint as item_count,
      (select c.covered from spec_coverage c where c.spec_key = v.spec_key) as range_min,
      (select count(*)::numeric from spec_scope_rows) as range_max
    from selected_category_rows base
    cross join args
    cross join spec_scope
    join spec_values v on v.product_id = base.id
    where args.is_valid
      and (
        p_brand_ids is null
        or cardinality(p_brand_ids) = 0
        or base.brand_id = any(p_brand_ids)
      )
      and (args.min_price is null or base.price >= args.min_price)
      and (args.max_price is null or base.price <= args.max_price)
      and (
        case when exists (select 1 from spec_filters k where k.key = v.spec_key)
          then exists (select 1 from spec_matches_by_key m where m.excluded_key = v.spec_key and m.product_id = base.id)
          else spec_scope.ids is null or base.id = any(spec_scope.ids)
        end
      )
    group by v.spec_key, v.data_type, v.unit, v.value_text, v.spec_label
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
  union all
  select * from spec_rows
  order by facet_key, value_label nulls first, value_id nulls first;
$function$;
revoke all on function public.get_public_product_facets_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb) from public, service_role;
grant execute on function public.get_public_product_facets_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb) to anon, authenticated;

-- The one filterable label still written for the engine: «Largo nominal de
-- esta variante de rayo» is the spoke length a mechanic asks for as «largo
-- del rayo». Definition and template contract, so both readers agree.
update public.spec_definitions
set label = 'Largo del rayo'
where tenant_id is null and key = 'spoke_length_mm'
  and label = 'Largo nominal de esta variante de rayo';
update public.spec_templates
set form_contract = jsonb_set(form_contract, '{labels,spoke_length_mm}', to_jsonb('Largo del rayo'::text))
where form_contract->'labels'->>'spoke_length_mm' = 'Largo nominal de esta variante de rayo';
commit;
