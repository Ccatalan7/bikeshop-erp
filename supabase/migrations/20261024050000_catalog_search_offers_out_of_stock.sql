-- 20261024050000: a search can include what is out of stock, when the store
-- offers it.
--
-- 2026-10-24, owner, seeing «camara fv» answer 3 tubes of the 41 the store
-- publishes (38 at zero): «put an option on the search to show the agotados
-- as well». The store's rule (product_visibility_stock_policy =
-- available_only) keeps out-of-stock products out of every listing, and the
-- catalog reads asked get_public_products for that universe only: a visitor
-- could narrow it, never widen it.
--
-- What changes:
--   1. A store setting, product_visibility_search_out_of_stock ('offer', the
--      default without a row, or 'hide'), edited in the ERP's «Reglas de la
--      tienda» next to the stock rule.
--   2. get_public_products lets a search through to what is out of stock when
--      its caller does not ask for stock only, there is a search term and the
--      store offers it. Without a term (a category, the home, a block) the
--      rule is the same.
--   3. get_public_products_faceted_v2 and get_public_product_facets_v2 take
--      p_include_out_of_stock (false by default, last): a caller that does not
--      send it reads as before. They are recreated in one transaction, with
--      their grants (visitors only: the default grant to service_role is
--      taken back, as before).

begin;

CREATE OR REPLACE FUNCTION public.get_public_products(p_tenant_id uuid, p_category_ids uuid[] DEFAULT NULL::uuid[], p_product_ids uuid[] DEFAULT NULL::uuid[], p_sku text DEFAULT NULL::text, p_search_term text DEFAULT NULL::text, p_product_type text DEFAULT NULL::text, p_only_in_stock boolean DEFAULT true, p_sort_by text DEFAULT 'name'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, tenant_id uuid, name text, sku text, barcode text, price numeric, cost numeric, inventory_qty integer, stock_quantity integer, image_url text, image_url_optimized text, image_urls text[], description text, website_description text, category text, category_id uuid, category_name text, brand_id uuid, brand text, model text, manufacturer text, manufacturer_sku text, gtin text, product_type text, track_stock boolean, is_active boolean, is_published boolean, show_on_website boolean, created_at timestamp with time zone, updated_at timestamp with time zone, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with policy as (
    select case
      -- Una ficha pide productos puntuales sin filtrar por stock: un agotado
      -- conserva su ficha (con «Agotado» y sin compra) aunque el sitio oculte
      -- los agotados de los listados. Destacados, carrito y listados piden
      -- con p_only_in_stock y siguen el ajuste del sitio.
      when not coalesce(p_only_in_stock, true)
        and (
          coalesce(cardinality(p_product_ids), 0) > 0
          or nullif(btrim(coalesce(p_sku, '')), '') is not null
        )
        then 'all'
      -- Una búsqueda que el visitante amplía a los agotados («Incluir
      -- agotados»), si la tienda lo ofrece (Reglas de la tienda:
      -- product_visibility_search_out_of_stock, 'offer' sin ajuste): quien
      -- busca encuentra lo que existe aunque hoy no haya stock, con su
      -- «Agotado» (2026-10-24).
      when not coalesce(p_only_in_stock, true)
        and nullif(btrim(coalesce(p_search_term, '')), '') is not null
        and lower(coalesce(nullif(btrim(coalesce((
          select setting.value
            from public.website_settings setting
           where setting.tenant_id = p_tenant_id
             and setting.key = 'product_visibility_search_out_of_stock'
           limit 1
        ), '')), ''), 'offer')) = 'offer'
        then 'all'
      else case lower(coalesce(
        nullif(btrim(coalesce((
          select setting.value
            from public.website_settings setting
           where setting.tenant_id = p_tenant_id
             and setting.key = 'product_visibility_stock_policy'
           limit 1
        ), '')), ''),
        case when p_only_in_stock then 'available_only' else 'all' end
      ))
        when 'all' then 'all'
        when 'both' then 'all'
        when 'out_of_stock_only' then 'out_of_stock_only'
        when 'out_of_stock' then 'out_of_stock_only'
        when 'sin_stock' then 'out_of_stock_only'
        else 'available_only'
      end
    end as stock_policy
  ), raw_rows as (
    select raw.*
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id,
        p_category_ids,
        p_product_ids,
        p_sku,
        p_search_term,
        p_product_type,
        false,
        p_sort_by,
        2147483647,
        0
      ) with ordinality as raw
  ), candidate as (
    -- One join instead of one function call per row. `is_set` and `is_service`
    -- are the only facts the inner catalog query does not already return.
    select r.id,
           r.tenant_id,
           r.stock_quantity,
           r.inventory_qty,
           coalesce(product.is_set, false) as is_set,
           coalesce(product.is_service, false) as is_service
      from raw_rows r
      join public.products product
        on product.id = r.id
       and product.tenant_id = r.tenant_id
     where r.product_type is distinct from 'service'
       and coalesce(r.track_stock, true)
  ), reserved as (
    -- Aggregated once for the whole tenant, then joined. Covers both the
    -- products themselves and the components of any set among them.
    select reservation.product_id,
           sum(reservation.quantity)::integer as quantity
      from public.online_order_inventory_reservations reservation
     where reservation.tenant_id = p_tenant_id
       and reservation.state = 'active'
       and reservation.expires_at > clock_timestamp()
     group by reservation.product_id
  ), simple_availability as (
    select candidate.id,
           greatest(
             coalesce(candidate.stock_quantity, candidate.inventory_qty, 0)
               - coalesce(reserved.quantity, 0),
             0
           ) as available_quantity
      from candidate
      left join reserved on reserved.product_id = candidate.id
     where not candidate.is_set
       and not candidate.is_service
  ), set_availability as (
    -- A set is limited by its scarcest component. An inner join means a set
    -- with no components produces no row here and resolves to zero below,
    -- which is what the per-row function returned for that case.
    select candidate.id,
           min(greatest(floor(
             (
               coalesce(component.stock_quantity, component.inventory_qty, 0)
               - coalesce(component_reserved.quantity, 0)
             )::numeric / set_component.quantity_in_set
           ), 0))::integer as available_quantity
      from candidate
      join public.product_set_components set_component
        on set_component.tenant_id = candidate.tenant_id
       and set_component.set_product_id = candidate.id
      join public.products component
        on component.id = set_component.component_product_id
       and component.tenant_id = set_component.tenant_id
      left join reserved component_reserved
        on component_reserved.product_id = component.id
     where candidate.is_set
       and not candidate.is_service
     group by candidate.id
  ), availability as (
    select id, available_quantity from simple_availability
    union all
    select id, available_quantity from set_availability
  ), base_rows as (
    select r.*,
           case
             when r.product_type = 'service'
               or not coalesce(r.track_stock, true)
               or coalesce(service_like.is_service, false)
               then greatest(coalesce(r.stock_quantity, r.inventory_qty, 0), 0)
             else coalesce(availability.available_quantity, 0)
           end as available_quantity
      from raw_rows r
      left join availability on availability.id = r.id
      left join candidate service_like on service_like.id = r.id
  ), filtered as (
    select base.*
      from base_rows base
      cross join policy
     where policy.stock_policy = 'all'
        or base.product_type = 'service'
        -- Un producto de venta que no controla stock pasa como antes; un
        -- consumible del taller (que tampoco lleva) ya no llega hasta aquí:
        -- lo saca la regla única en la lectura interna.
        or not coalesce(base.track_stock, true)
        or (
          policy.stock_policy = 'available_only'
          and base.available_quantity > 0
        )
        or (
          policy.stock_policy = 'out_of_stock_only'
          and base.available_quantity <= 0
        )
  ), paged as (
    select filtered.*,
           count(*) over() as filtered_total
      from filtered
     order by filtered.ordinality
     limit greatest(coalesce(p_limit, 20), 0)
     offset greatest(coalesce(p_offset, 0), 0)
  )
  select
    paged.id,
    paged.tenant_id,
    paged.name,
    paged.sku,
    paged.barcode,
    paged.price,
    paged.cost,
    case
      when paged.product_type = 'service'
        or not coalesce(paged.track_stock, true)
        then paged.inventory_qty
      else paged.available_quantity
    end as inventory_qty,
    case
      when paged.product_type = 'service'
        or not coalesce(paged.track_stock, true)
        then paged.stock_quantity
      else paged.available_quantity
    end as stock_quantity,
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
    paged.filtered_total as total_count
  from paged
  order by paged.ordinality;
$function$;

drop function if exists public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer);

CREATE OR REPLACE FUNCTION public.get_public_products_faceted_v2(p_tenant_id uuid, p_category_ids uuid[] DEFAULT NULL::uuid[], p_search_term text DEFAULT NULL::text, p_product_type text DEFAULT NULL::text, p_only_in_stock boolean DEFAULT true, p_brand_ids uuid[] DEFAULT NULL::uuid[], p_min_price numeric DEFAULT NULL::numeric, p_max_price numeric DEFAULT NULL::numeric, p_spec_filters jsonb DEFAULT NULL::jsonb, p_sort_by text DEFAULT 'name'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0, p_include_out_of_stock boolean DEFAULT false)
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
      -- returns. A visitor can narrow a rule, never widen it, except a search
      -- the store lets them widen to what is out of stock
      -- (p_include_out_of_stock; the rule decides in get_public_products).
      p_only_in_stock := not coalesce(p_include_out_of_stock, false),
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

revoke all on function public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer, boolean) from public, service_role;
grant execute on function public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer, boolean) to anon, authenticated;

drop function if exists public.get_public_product_facets_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb);

CREATE OR REPLACE FUNCTION public.get_public_product_facets_v2(p_tenant_id uuid, p_category_ids uuid[] DEFAULT NULL::uuid[], p_search_term text DEFAULT NULL::text, p_product_type text DEFAULT NULL::text, p_only_in_stock boolean DEFAULT true, p_brand_ids uuid[] DEFAULT NULL::uuid[], p_min_price numeric DEFAULT NULL::numeric, p_max_price numeric DEFAULT NULL::numeric, p_spec_filters jsonb DEFAULT NULL::jsonb, p_include_out_of_stock boolean DEFAULT false)
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
      -- A search the store lets the visitor widen to what is out of stock.
      p_only_in_stock := not coalesce(p_include_out_of_stock, false),
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

revoke all on function public.get_public_product_facets_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, boolean) from public, service_role;
grant execute on function public.get_public_product_facets_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, boolean) to anon, authenticated;

commit;

notify pgrst, 'reload schema';
