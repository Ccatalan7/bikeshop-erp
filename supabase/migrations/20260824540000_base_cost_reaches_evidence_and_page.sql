-- El costo sin flete llega también a la evidencia y a la ficha.
--
-- Complemento del motor de concentración: si la tabla puede mostrar el costo de
-- mercadería pero la evidencia y el catálogo del proveedor sólo tienen el
-- aterrizado, el operador cambia el interruptor y la mitad de la pantalla sigue
-- contando otra cosa.
--
-- Los defaults de cada firma se conservan tal cual están vivos: cambiarlos en
-- un `create or replace` hace que Postgres se niegue.

begin;

create or replace function public.purchase_supplier_evidence_v1(
  p_supplier_id uuid,
  p_queries jsonb,
  p_limit integer default 6
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '9000ms'
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_need text;
  v_needs jsonb := '[]'::jsonb;
  v_lines jsonb;
  v_stock jsonb;
  v_count integer := 0;
  v_metrics jsonb;
  v_supplier jsonb;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if jsonb_typeof(p_queries) <> 'array'
     or jsonb_array_length(p_queries) < 1
     or jsonb_array_length(p_queries) > 6
     or p_limit not between 1 and 12 then
    raise exception 'Invalid evidence arguments' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.suppliers supplier
    where supplier.id = p_supplier_id and supplier.tenant_id = v_tenant_id
  ) then
    raise exception 'Supplier not found' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'id', supplier.id,
    'name', supplier.name,
    'city', supplier.city,
    'website', supplier.website,
    'salesRepName', supplier.sales_rep_name,
    'salesRepPhone', coalesce(supplier.sales_rep_phone, supplier.phone),
    'salesRepEmail', coalesce(supplier.sales_rep_email, supplier.email),
    'hasPortalAccount',
      nullif(btrim(coalesce(supplier.portal_username, '')), '') is not null
  )
  into v_supplier
  from public.suppliers supplier
  where supplier.id = p_supplier_id and supplier.tenant_id = v_tenant_id;

  for v_need in
    select btrim(item.value #>> '{}')
    from jsonb_array_elements(p_queries) item(value)
    where btrim(coalesce(item.value #>> '{}', '')) <> ''
  loop
    -- Las compras de ESTE proveedor que calzan con ESTA línea, lo más reciente
    -- primero: la fecha es lo que el operador usa para saber si el precio
    -- todavía significa algo.
    select coalesce(jsonb_agg(fila order by fecha desc nulls last), '[]'::jsonb)
    into v_lines
    from (
      select jsonb_build_object(
          'productName', observation.product_name,
          'productSku', observation.product_sku,
          'brand', observation.brand,
          'quantity', round(observation.quantity, 2),
          'landedUnitCostNet', round(observation.landed_unit_cost_net, 2),
          -- Sólo la mercadería: es lo que el proveedor cobró, sin el flete que
          -- pagamos aparte y prorrateamos después.
          'baseUnitCostNet', round(observation.base_unit_cost_net, 2),
          'invoiceNumber', observation.invoice_number,
          'purchaseDate', observation.economic_date,
          'categoryPath', observation.category_path
        ) fila,
        observation.economic_date fecha
      from public.purchase_line_landed_cost_observations_v1 observation
      join public.purchase_query_products_internal_v1(
        v_tenant_id, v_need, true
      ) resolved on resolved.product_id = observation.product_id
      where observation.tenant_id = v_tenant_id
        and observation.supplier_id = p_supplier_id
        and observation.document_status in ('received', 'paid')
      order by observation.economic_date desc nulls last
      limit p_limit
    ) recientes;

    -- Sin compras de esta línea, lo que ese proveedor tiene catalogado. Es otra
    -- cosa y se rotula como otra cosa: nunca entra al historial ni al puntaje.
    v_stock := '[]'::jsonb;
    if jsonb_array_length(v_lines) = 0 then
      select coalesce(jsonb_agg(fila order by nombre), '[]'::jsonb)
      into v_stock
      from (
        select jsonb_build_object(
            'productName', product.name,
            'productSku', product.sku,
            'brand', product.brand,
            'stock', public.inventory_available_quantity_v1(
              product.tenant_id, product.id
            ),
            'costNet', product.cost,
            'priceGross', product.price
          ) fila,
          product.name nombre
        from public.products product
        join public.purchase_query_products_internal_v1(
          v_tenant_id, v_need, false
        ) resolved on resolved.product_id = product.id
        where product.tenant_id = v_tenant_id
          and product.supplier_id = p_supplier_id
          and product.is_active is true
        order by product.name
        limit p_limit
      ) catalogados;
    end if;

    v_needs := v_needs || jsonb_build_array(jsonb_build_object(
      'need', v_need,
      'purchases', v_lines,
      'catalog', v_stock
    ));
    v_count := v_count + 1;
  end loop;

  -- Las métricas que llevaron al puesto, con el peso que cada una tiene en el
  -- puntaje. Publicar el número sin su peso deja al operador adivinando cuál
  -- pesó, que es justo lo que este panel viene a evitar.
  with resolved as materialized (
    select distinct r.product_id
    from jsonb_array_elements(p_queries) item(value)
    cross join lateral public.purchase_query_products_internal_v1(
      v_tenant_id, btrim(item.value #>> '{}'), true
    ) r
  ), lines as (
    select observation.supplier_id,
      observation.product_id,
      observation.purchase_invoice_id,
      observation.economic_date,
      greatest(coalesce(observation.quantity, 0), 0) units,
      greatest(coalesce(observation.quantity, 0), 0)
        * greatest(coalesce(observation.landed_unit_cost_net, 0), 0) spend
    from public.purchase_line_landed_cost_observations_v1 observation
    join resolved on resolved.product_id = observation.product_id
    where observation.tenant_id = v_tenant_id
      and observation.supplier_id is not null
      and observation.document_status in ('received', 'paid')
  )
  select jsonb_build_object(
    'purchaseLines', count(*) filter (where supplier_id = p_supplier_id),
    'purchaseInvoices', count(distinct purchase_invoice_id)
      filter (where supplier_id = p_supplier_id),
    'distinctProducts', count(distinct product_id)
      filter (where supplier_id = p_supplier_id),
    'purchasedUnits', round(coalesce(
      sum(units) filter (where supplier_id = p_supplier_id), 0), 2),
    'landedSpendNet', round(coalesce(
      sum(spend) filter (where supplier_id = p_supplier_id), 0), 2),
    'averageLandedUnitCostNet', case
      when coalesce(sum(units) filter (where supplier_id = p_supplier_id), 0) > 0
        then round(
          sum(spend) filter (where supplier_id = p_supplier_id)
          / sum(units) filter (where supplier_id = p_supplier_id), 2)
      else null end,
    'firstPurchaseAt', min(economic_date) filter (where supplier_id = p_supplier_id),
    'lastPurchaseAt', max(economic_date) filter (where supplier_id = p_supplier_id),
    'spendSharePercent', round(100 * coalesce(
      sum(spend) filter (where supplier_id = p_supplier_id)
      / nullif(sum(spend), 0), 0), 1),
    'unitsSharePercent', round(100 * coalesce(
      sum(units) filter (where supplier_id = p_supplier_id)
      / nullif(sum(units), 0), 0), 1),
    'totalPurchaseLines', count(*),
    'totalSuppliers', count(distinct supplier_id),
    'weights', jsonb_build_object(
      'spendShare', 0.55,
      'unitsShare', 0.20,
      'recency', 0.15,
      'breadth', 0.10
    )
  )
  into v_metrics
  from lines;

  return jsonb_build_object(
    'asOf', clock_timestamp(),
    'supplier', v_supplier,
    'metrics', coalesce(v_metrics, '{}'::jsonb),
    'needs', v_needs,
    'needCount', v_count,
    'supplierAvailabilitySemantics', 'historical_only_unverified'
  );
end;
$function$;

-- La ficha del proveedor publica los dos costos por producto.
create or replace function public.supplier_catalog_page_v1(
  p_supplier_id uuid,
  p_search text default null,
  p_limit integer default 40,
  p_offset integer default 0,
  p_need_phrase text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '9000ms'
as $ficha$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_supplier jsonb;
  v_metrics jsonb;
  v_items jsonb;
  v_total integer := 0;
  v_matched integer := 0;
  v_dropped_words text;
  v_dropped_filters text;
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
  v_phrase text := nullif(btrim(coalesce(p_need_phrase, '')), '');
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if p_limit not between 1 and 120 or p_offset < 0 then
    raise exception 'Invalid catalog page arguments' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.suppliers supplier
    where supplier.id = p_supplier_id and supplier.tenant_id = v_tenant_id
  ) then
    raise exception 'Supplier not found' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'id', supplier.id,
    'name', supplier.name,
    'legalName', supplier.legal_name,
    'tradeName', supplier.trade_name,
    'rut', supplier.rut,
    'city', supplier.city,
    'website', supplier.website,
    'imageUrl', supplier.image_url,
    'paymentTerms', supplier.payment_terms,
    'purchaseInstructions', supplier.purchase_instructions,
    'salesRepName', supplier.sales_rep_name,
    'salesRepPhone', coalesce(supplier.sales_rep_phone, supplier.phone),
    'salesRepEmail', coalesce(supplier.sales_rep_email, supplier.email),
    'phone', supplier.phone,
    'email', supplier.email,
    'hasPortalAccount',
      nullif(btrim(coalesce(supplier.portal_username, '')), '') is not null
  )
  into v_supplier
  from public.suppliers supplier
  where supplier.id = p_supplier_id and supplier.tenant_id = v_tenant_id;

  select jsonb_build_object(
    'purchaseLines', coalesce(count(*), 0)::integer,
    'purchaseInvoices',
      coalesce(count(distinct observation.purchase_invoice_id), 0)::integer,
    'distinctProducts',
      coalesce(count(distinct observation.product_id), 0)::integer,
    'landedSpendNet',
      coalesce(sum(observation.merchandise_net_amount
        + coalesce(observation.allocated_freight_net, 0)), 0),
    'purchasedUnits', coalesce(sum(observation.quantity), 0),
    'firstPurchaseAt', min(observation.economic_date),
    'lastPurchaseAt', max(observation.economic_date)
  )
  into v_metrics
  from public.purchase_line_landed_cost_observations_v1 observation
  where observation.tenant_id = v_tenant_id
    and observation.supplier_id = p_supplier_id;

  with pedido as (
    select resolved.product_id,
      resolved.dropped_words,
      resolved.dropped_filters
    from public.purchase_query_products_internal_v1(
      v_tenant_id, coalesce(v_phrase, ''), false
    ) resolved
    where v_phrase is not null
  ), medida as (
    select max(dropped_words) dropped_words,
      max(dropped_filters) dropped_filters
    from pedido
  ), comprado as (
    select observation.product_id,
      max(observation.product_name) product_name,
      max(observation.product_sku) product_sku,
      max(observation.brand) brand,
      max(observation.category_path) category_path,
      count(*)::integer times_purchased,
      sum(observation.quantity) total_quantity,
      max(observation.economic_date) last_purchase_at,
      (array_agg(observation.landed_unit_cost_net
        order by observation.economic_date desc nulls last))[1]
        last_landed_unit_cost_net,
      -- Lo que el proveedor cobró, sin el flete que pagamos aparte.
      (array_agg(observation.base_unit_cost_net
        order by observation.economic_date desc nulls last))[1]
        last_base_unit_cost_net,
      (array_agg(observation.invoice_number
        order by observation.economic_date desc nulls last))[1]
        last_invoice_number
    from public.purchase_line_landed_cost_observations_v1 observation
    where observation.tenant_id = v_tenant_id
      and observation.supplier_id = p_supplier_id
      and observation.product_id is not null
    group by observation.product_id
  ), unificado as (
    select product.id product_id,
      product.name,
      product.sku,
      product.brand,
      coalesce(comprado.category_path, product.category_name) category_path,
      coalesce(comprado.times_purchased, 0) times_purchased,
      comprado.total_quantity,
      comprado.last_purchase_at,
      comprado.last_invoice_number,
      comprado.last_landed_unit_cost_net,
      comprado.last_base_unit_cost_net,
      product.cost catalog_cost_net,
      public.inventory_available_quantity_v1(product.tenant_id, product.id)
        available,
      case when comprado.product_id is not null
        then 'comprado' else 'catalogado' end origin,
      coalesce(
        nullif(btrim(coalesce(product.image_url_optimized, '')), ''),
        nullif(btrim(coalesce(product.image_url, '')), '')
      ) image_url,
      exists (select 1 from pedido where pedido.product_id = product.id)
        matches_need
    from public.products product
    left join comprado on comprado.product_id = product.id
    where product.tenant_id = v_tenant_id
      and product.is_active is true
      and (comprado.product_id is not null
           or product.supplier_id = p_supplier_id)
      and (
        v_search is null
        or product.name ilike '%' || v_search || '%'
        or coalesce(product.sku, '') ilike '%' || v_search || '%'
        or coalesce(product.brand, '') ilike '%' || v_search || '%'
      )
  ), contado as (
    select unificado.*,
      count(*) over ()::integer total,
      count(*) filter (where matches_need) over ()::integer matched
    from unificado
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'productId', product_id,
      'name', name,
      'sku', sku,
      'brand', brand,
      'categoryPath', category_path,
      'origin', origin,
      'imageUrl', image_url,
      'matchesNeed', matches_need,
      'timesPurchased', times_purchased,
      'totalQuantity', total_quantity,
      'lastPurchaseAt', last_purchase_at,
      'lastInvoiceNumber', last_invoice_number,
      'lastLandedUnitCostNet', last_landed_unit_cost_net,
      'lastBaseUnitCostNet', last_base_unit_cost_net,
      'catalogCostNet', catalog_cost_net,
      'available', available
    ) order by orden), '[]'::jsonb),
    coalesce(max(total), 0), coalesce(max(matched), 0),
    max(dropped_words), max(dropped_filters)
  into v_items, v_total, v_matched, v_dropped_words, v_dropped_filters
  from (
    select contado.*,
      (select medida.dropped_words from medida) dropped_words,
      (select medida.dropped_filters from medida) dropped_filters,
      row_number() over (
        order by (case when matches_need then 0 else 1 end),
          (case when origin = 'comprado' then 0 else 1 end),
          last_purchase_at desc nulls last,
          times_purchased desc,
          name
      ) orden
    from contado
  ) ordenado
  where orden > p_offset and orden <= p_offset + p_limit;

  return jsonb_build_object(
    'supplier', v_supplier,
    'metrics', v_metrics,
    'items', v_items,
    'total', v_total,
    'matched', v_matched,
    'needPhrase', v_phrase,
    -- Qué tuvo que soltar la búsqueda para poder contestar. Sin esto, el
    -- rótulo prometía una coincidencia exacta sobre un resultado ampliado:
    -- una cámara V/FRANCESA bajo «válvula Schrader».
    'droppedWords', v_dropped_words,
    'droppedFilters', v_dropped_filters,
    'returned', jsonb_array_length(v_items),
    'offset', p_offset,
    'asOf', clock_timestamp()
  );
end;
$ficha$;

revoke all on function public.supplier_catalog_page_v1(uuid, text, integer, integer, text)
  from public;
grant execute on function public.supplier_catalog_page_v1(uuid, text, integer, integer, text)
  to authenticated;

commit;
