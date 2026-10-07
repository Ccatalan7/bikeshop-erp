-- The public catalog reads do only the work their answer needs. Same
-- answers, row by row and in order (compared against the previous bodies in
-- production, read-only, before deploying: 13 listing calls, 7 facet calls
-- and the technical values of the store).
--
-- Why (measured in production, 2026-10-07): a catalog page read the filters
-- (get_public_product_facets_v2, ~420 ms) and the listing (~150 ms). The
-- database is a small instance; a burst of a dozen visits pushed the filter
-- read past `anon`'s 3 s statement timeout and the storefront answered «La
-- tienda no pudo leer esta página» to whole pages (22 times to PerplexityBot
-- on 2026-10-06; 8 of 12 in a test burst). The work was waste:
--
-- 1. spec_public_facet_values_internal_v1 (~230 ms) resolved each product's
--    template with one function call per product (product_spec_bindings_
--    internal_v1 → spec_template_resolution_internal_v1, ~62 ms) and read
--    the template's form_contract once per fact (~7.500 detoasts). It is now
--    spec_public_facet_values_compute_internal_v1: the same rules as one
--    join, the contract's roles and labels read once per template, and an
--    optional product list (~50 ms for the whole store).
-- 2. get_public_product_facets_v2 computed those values for every product of
--    the store even on a category page of 67; it now computes them for the
--    products its facets describe (selected_category_rows), the only ones it
--    joins them with.
-- 3. get_public_products_without_inventory_reservations normalized ten texts
--    of every product (unaccent + regexp, ~110 ms) and scored them although
--    no visitor was searching. Without a search term every product passes,
--    every score is zero and the order reads the raw name, price and date;
--    it now normalizes and scores only when there is a term (~23 ms).
--
-- A first attempt kept both results in trigger-maintained tables; two Codex
-- reviews found nine concurrency defects in it (stale overwrites, deadlocks,
-- a missed invalidation), and the cache was not needed once the reads stopped
-- doing unnecessary work. Nothing is stored: every visit still reads the
-- live catalog, as docs/architecture/storefront-html-migration-plan.md asks.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

create or replace function public.spec_public_facet_values_compute_internal_v1(
  p_tenant_id uuid,
  p_product_ids uuid[] default null
)
returns table(product_id uuid, spec_key text, spec_label text, data_type text, unit text, value_text text)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  with templates as materialized (
    -- The active templates the store can use, with the two parts of their
    -- contract the values read (once per template, not once per fact).
    select t.id, t.form_contract -> 'roles' as roles,
           t.form_contract -> 'labels' as labels
      from public.spec_templates t
     where t.is_active
       and (t.tenant_id is null or t.tenant_id = p_tenant_id)
  ), bindings as materialized (
    -- product_spec_bindings_internal_v1 with spec_template_resolution_internal_v1,
    -- as one join instead of one function call per product: the product's
    -- own template, else its category's active mapping.
    select p.id as product_id, t.id as template_id, t.roles, t.labels
      from public.products p
      left join public.category_tech_mappings m
        on p.spec_template_id is null
       and m.tenant_id = p.tenant_id
       and m.category_id = p.category_id
       and m.status = 'active'
      join templates t
        on t.id = coalesce(p.spec_template_id, m.template_id)
     where p.tenant_id = p_tenant_id
       and (p_product_ids is null or p.id = any(p_product_ids))
  ), visible_definitions as materialized (
    select d.id, d.key, d.label, d.store_label, d.data_type, d.unit,
           d.is_filterable, d.validation_rules
      from public.spec_definitions d
     where d.is_customer_visible
  ), bound as (
    -- Facts of the product's resolved active template, field not retired,
    -- customer-visible, whatever their origin.
    select f.id as fact_id, f.subject_id, f.value_number, f.value_boolean, f.value_json,
      d.key, d.label, d.store_label, d.data_type, d.unit, d.is_filterable, d.validation_rules,
      b.labels
    from public.spec_facts f
    join bindings b on b.product_id = f.subject_id
    join public.spec_template_fields tf on tf.template_id = b.template_id and tf.spec_definition_id = f.spec_definition_id
    join visible_definitions d on d.id = f.spec_definition_id
    where f.tenant_id = p_tenant_id and f.subject_type = 'product' and f.subject_scope is null
      and (p_product_ids is null or f.subject_id = any(p_product_ids))
      and coalesce(b.roles->>d.key, 'primary') <> 'legacy'
  ), scalar as (
    -- Options by label, numbers without trailing zeros, booleans as «Sí»/«No».
    select b.subject_id, b.key,
      coalesce(nullif(btrim(b.store_label), ''), b.labels->>b.key, b.label) as spec_label,
      b.data_type, b.unit,
      case b.data_type
        when 'number' then trim_scale(b.value_number)::text
        when 'boolean' then case when b.value_boolean then 'Sí' else 'No' end
        else v.label end as value_text
    from bound b
    left join public.spec_fact_values fv on fv.fact_id = b.fact_id
    left join public.spec_definition_values v on v.id = fv.value_id and v.is_active
    where b.is_filterable and b.data_type in ('single_select','number','boolean')
      and (b.data_type <> 'single_select' or v.label is not null)
      and (b.data_type <> 'number' or b.value_number is not null)
      and (b.data_type <> 'boolean' or b.value_boolean is not null)
  ), projected as (
    -- A numeric cell of a rows field named after a global filterable number
    -- field is that field for the visitor (a tube's ISO diameter is «Aro»).
    select b.subject_id, target.key,
      coalesce(nullif(btrim(target.store_label), ''), b.labels->>target.key, target.label) as spec_label,
      target.data_type, target.unit,
      case when (fit.r->'values'->>(cols.col->>'key')) ~ '^[0-9]+(\.[0-9]+)?$'
        then trim_scale((fit.r->'values'->>(cols.col->>'key'))::numeric)::text end as value_text
    from bound b
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(b.validation_rules->'rows_schema'->'columns') = 'array'
        then b.validation_rules->'rows_schema'->'columns' else '[]'::jsonb end
    ) as cols(col)
    join public.spec_definitions target
      on target.tenant_id is null and target.key = cols.col->>'key'
     and target.data_type = 'number' and target.is_filterable and target.is_customer_visible
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(b.value_json->'rows') = 'array' then b.value_json->'rows' else '[]'::jsonb end
    ) as fit(r)
    where b.data_type = 'json' and cols.col->>'type' in ('integer','decimal','number')
  )
  select subject_id, key, spec_label, data_type, unit, value_text from scalar
  union
  select subject_id, key, spec_label, data_type, unit, value_text from projected where value_text is not null
$function$;

revoke all on function public.spec_public_facet_values_compute_internal_v1(uuid, uuid[])
  from public, anon, authenticated, service_role;

-- The same answer as before for the whole store (the technical filters of a
-- spec filter, spec_public_facet_matches_internal_v1, still read it).
create or replace function public.spec_public_facet_values_internal_v1(p_tenant_id uuid)
returns table(product_id uuid, spec_key text, spec_label text, data_type text, unit text, value_text text)
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select c.product_id, c.spec_key, c.spec_label, c.data_type, c.unit, c.value_text
    from public.spec_public_facet_values_compute_internal_v1(p_tenant_id, null) c
$function$;

revoke all on function public.spec_public_facet_values_internal_v1(uuid)
  from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_public_product_facets_v2(p_tenant_id uuid, p_category_ids uuid[] DEFAULT NULL::uuid[], p_search_term text DEFAULT NULL::text, p_product_type text DEFAULT NULL::text, p_only_in_stock boolean DEFAULT true, p_brand_ids uuid[] DEFAULT NULL::uuid[], p_min_price numeric DEFAULT NULL::numeric, p_max_price numeric DEFAULT NULL::numeric, p_spec_filters jsonb DEFAULT NULL::jsonb)
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
  ), spec_values as materialized (
    -- The technical values of the products these facets describe, not of
    -- the whole store: a category page computes its own few.
    select *
    from public.spec_public_facet_values_compute_internal_v1(
      p_tenant_id,
      (select coalesce(array_agg(s.id), '{}'::uuid[]) from selected_category_rows s)
    )
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

CREATE OR REPLACE FUNCTION public.get_public_products_without_inventory_reservations(p_tenant_id uuid, p_category_ids uuid[] DEFAULT NULL::uuid[], p_product_ids uuid[] DEFAULT NULL::uuid[], p_sku text DEFAULT NULL::text, p_search_term text DEFAULT NULL::text, p_product_type text DEFAULT NULL::text, p_only_in_stock boolean DEFAULT true, p_sort_by text DEFAULT 'name'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, tenant_id uuid, name text, sku text, barcode text, price numeric, cost numeric, inventory_qty integer, stock_quantity integer, image_url text, image_url_optimized text, image_urls text[], description text, website_description text, category text, category_id uuid, category_name text, brand_id uuid, brand text, model text, manufacturer text, manufacturer_sku text, gtin text, product_type text, track_stock boolean, is_active boolean, is_published boolean, show_on_website boolean, created_at timestamp with time zone, updated_at timestamp with time zone, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with args as (
    select
      s.term,
      coalesce(t.tokens, array[]::text[]) as tokens,
      greatest(coalesce(p_limit, 20), 0) as page_limit,
      greatest(coalesce(p_offset, 0), 0) as page_offset,
      lower(coalesce(nullif(trim(p_sort_by), ''), 'name')) as sort_by,
      nullif(trim(coalesce(p_sku, '')), '') as wanted_sku,
      nullif(trim(coalesce(p_product_type, '')), '') as wanted_product_type,
      -- The outer reservation-aware wrapper is the sole stock-policy owner.
      'all'::text as stock_policy,
      lower(coalesce((
          select ws.value
          from public.website_settings ws
          where ws.tenant_id = p_tenant_id
            and ws.key = 'product_visibility_require_image'
          limit 1
        ), 'false')) in ('true', '1', 'yes', 'si', 'sí') as require_image,
      lower(coalesce((
          select ws.value
          from public.website_settings ws
          where ws.tenant_id = p_tenant_id
            and ws.key = 'product_visibility_require_visible_category'
          limit 1
        ), 'false')) in ('true', '1', 'yes', 'si', 'sí') as require_visible_category,
      lower(coalesce((
          select ws.value
          from public.website_settings ws
          where ws.tenant_id = p_tenant_id
            and ws.key = 'product_visibility_include_uncategorized'
          limit 1
        ), 'true')) in ('true', '1', 'yes', 'si', 'sí') as include_uncategorized
    from (
      select trim(
        regexp_replace(
          unaccent(lower(trim(coalesce(p_search_term, '')))),
          '[^a-z0-9]+',
          ' ',
          'g'
        )
      ) as term
    ) s
    cross join lateral (
      select array_agg(token) as tokens
      from regexp_split_to_table(s.term, '\s+') as token_parts(token)
      where token <> ''
    ) t
  ),
  normalized as (
    -- The normalized texts only matter to a search: without a term every
    -- product passes and the order reads the raw name, price and date, so
    -- they are not computed (nor scored, below).
    select
      p.*,
      a.term,
      a.tokens,
      a.page_limit,
      a.page_offset,
      a.sort_by,
      (
        a.term ~ '(^| )(servicio|servicios|mantencion|mantenciones|reparacion|reparaciones|ajuste|ajustes|instalacion|instalaciones|limpieza|lavado|engrase|sangrado|purga|centrado|enrayado|diagnostico|revision)( |$)'
      ) as service_intent,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(concat_ws(' ', p.website_name, p.name))), '[^a-z0-9]+', ' ', 'g')) end as name_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.sku, ''))), '[^a-z0-9]+', ' ', 'g')) end as sku_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.barcode, ''))), '[^a-z0-9]+', ' ', 'g')) end as barcode_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.gtin, ''))), '[^a-z0-9]+', ' ', 'g')) end as gtin_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.category_name, p.category, ''))), '[^a-z0-9]+', ' ', 'g')) end as category_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.brand, ''))), '[^a-z0-9]+', ' ', 'g')) end as brand_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.model, ''))), '[^a-z0-9]+', ' ', 'g')) end as model_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.manufacturer, ''))), '[^a-z0-9]+', ' ', 'g')) end as manufacturer_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.manufacturer_sku, ''))), '[^a-z0-9]+', ' ', 'g')) end as manufacturer_sku_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(concat_ws(' ', p.website_description, p.description))), '[^a-z0-9]+', ' ', 'g')) end as description_n
    from public.products p
    cross join args a
    where p.tenant_id = p_tenant_id
      and p.is_active = true
      and coalesce(p.is_published, false) = true
      and coalesce(p.show_on_website, false) = true
      and (
        p_product_ids is null
        or cardinality(p_product_ids) = 0
        or p.id = any(p_product_ids)
      )
      and (
        p_category_ids is null
        or cardinality(p_category_ids) = 0
        or p.category_id = any(p_category_ids)
      )
      and (
        a.wanted_sku is null
        or lower(p.sku) = lower(a.wanted_sku)
      )
      and (
        a.wanted_product_type is null
        or p.product_type = a.wanted_product_type
      )
      and (
        not a.require_image
        or nullif(btrim(coalesce(p.website_image_url, '')), '') is not null
        or nullif(btrim(coalesce(p.website_image_url_optimized, '')), '') is not null
        or cardinality(coalesce(p.website_image_urls, array[]::text[])) > 0
        or nullif(btrim(coalesce(p.image_url, '')), '') is not null
        or nullif(btrim(coalesce(p.image_url_optimized, '')), '') is not null
        or cardinality(coalesce(p.image_urls, array[]::text[])) > 0
      )
      and (
        not a.require_visible_category
        or (p.category_id is null and a.include_uncategorized)
        or exists (
          select 1
          from public.product_categories pc
          where pc.id = p.category_id
            and pc.tenant_id = p_tenant_id
            and pc.is_active = true
            and coalesce(pc.show_on_website, false) = true
        )
      )
      and (
        a.stock_policy = 'all'
        or coalesce(p.is_service, false)
        or p.product_type = 'service'
        or (
          a.stock_policy = 'available_only'
          and (
            coalesce(p.track_stock, true) = false
            or coalesce(p.stock_quantity, p.inventory_qty, 0) > 0
          )
        )
        or (
          a.stock_policy = 'out_of_stock_only'
          and coalesce(p.track_stock, true) = true
          and coalesce(p.stock_quantity, p.inventory_qty, 0) <= 0
        )
      )
  ),
  enriched as (
    select
      n.*,
      trim(concat_ws(
        ' ',
        case
          when n.name_n like '%pinon%'
            or n.category_n in ('pinones', 'cassette')
            then 'pinon pinones cassette freewheel rueda libre coronas'
          else null
        end,
        case
          when concat_ws(' ', n.name_n, n.category_n) like '%cadena%'
            then 'cadena chain transmision'
          else null
        end,
        case
          when concat_ws(' ', n.name_n, n.category_n) like '%camara%'
            then 'camara tubo tube valvula neumatico'
          else null
        end,
        case
          when concat_ws(' ', n.name_n, n.category_n) like '%cubierta%'
            or concat_ws(' ', n.name_n, n.category_n) like '%neumatico%'
            then 'cubierta neumatico tire goma'
          else null
        end
      )) as alias_n
    from normalized n
  ),
  matched as (
    select
      e.*,
      (
        case when e.term <> '' and e.sku_n = e.term then 1000 else 0 end +
        case when e.term <> '' and e.barcode_n = e.term then 980 else 0 end +
        case when e.term <> '' and e.gtin_n = e.term then 980 else 0 end +
        case when e.term <> '' and e.name_n = e.term then 850 else 0 end +
        case when e.term <> '' and e.name_n like e.term || '%' then 760 else 0 end +
        case when e.term <> '' and e.name_n like '%' || e.term || '%' then 650 else 0 end +
        case when e.term <> '' and e.category_n = e.term then 620 else 0 end +
        case when e.term <> '' and e.category_n like '%' || e.term || '%' then 560 else 0 end +
        case when e.term <> '' and e.alias_n like '%' || e.term || '%' then 500 else 0 end +
        case when e.term <> '' and e.sku_n like '%' || e.term || '%' then 460 else 0 end +
        case when e.term <> '' and e.manufacturer_sku_n like '%' || e.term || '%' then 420 else 0 end +
        case when e.term <> '' and e.brand_n like '%' || e.term || '%' then 360 else 0 end +
        case when e.term <> '' and e.model_n like '%' || e.term || '%' then 320 else 0 end +
        case when e.term <> '' and e.manufacturer_n like '%' || e.term || '%' then 300 else 0 end
      ) as phrase_strong_score,
      case when e.term = '' then 0 else coalesce((
        select sum(
          case
            when token ~ '^[0-9]+$' and e.sku_n = token then 120
            when token ~ '^[0-9]+$' and e.barcode_n = token then 120
            when token ~ '^[0-9]+$' and e.gtin_n = token then 120
            when token ~ '^[0-9]+$' and e.name_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)') then 70
            when token ~ '^[0-9]+$' and e.category_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)') then 58
            when token ~ '^[0-9]+$' then 0
            when e.name_n like token || '%' then 95
            when e.name_n like '%' || token || '%' then 76
            when e.category_n like '%' || token || '%' then 66
            when e.alias_n like '%' || token || '%' then 56
            when e.sku_n like '%' || token || '%' then 54
            when e.manufacturer_sku_n like '%' || token || '%' then 48
            when e.brand_n like '%' || token || '%' then 42
            when e.model_n like '%' || token || '%' then 38
            when e.manufacturer_n like '%' || token || '%' then 34
            when length(token) >= 4 and greatest(
              word_similarity(token, e.name_n),
              word_similarity(token, e.category_n),
              word_similarity(token, e.brand_n),
              word_similarity(token, e.model_n),
              word_similarity(token, e.manufacturer_n),
              word_similarity(token, e.alias_n)
            ) >= case when length(token) >= 5 then 0.56 else 0.72 end then 28
            else 0
          end
        )
        from unnest(e.tokens) as token_parts(token)
        where token <> ''
      ), 0) end as token_strong_score,
      case when e.term = '' then 0 else coalesce((
        select sum(
          case
            when token ~ '^[0-9]+$' and e.description_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)') then 8
            when token !~ '^[0-9]+$' and e.description_n like '%' || token || '%' then 8
            when token !~ '^[0-9]+$' and length(token) >= 5 and word_similarity(token, e.description_n) >= 0.86 then 5
            else 0
          end
        )
        from unnest(e.tokens) as token_parts(token)
        where token <> ''
      ), 0) end as weak_description_score
    from enriched e
    where e.term = ''
      or not exists (
        select 1
        from unnest(e.tokens) as token_parts(token)
        where token <> ''
          and not (
            (
              token ~ '^[0-9]+$'
              and (
                e.sku_n = token
                or e.barcode_n = token
                or e.gtin_n = token
                or e.name_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)')
                or e.category_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)')
                or e.description_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)')
              )
            )
            or (
              token !~ '^[0-9]+$'
              and (
                e.name_n like '%' || token || '%'
                or e.category_n like '%' || token || '%'
                or e.alias_n like '%' || token || '%'
                or e.sku_n like '%' || token || '%'
                or e.barcode_n like '%' || token || '%'
                or e.gtin_n like '%' || token || '%'
                or e.brand_n like '%' || token || '%'
                or e.model_n like '%' || token || '%'
                or e.manufacturer_n like '%' || token || '%'
                or e.manufacturer_sku_n like '%' || token || '%'
                or e.description_n like '%' || token || '%'
                or (
                  length(token) >= 4
                  and greatest(
                    word_similarity(token, e.name_n),
                    word_similarity(token, e.category_n),
                    word_similarity(token, e.brand_n),
                    word_similarity(token, e.model_n),
                    word_similarity(token, e.manufacturer_n),
                    word_similarity(token, e.alias_n)
                  ) >= case when length(token) >= 5 then 0.56 else 0.72 end
                )
                or (
                  length(token) >= 5
                  and word_similarity(token, e.description_n) >= 0.86
                )
              )
            )
          )
      )
  ),
  scored as (
    select
      m.*,
      (m.phrase_strong_score + m.token_strong_score) as strong_score,
      (
        m.phrase_strong_score +
        m.token_strong_score +
        m.weak_description_score +
        case when m.product_type = 'service' and not m.service_intent
          then -260 else 0 end
      ) as search_score
    from matched m
  ),
  ranked as (
    select s.*
    from scored s
    where s.term = ''
      or s.product_type <> 'service'
      or s.service_intent
      or s.strong_score > 0
      or not exists (
        select 1
        from scored product_match
        where product_match.product_type <> 'service'
          and product_match.strong_score > 0
      )
  ),
  counted as (
    select p.*, count(*) over() as row_total
    from ranked p
  )
  select
    p.id,
    p.tenant_id,
    coalesce(nullif(btrim(p.website_name), ''), p.name) as name,
    p.sku,
    p.barcode,
    coalesce(p.website_price, p.price) as price,
    0::numeric as cost,
    p.inventory_qty,
    p.stock_quantity,
    coalesce(nullif(btrim(p.website_image_url), ''), p.image_url) as image_url,
    coalesce(nullif(btrim(p.website_image_url_optimized), ''), p.image_url_optimized) as image_url_optimized,
    case
      when cardinality(coalesce(p.website_image_urls, array[]::text[])) > 0
        then p.website_image_urls
      else p.image_urls
    end as image_urls,
    p.description,
    p.website_description,
    p.category,
    p.category_id,
    p.category_name,
    p.brand_id,
    p.brand,
    p.model,
    p.manufacturer,
    p.manufacturer_sku,
    p.gtin,
    p.product_type,
    p.track_stock,
    p.is_active,
    p.is_published,
    p.show_on_website,
    p.created_at,
    p.updated_at,
    p.row_total as total_count
  from counted p
  order by
    case when p.term <> '' then p.search_score end desc nulls last,
    case when p.term = '' and p.sort_by = 'price_asc'
      then coalesce(p.website_price, p.price) end asc nulls last,
    case when p.term = '' and p.sort_by = 'price_desc'
      then coalesce(p.website_price, p.price) end desc nulls last,
    case when p.term = '' and p.sort_by = 'newest'
      then p.created_at end desc nulls last,
    coalesce(nullif(btrim(p.website_name), ''), p.name) asc,
    p.id asc
  limit (select page_limit from args)
  offset (select page_offset from args);
$function$;

commit;
