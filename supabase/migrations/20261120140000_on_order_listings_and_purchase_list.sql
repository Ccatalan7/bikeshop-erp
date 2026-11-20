-- Lo que se vende a pedido entra a los listados de la tienda y no ensucia la
-- lista de compras (etapa 6 de cotizaciones, escrita el 2026-11-04 y
-- desplegada el 2026-11-20 con los primeros productos de MKR a pedido).
--
-- Hasta hoy un producto agotado con «Se vende a pedido» (product_on_order_terms
-- activo, con proveedor y plazo) sólo se veía en su ficha, en Google y en una
-- búsqueda con «Incluir agotados»: la regla de stock de la tienda
-- (available_only) lo sacaba de las categorías como a cualquier agotado.
--
-- Ahora el listado, sus filtros y los conteos por categoría lo suman, después
-- de lo que hay en stock: primero lo que se compra ahora, después lo que llega
-- a pedido y, en una búsqueda ampliada, al final lo agotado. «Disponibles» del
-- visitante (p_only_in_stock) sigue mostrando sólo lo que hay.
--
-- No cambian get_public_products ni sus otros lectores: el carrito, los
-- destacados, la ficha y Merchant lo siguen viendo como hoy (lo a pedido se
-- cotiza, no se compra directo). Tampoco get_public_product_category_counts:
-- sólo la lee la tienda Flutter, que lista con get_public_products y
-- quedaría contando lo que no muestra. Lo a pedido se lee con la misma función,
-- pedido por id, y la regla única de venta online (foto, precio, IVA,
-- publicación) decide igual que para todo lo demás.

begin;

set local lock_timeout = '5s';

create or replace function public.catalog_on_order_product_ids_internal_v1(p_tenant_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(array_agg(t.product_id order by t.product_id), array[]::uuid[])
  from public.product_on_order_terms t
  where t.tenant_id = p_tenant_id
    and t.is_active;
$function$;

revoke all on function public.catalog_on_order_product_ids_internal_v1(uuid)
  from public, anon, authenticated, service_role;

comment on function public.catalog_on_order_product_ids_internal_v1(uuid) is
  'Productos con «Se vende a pedido» activo de un taller. Núcleo privado de las '
  'lecturas públicas del catálogo (20261120140000); sin grant.';

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
  ), listed_rows as materialized (
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
  ), on_order as materialized (
    -- Lo que se vende a pedido (Inventario › ficha › «Se vende a pedido»,
    -- product_on_order_terms activo) entra al listado aunque esté en cero,
    -- después de lo que hay (20261120140000). Sin productos a pedido no hay
    -- fila acá y la lectura de abajo no corre.
    select found.ids
    from (
      select public.catalog_on_order_product_ids_internal_v1(p_tenant_id) as ids
    ) found
    where cardinality(found.ids) > 0
  ), on_order_rows as (
    -- La misma lectura canónica, pedida por id: la ficha puntual no filtra
    -- por stock, y la regla única de venta online sigue decidiendo.
    select product.*
    from on_order
    cross join lateral public.get_public_products(
      p_tenant_id := p_tenant_id,
      p_category_ids := p_category_ids,
      p_product_ids := on_order.ids,
      p_search_term := p_search_term,
      p_product_type := p_product_type,
      p_only_in_stock := false,
      p_sort_by := p_sort_by,
      p_limit := 2147483647,
      p_offset := 0
    ) with ordinality as product
    where not exists (
      select 1 from listed_rows listed where listed.id = product.id
    )
  ), base_rows as (
    select listed.* from listed_rows listed
    union all
    select on_order_row.* from on_order_rows on_order_row
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
      -- Lo que se compra ahora, después lo que llega a pedido y al final lo
      -- agotado de una búsqueda ampliada (20261120140000).
      case
        when filtered.product_type = 'service'
          or not coalesce(filtered.track_stock, true)
          or coalesce(filtered.stock_quantity, filtered.inventory_qty, 0) > 0
          then 0
        when exists (
          select 1 from on_order where filtered.id = any(on_order.ids)
        )
          then 1
        when coalesce(p_include_out_of_stock, false)
          then 2
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
  ), listed_universe as materialized (
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
  ), on_order as materialized (
    -- Lo que se vende a pedido (Inventario › ficha › «Se vende a pedido»,
    -- product_on_order_terms activo) entra al listado aunque esté en cero,
    -- después de lo que hay (20261120140000). Sin productos a pedido no hay
    -- fila acá y la lectura de abajo no corre.
    select found.ids
    from (
      select public.catalog_on_order_product_ids_internal_v1(p_tenant_id) as ids
    ) found
    where cardinality(found.ids) > 0
  ), on_order_universe as materialized (
    -- Los filtros cuentan lo mismo que lista el catálogo, a pedido incluido.
    select product.*
    from on_order
    cross join lateral public.get_public_products(
      p_tenant_id := p_tenant_id,
      p_category_ids := null,
      p_product_ids := on_order.ids,
      p_search_term := p_search_term,
      p_product_type := p_product_type,
      p_only_in_stock := false,
      p_sort_by := 'name',
      p_limit := 2147483647,
      p_offset := 0
    ) product
    where not exists (
      select 1 from listed_universe listed where listed.id = product.id
    )
  ), canonical_universe as materialized (
    select listed.* from listed_universe listed
    union all
    select on_order_row.* from on_order_universe on_order_row
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

CREATE OR REPLACE FUNCTION public.get_public_search_category_counts_v1(p_tenant_id uuid, p_search_term text, p_include_out_of_stock boolean DEFAULT false)
 RETURNS TABLE(category_id uuid, item_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with listed as materialized (
    select found.id, found.category_id
    from public.get_public_products(
      p_tenant_id := p_tenant_id,
      p_category_ids := null,
      p_search_term := p_search_term,
      p_product_type := 'product',
      p_only_in_stock := not coalesce(p_include_out_of_stock, false),
      p_sort_by := 'name',
      p_limit := 2147483647,
      p_offset := 0
    ) found
  ), on_order as materialized (
    -- Lo que se vende a pedido (Inventario › ficha › «Se vende a pedido»,
    -- product_on_order_terms activo) entra al listado aunque esté en cero,
    -- después de lo que hay (20261120140000). Sin productos a pedido no hay
    -- fila acá y la lectura de abajo no corre.
    select found.ids
    from (
      select public.catalog_on_order_product_ids_internal_v1(p_tenant_id) as ids
    ) found
    where cardinality(found.ids) > 0
  ), universe as (
    select listed.id, listed.category_id from listed
    union all
    -- Las mismas cifras que el listado de la búsqueda, a pedido incluido.
    select found.id, found.category_id
    from on_order
    cross join lateral public.get_public_products(
      p_tenant_id := p_tenant_id,
      p_category_ids := null,
      p_product_ids := on_order.ids,
      p_search_term := p_search_term,
      p_product_type := 'product',
      p_only_in_stock := false,
      p_sort_by := 'name',
      p_limit := 2147483647,
      p_offset := 0
    ) found
    where not exists (select 1 from listed where listed.id = found.id)
  )
  select found.category_id, count(*)::bigint as item_count
  from universe found
  join public.product_categories category
    on category.id = found.category_id
   and category.tenant_id = p_tenant_id
   and category.is_active = true
  group by found.category_id
$function$;

-- Las fachadas mantienen sus permisos: create or replace no los toca, pero se
-- dejan escritos para que el archivo diga el estado completo.
grant execute on function public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer, boolean) to anon, authenticated;
grant execute on function public.get_public_product_facets_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, boolean) to anon, authenticated;
grant execute on function public.get_public_search_category_counts_v1(uuid, text, boolean) to anon, authenticated;

-- Lista de compras: lo a pedido que nunca se compró para la repisa no es
-- reposición.
--
-- auto_add_low_stock_to_purchase_list mete a smart_purchase_list todo producto
-- que queda en su mínimo o bajo él, también uno recién creado en cero. Un
-- producto que se vende a pedido vive en cero: se le pide al proveedor cuando
-- un cliente lo paga (customer_quote_purchase_orders), así que sumarlo como
-- «por comprar» llenaría la lista de sugerencias que no son. Lo que sí se
-- compró alguna vez para tener (una factura de compra que no es el pedido de
-- una cotización) sigue entrando como siempre: el local lo trabaja en stock y
-- lo a pedido es sólo el respaldo cuando se acaba.

create or replace function public.purchase_list_on_order_only_internal_v1(
  p_tenant_id uuid,
  p_product_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists (
           select 1
             from public.product_on_order_terms t
            where t.tenant_id = p_tenant_id
              and t.product_id = p_product_id
              and t.is_active
         )
     and not exists (
           select 1
             from public.purchase_invoices pi
            cross join lateral jsonb_array_elements(
              case when jsonb_typeof(pi.items) = 'array' then pi.items else '[]'::jsonb end
            ) item
            where pi.tenant_id = p_tenant_id
              and coalesce(pi.status, '') <> 'cancelled'
              and item->>'product_id' = p_product_id::text
              and not exists (
                select 1
                  from public.customer_quote_purchase_orders po
                 where po.tenant_id = p_tenant_id
                   and po.purchase_invoice_id = pi.id
              )
         );
$function$;

revoke all on function public.purchase_list_on_order_only_internal_v1(uuid, uuid)
  from public, anon, authenticated, service_role;

comment on function public.purchase_list_on_order_only_internal_v1(uuid, uuid) is
  'Verdadero si el producto se vende a pedido y nunca se compró para tener '
  '(sólo en pedidos de cotización). La lista de compras no lo sugiere '
  '(20261120140000); sin grant.';

-- El disparador de stock: el cuerpo vivo, con la regla nueva antes de sumar.
CREATE OR REPLACE FUNCTION public.auto_add_low_stock_to_purchase_list()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_supplier_id uuid;
  v_supplier_name text;
  v_rotation_kpi numeric(5,2);
  v_avg_daily_consumption numeric(10,2);
  v_days_since_last_purchase integer;
  v_suggested_qty integer;
  v_priority numeric(5,2);
  v_lead_time_days integer;
  v_estimated_stockout_date timestamp with time zone;
  v_current_stock integer;
begin
  -- Sync inventory_qty to match stock_quantity (stock_quantity is source of truth)
  if NEW.stock_quantity != NEW.inventory_qty then
    NEW.inventory_qty := NEW.stock_quantity;
  end if;
  
  v_current_stock := coalesce(NEW.stock_quantity, NEW.inventory_qty, 0);
  
  -- AUTO-REMOVAL: If stock is now ABOVE minimum level, remove from pending list
  if v_current_stock > NEW.min_stock_level then
    delete from smart_purchase_list
    where product_id = NEW.id
    and status = 'pending'
    and tenant_id = NEW.tenant_id;
    
    if found then
      raise notice '🗑️ Auto-removed product % (%) from purchase list - stock restored to %', NEW.name, NEW.sku, v_current_stock;
    end if;
    
    return NEW;
  end if;
  
  -- AUTO-ADD: Trigger when stock is at or below minimum level
  if v_current_stock <= NEW.min_stock_level then
    
    -- Check if product is already in the purchase list with pending/ordered status
    if exists (
      select 1 from smart_purchase_list
      where product_id = NEW.id
      and status in ('pending', 'ordered')
      and tenant_id = NEW.tenant_id
    ) then
      -- Already in list, just update the current stock
      update smart_purchase_list
      set current_stock = v_current_stock,
          updated_at = now()
      where product_id = NEW.id
      and status in ('pending', 'ordered')
      and tenant_id = NEW.tenant_id;
      
      return NEW;
    end if;
    
    -- Lo que se vende a pedido y nunca se compró para tener no es reposición:
    -- se le pide al proveedor cuando un cliente lo paga (20261120140000).
    if public.purchase_list_on_order_only_internal_v1(NEW.tenant_id, NEW.id) then
      return NEW;
    end if;

    -- Get supplier info
    select s.id, s.name into v_supplier_id, v_supplier_name
    from suppliers s
    where s.tenant_id = NEW.tenant_id
    and s.is_active = true
    order by s.created_at asc
    limit 1;
    
    -- Calculate rotation KPI (sales per day over last 30 days)
    -- NOTE: sales_invoices stores items in JSONB 'items' column, not a separate table
    -- Use text comparison to avoid UUID casting errors with null/empty product_ids
    select 
      coalesce(sum((item->>'quantity')::numeric), 0)::numeric / 30.0
    into v_avg_daily_consumption
    from sales_invoices si,
         jsonb_array_elements(si.items) as item
    where item->>'product_id' = NEW.id::text
    and si.tenant_id = NEW.tenant_id
    and si.date >= now() - interval '30 days'
    and si.status in ('confirmed', 'paid');
    
    v_rotation_kpi := coalesce(v_avg_daily_consumption * 100, 0);
    
    -- Days since last purchase
    -- NOTE: purchase_invoices stores items in JSONB 'items' column
    -- Use text comparison to avoid UUID casting errors with null/empty product_ids
    select extract(day from now() - max(pi.date))::integer
    into v_days_since_last_purchase
    from purchase_invoices pi,
         jsonb_array_elements(pi.items) as item
    where item->>'product_id' = NEW.id::text
    and pi.tenant_id = NEW.tenant_id;
    
    v_days_since_last_purchase := coalesce(v_days_since_last_purchase, 999);
    
    -- Lead time (use 7 days default)
    v_lead_time_days := 7;
    
    -- Calculate suggested quantity
    v_suggested_qty := greatest(
      NEW.max_stock_level - v_current_stock,
      ceil(coalesce(v_avg_daily_consumption, 0.1) * v_lead_time_days * 1.5)::integer,
      1
    );
    
    -- Calculate priority (0-100 scale)
    v_priority := least(100, greatest(0,
      (case when v_current_stock = 0 then 50 else 0 end) +
      (case when v_current_stock <= NEW.min_stock_level * 0.5 then 25 else 0 end) +
      least(v_rotation_kpi, 25)
    ));
    
    -- Estimate stockout date
    if v_avg_daily_consumption > 0 then
      v_estimated_stockout_date := now() + (v_current_stock / v_avg_daily_consumption) * interval '1 day';
    end if;
    
    -- Insert into purchase list with CORRECT column name: suggested_quantity
    insert into smart_purchase_list (
      tenant_id,
      product_id,
      product_name,
      product_sku,
      supplier_id,
      supplier_name,
      suggested_quantity,  -- FIXED: was suggested_qty
      status,
      priority,
      rotation_kpi,
      days_since_last_purchase,
      current_stock,
      min_stock_level,
      avg_daily_consumption,
      lead_time_days,
      estimated_stockout_date,
      notes,
      added_date
    ) values (
      NEW.tenant_id,
      NEW.id,
      NEW.name,
      NEW.sku,
      v_supplier_id,
      v_supplier_name,
      v_suggested_qty,
      'pending',
      v_priority,
      v_rotation_kpi,
      v_days_since_last_purchase,
      v_current_stock,
      NEW.min_stock_level,
      v_avg_daily_consumption,
      v_lead_time_days,
      v_estimated_stockout_date,
      'Auto-added: stock at or below minimum level',
      now()
    );
    
    raise notice '✅ Auto-added product % (%) to purchase list with priority %', NEW.name, NEW.sku, v_priority;
  end if;
  
  return NEW;
end;
$function$;

comment on function public.auto_add_low_stock_to_purchase_list() is
  'Mantiene smart_purchase_list con lo que quedó en su mínimo. Desde '
  '20261120140000 no suma lo que se vende a pedido y nunca se compró para '
  'tener.';

-- Al marcar un producto «Se vende a pedido», sale de la lista la sugerencia
-- automática que el disparador de stock le había puesto (por ejemplo, al
-- crearlo en cero). Sólo la que nadie tocó: pendiente, automática, sin autor,
-- sin cantidad comprada y sin nada enlazado.
create or replace function public.purchase_list_drop_on_order_only_internal_v1()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if NEW.is_active
     and public.purchase_list_on_order_only_internal_v1(NEW.tenant_id, NEW.product_id) then
    delete from public.smart_purchase_list l
     where l.tenant_id = NEW.tenant_id
       and l.product_id = NEW.product_id
       and l.status = 'pending'
       and l.notes like 'Auto-added%'
       and l.added_by is null
       and l.actual_quantity is null
       and l.linked_purchase_invoice_id is null
       and l.linked_expense_id is null
       and l.linked_job_id is null;
  end if;
  return null;
end;
$function$;

revoke all on function public.purchase_list_drop_on_order_only_internal_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_product_on_order_terms_purchase_list on public.product_on_order_terms;
create trigger trg_product_on_order_terms_purchase_list
  after insert or update of is_active on public.product_on_order_terms
  for each row
  execute function public.purchase_list_drop_on_order_only_internal_v1();

commit;
