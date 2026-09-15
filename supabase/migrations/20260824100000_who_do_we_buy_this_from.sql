-- «¿A quién le compramos esto?» — la pregunta que el taller hace de verdad.
--
-- El Asistente de compras sabía comparar candidatos para UN producto exacto
-- (`rank_purchase_candidates`), pero el trabajador nuevo no llega con un
-- producto: llega con «necesito rayos 27.5» o «faltan neumáticos 29 de gama
-- media y alta». Su pregunta es por PROVEEDOR, y no existía forma de
-- contestarla.
--
-- Corrección del dueño, 2026-08-23: «es probable que la mayoría de proveedores
-- tengan rayos, pero al hacer el análisis de compras se puede detectar que
-- principalmente a un solo proveedor se le compran rayos». La señal es la
-- CONCENTRACIÓN del gasto histórico, no la cobertura del catálogo.
--
-- Tres hallazgos de la medición sobre datos reales que gobiernan el diseño:
--
-- 1. La concentración sólo aparece en la hoja que el operador nombra. En
--    `Componentes / Ruedas` el líder tiene 24% sobre 11 proveedores —inútil—;
--    en `Componentes / Ruedas / Rayos` es Derman con 57% sobre 4.
--
-- 2. Se agrega la vista de LÍNEAS, no `purchase_candidate_metrics_v1`. Esa
--    vista trae una fila por producto —267 filas, 267 productos—, así que un
--    producto comprado cinco veces a un proveedor y una al último le
--    atribuiría toda la historia al último. La línea es el hecho.
--
-- 3. Se mide con costo ATERRIZADO (`landed_unit_cost_net`), que ya prorratea
--    el flete. Comparar por precio unitario premiaría al importador barato
--    contra el distribuidor local por una diferencia que el flete se come.
--
-- La gama NO elimina: se informa como mezcla por proveedor.
--
-- La disponibilidad sigue siendo `unverified`: esto es historia de compras,
-- nunca stock del proveedor.

begin;

create or replace function public.assistant_rank_purchase_suppliers_v1(
  p_query text default null,
  p_category text default null,
  p_brand text default null,
  p_limit integer default 5
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_query text;
  v_brand text;
  v_category text;
  v_inferred jsonb;
  v_inferred_categories uuid[];
  v_predicates jsonb := '[]'::jsonb;
  v_items jsonb;
  v_scope jsonb;
  v_evidence jsonb;
  v_total integer := 0;
begin
  select authority.tenant_id, authority.actor_user_id
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.purchases'
  ) authority;

  if octet_length(coalesce(p_query, '')) > 240
     or octet_length(coalesce(p_category, '')) > 160
     or octet_length(coalesce(p_brand, '')) > 80
     or p_limit not between 1 and 10 then
    raise exception 'Invalid supplier ranking arguments' using errcode = '22023';
  end if;

  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_brand := nullif(public.assistant_normalize_query_internal_v1(p_brand), '');
  v_category := nullif(
    public.assistant_normalize_query_internal_v1(p_category), ''
  );

  -- Sin nada que acotar, la respuesta sería «a quién le compramos todo», que
  -- no es una pregunta del taller y devolvería el ranking de proveedores
  -- completo disfrazado de análisis.
  if v_query is null and v_category is null and v_brand is null then
    raise exception 'Invalid supplier ranking arguments' using errcode = '22023';
  end if;

  if v_category is not null and not exists (
    select 1
    from public.product_categories category
    where category.tenant_id = v_authority.tenant_id
      and (
        public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path)
           = v_category
      )
  ) then
    raise exception 'Category not found' using errcode = 'P0002';
  end if;

  -- La frase se traduce igual que en `search_inventory`: la rama nombrada
  -- vuelve como filtro de categoría y las medidas como predicados de ficha.
  -- El residuo es lo único que sigue buscándose como texto libre.
  if v_query is not null then
    v_inferred := public.assistant_infer_technical_predicates_internal_v1(
      v_authority.tenant_id, p_query
    );
    v_predicates := coalesce(v_inferred -> 'predicates', '[]'::jsonb);
    select array_agg((category.value #>> '{}')::uuid)
    into v_inferred_categories
    from jsonb_array_elements(
      coalesce(v_inferred -> 'categories', '[]'::jsonb)
    ) category(value);
    if jsonb_array_length(v_predicates) > 0
       or v_inferred_categories is not null then
      v_query := nullif(
        public.assistant_normalize_query_internal_v1(
          v_inferred ->> 'residual'
        ), ''
      );
    end if;
  end if;
  end if;

  with recursive category_scope as (
    select category.id
    from public.product_categories category
    where category.tenant_id = v_authority.tenant_id
      and v_category is not null
      and (
        public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path)
           = v_category
      )
    union all
    select child.id
    from public.product_categories child
    join category_scope parent on child.parent_id = parent.id
    where child.tenant_id = v_authority.tenant_id and child.is_active is true
  ), requested_predicates as (
    select predicate.value ->> 'field' as field_key,
      predicate.value ->> 'operator' as operator,
      coalesce(predicate.value -> 'values', '[]'::jsonb) as values
    from jsonb_array_elements(v_predicates) predicate(value)
  ), purchased as materialized (
    -- El universo son los productos que ALGUNA vez se compraron: ~267, no el
    -- catálogo entero. Evaluar la ficha ahí adentro es barato.
    select distinct observation.product_id,
      product.category_id,
      public.assistant_normalize_query_internal_v1(concat_ws(' ',
        product.name, product.brand, product.model, product.manufacturer,
        product.category_name, product.category
      )) identity_surface,
      unaccent(lower(concat_ws(' ', product.name, product.brand,
        product.model, product.manufacturer, product.category_name,
        product.category))) identity_raw,
      public.assistant_normalize_query_internal_v1(product.brand) brand_key
    from public.purchase_line_landed_cost_observations_v1 observation
    join public.products product
      on product.id = observation.product_id
     and product.tenant_id = observation.tenant_id
    where observation.tenant_id = v_authority.tenant_id
      and observation.product_id is not null
      and observation.document_status in ('received', 'paid')
  ), matching as materialized (
    select purchased.product_id
    from purchased
    cross join lateral (
      select coalesce(bool_and(source.value in (
          'product_spec', 'identity_fallback'
        )), true) predicates_match
      from requested_predicates predicate
      cross join lateral (
        select public.assistant_inventory_technical_predicate_source_internal_v1(
          v_authority.tenant_id, purchased.product_id, predicate.field_key,
          predicate.operator, predicate.values, purchased.identity_surface,
          purchased.identity_raw
        ) value
      ) source
    ) predicate_state
    where predicate_state.predicates_match
      and (
        v_inferred_categories is null
        or purchased.category_id = any(v_inferred_categories)
      )
      and (
        v_category is null
        or purchased.category_id in (select id from category_scope)
      )
      and (
        v_brand is null
        or position(v_brand in coalesce(purchased.brand_key, '')) > 0
      )
      and (
        v_query is null
        or not exists (
          select 1 from regexp_split_to_table(v_query, ' +') token
          where position(token in purchased.identity_surface) = 0
        )
      )
  ), lines as (
    select observation.supplier_id,
      observation.supplier_name,
      observation.product_id,
      observation.purchase_invoice_id,
      observation.brand,
      observation.economic_date,
      greatest(coalesce(observation.quantity, 0), 0) units,
      greatest(coalesce(observation.quantity, 0), 0)
        * greatest(coalesce(observation.landed_unit_cost_net, 0), 0) spend,
      band.band gama_band
    from public.purchase_line_landed_cost_observations_v1 observation
    join matching on matching.product_id = observation.product_id
    left join public.product_gama_v1 band
      on band.tenant_id = observation.tenant_id
     and band.category_id = observation.category_id
     and lower(btrim(band.brand)) = lower(btrim(observation.brand))
    where observation.tenant_id = v_authority.tenant_id
      and observation.supplier_id is not null
      and observation.document_status in ('received', 'paid')
  ), totals as (
    select nullif(sum(spend), 0) total_spend,
      nullif(sum(units), 0) total_units,
      count(*)::integer total_lines,
      count(distinct product_id)::integer total_products,
      min(economic_date) first_at,
      max(economic_date) last_at
    from lines
  ), by_supplier as (
    select supplier_id,
      max(supplier_name) supplier_name,
      count(*)::integer purchase_lines,
      count(distinct product_id)::integer distinct_products,
      count(distinct purchase_invoice_id)::integer purchase_invoices,
      sum(units) units,
      sum(spend) spend,
      min(economic_date) first_at,
      max(economic_date) last_at,
      count(*) filter (where gama_band = 'alta')::integer gama_alta,
      count(*) filter (where gama_band = 'media')::integer gama_media,
      count(*) filter (where gama_band = 'economica')::integer gama_economica,
      count(*) filter (where gama_band is null)::integer gama_desconocida
    from lines
    group by supplier_id
  ), brands_by_supplier as (
    select supplier_id,
      coalesce(jsonb_agg(brand order by brand_spend desc, brand)
        filter (where brand is not null), '[]'::jsonb) brands
    from (
      select supplier_id, brand, sum(spend) brand_spend,
        row_number() over (
          partition by supplier_id order by sum(spend) desc, brand
        ) position
      from lines
      where brand is not null and btrim(brand) <> ''
      group by supplier_id, brand
    ) ranked
    where position <= 5
    group by supplier_id
  ), scored as (
    select by_supplier.*,
      supplier.website supplier_website,
      supplier.city supplier_city,
      supplier.sales_rep_name,
      supplier.sales_rep_phone,
      supplier.sales_rep_email,
      supplier.phone supplier_phone,
      supplier.email supplier_email,
      nullif(btrim(coalesce(supplier.portal_username, '')), '') is not null
        has_portal_account,
      coalesce(brands_by_supplier.brands, '[]'::jsonb) brands,
      totals.total_spend, totals.total_units, totals.total_lines,
      totals.total_products, totals.first_at global_first, totals.last_at
        global_last,
      (extract(epoch from (statement_timestamp() - by_supplier.last_at))
        / 86400)::integer days_since,
      max(by_supplier.distinct_products) over () max_products
    from by_supplier
    cross join totals
    left join public.suppliers supplier
      on supplier.id = by_supplier.supplier_id
     and supplier.tenant_id = v_authority.tenant_id
    left join brands_by_supplier
      on brands_by_supplier.supplier_id = by_supplier.supplier_id
  ), ranked as (
    select scored.*,
      coalesce(spend / nullif(total_spend, 0), 0) spend_share,
      coalesce(units / nullif(total_units, 0), 0) units_share,
      exp(-greatest(days_since, 0)::numeric / 180) recency_score,
      coalesce(
        distinct_products::numeric / nullif(max_products, 0), 0
      ) breadth_score
    from scored
  ), final as (
    select ranked.*,
      (0.55 * spend_share + 0.20 * units_share
        + 0.15 * recency_score + 0.10 * breadth_score)::numeric
        concentration_score,
      row_number() over (
        order by (0.55 * spend_share + 0.20 * units_share
          + 0.15 * recency_score + 0.10 * breadth_score) desc,
          spend desc, last_at desc, supplier_id
      )::integer rank,
      count(*) over ()::integer matched_suppliers
    from ranked
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank,
      'supplierId', supplier_id,
      'supplierName', supplier_name,
      'supplierWebsite', supplier_website,
      'supplierCity', supplier_city,
      'salesRepName', sales_rep_name,
      'salesRepPhone', coalesce(sales_rep_phone, supplier_phone),
      'salesRepEmail', coalesce(sales_rep_email, supplier_email),
      'hasPortalAccount', has_portal_account,
      'purchaseLines', purchase_lines,
      'purchaseInvoices', purchase_invoices,
      'distinctProducts', distinct_products,
      'purchasedUnits', round(units, 2),
      'landedSpendNet', round(spend, 2),
      'spendSharePercent', round(100 * spend_share, 1),
      'unitsSharePercent', round(100 * units_share, 1),
      'averageLandedUnitCostNet', case
        when units > 0 then round(spend / units, 2) else null end,
      'firstPurchaseAt', first_at,
      'lastPurchaseAt', last_at,
      'daysSinceLastPurchase', days_since,
      'brands', brands,
      'gamaMix', jsonb_build_object(
        'alta', gama_alta, 'media', gama_media,
        'economica', gama_economica, 'sinBanda', gama_desconocida
      ),
      'concentrationScore', round(concentration_score, 6),
      'supplierAvailability', 'unverified'
    ) order by rank) filter (where rank <= p_limit), '[]'::jsonb),
    coalesce(max(matched_suppliers), 0),
    jsonb_build_object(
      'purchaseLines', coalesce(max(total_lines), 0),
      'suppliers', coalesce(max(matched_suppliers), 0),
      'productsMatched', coalesce(max(total_products), 0),
      'landedSpendNet', round(coalesce(max(total_spend), 0), 2),
      'firstPurchaseAt', max(global_first),
      'lastPurchaseAt', max(global_last)
    )
  into v_items, v_total, v_evidence
  from final;

  v_scope := jsonb_build_object(
    'phrase', public.assistant_truncate_utf8_internal_v1(p_query, 240),
    'residualText', v_query,
    'technicalPredicates', v_predicates,
    'categoryFilter', public.assistant_truncate_utf8_internal_v1(
      p_category, 160
    ),
    'brandFilter', public.assistant_truncate_utf8_internal_v1(p_brand, 80),
    'inferredCategoryCount', coalesce(
      array_length(v_inferred_categories, 1), 0
    )
  );

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > p_limit, v_total
  ) || jsonb_build_object(
    'scope', v_scope,
    'evidence', coalesce(v_evidence, jsonb_build_object(
      'purchaseLines', 0, 'suppliers', 0, 'productsMatched', 0,
      'landedSpendNet', 0, 'firstPurchaseAt', null, 'lastPurchaseAt', null
    )),
    'supplierAvailabilitySemantics', 'historical_only_unverified'
  );
end;
$$;

revoke all on function public.assistant_rank_purchase_suppliers_v1(
  text, text, text, integer
) from public, anon, authenticated, service_role;
grant execute on function public.assistant_rank_purchase_suppliers_v1(
  text, text, text, integer
) to authenticated;

commit;
