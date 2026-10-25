-- 20261024060000: a search widened to what is out of stock lists what can be
-- bought now first.
--
-- 2026-10-24: with «Incluir agotados» (20261024050000), «camara fv» put one of
-- the three tubes in stock among its first six and five at zero: the order was
-- relevance alone. What can be bought goes first and what is out of stock
-- after it, each by relevance; without the option the order is the same as
-- before (out_last is 0 for every row).

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
  ), ranked as (
    -- A search widened to what is out of stock lists what can be bought now
    -- first and what is out of stock after it, each by relevance, as the big
    -- stores do: «Incluir agotados» must not push the three tubes in stock
    -- below the 38 at zero (2026-10-24).
    select filtered.*,
      case
        when coalesce(p_include_out_of_stock, false)
          and not (
            filtered.product_type = 'service'
            or not coalesce(filtered.track_stock, true)
            or coalesce(filtered.stock_quantity, filtered.inventory_qty, 0) > 0
          )
          then 1
        else 0
      end as out_last
    from filtered
  ), paged as (
    select ranked.*, page.total_count as filtered_total
    from ranked
    cross join page_window page
    order by ranked.out_last, ranked.ordinality
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
  order by paged.out_last, paged.ordinality
$function$;
