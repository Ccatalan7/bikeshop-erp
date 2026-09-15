-- La ficha del proveedor no olvida lo que se estaba buscando.
--
-- Se entra a RBX desde una necesidad de «Cámaras 29 con válvula Schrader» y la
-- lista abría con una cámara 26. El operador venía de una búsqueda concreta y
-- la ficha se la ignoraba: para encontrar lo suyo tenía que volver a buscarlo a
-- mano, en la misma pantalla que llegó por eso.
--
-- Lo que coincide con la necesidad va **primero y rotulado**. El resto del
-- catálogo sigue abajo, porque el proveedor tiene más cosas y a veces se entra
-- justamente a mirar eso.
--
-- La coincidencia la resuelve `purchase_query_products_internal_v1`, la misma
-- que usan el ranking y la evidencia. Si usara su propio criterio, la ficha
-- destacaría productos distintos de los que el ranking dijo que calzaban.
--
-- Y las filas traen su foto: 1.365 de 1.612 productos del taller tienen una.
-- Aquí no aplica lo de la foto del proveedor —donde el monograma es el estado
-- normal porque no hay ninguna—: acá la foto es el caso común y su ausencia la
-- excepción.

begin;

drop function if exists public.supplier_catalog_page_v1(uuid, text, integer, integer);

create or replace function public.supplier_catalog_page_v1(
  p_supplier_id uuid,
  p_search text default null,
  p_limit integer default 40,
  p_offset integer default 0,
  -- Lo que el operador venía buscando. Nulo = se entró sin contexto.
  p_need_phrase text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '9000ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_supplier jsonb;
  v_metrics jsonb;
  v_items jsonb;
  v_total integer := 0;
  v_matched integer := 0;
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
    -- La MISMA resolución que usan el ranking y la evidencia. Un criterio
    -- propio destacaría productos distintos de los que el ranking dijo que
    -- calzaban, y las dos pantallas se contradirían.
    select distinct resolved.product_id
    from public.purchase_query_products_internal_v1(
      v_tenant_id, coalesce(v_phrase, ''), false
    ) resolved
    where v_phrase is not null
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
      product.cost catalog_cost_net,
      public.inventory_available_quantity_v1(product.tenant_id, product.id)
        available,
      case when comprado.product_id is not null
        then 'comprado' else 'catalogado' end origin,
      -- La optimizada primero: pesa menos y la fila la muestra en 38 px.
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
      'catalogCostNet', catalog_cost_net,
      'available', available
    ) order by orden), '[]'::jsonb),
    coalesce(max(total), 0), coalesce(max(matched), 0)
  into v_items, v_total, v_matched
  from (
    select contado.*,
      row_number() over (
        -- **Lo que se estaba buscando, primero.** Después lo comprado sobre lo
        -- sólo catalogado, y lo más reciente arriba: es lo que se vuelve a
        -- pedir.
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
    'returned', jsonb_array_length(v_items),
    'offset', p_offset,
    'asOf', clock_timestamp()
  );
end;
$$;

revoke all on function public.supplier_catalog_page_v1(uuid, text, integer, integer, text)
  from public;
grant execute on function public.supplier_catalog_page_v1(uuid, text, integer, integer, text)
  to authenticated;

commit;
