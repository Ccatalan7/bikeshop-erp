-- La ficha del proveedor: quién es, qué le compramos y qué más tiene.
--
-- El panel de evidencia contesta «por qué ESTE proveedor quedó acá para ESTA
-- línea». Esta función contesta otra pregunta, la que sigue: **abrí al
-- proveedor, ahora muéstrame todo lo suyo** para poder armarle un pedido sin
-- salir del bloque.
--
-- Por eso NO se cuelga de la necesidad activa. Une dos fuentes y dice de cuál
-- viene cada fila, porque no significan lo mismo:
--
--   * `comprado` — sale de las líneas de compra con costo aterrizado. Trae la
--     última factura, su fecha y lo que costó de verdad con flete prorrateado.
--   * `catalogado` — sale de `products.supplier_id`. Existe en la ficha, pero
--     nunca se le compró: su costo es el de la ficha, no un precio pagado.
--
-- Mezclarlas sin decirlo convertiría un costo de ficha —que nadie verificó— en
-- «lo que pagamos», y el operador armaría un pedido con un número inventado.

begin;

create or replace function public.supplier_catalog_page_v1(
  p_supplier_id uuid,
  p_search text default null,
  p_limit integer default 40,
  p_offset integer default 0
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
  v_search text := nullif(btrim(coalesce(p_search, '')), '');
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

  -- La cabecera trae también por dónde se le escribe. El paso de enviar el
  -- pedido lo necesita, y descubrir ahí que no hay teléfono es descubrirlo
  -- tarde: con el dato acá, la pantalla puede ofrecer agregarlo antes.
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

  with comprado as (
    select observation.product_id,
      max(observation.product_name) product_name,
      max(observation.product_sku) product_sku,
      max(observation.brand) brand,
      max(observation.category_path) category_path,
      count(*)::integer times_purchased,
      sum(observation.quantity) total_quantity,
      max(observation.economic_date) last_purchase_at,
      -- El costo que se propone es el de la ÚLTIMA compra, no el promedio:
      -- para pedir hoy, lo que importa es lo último que se pagó.
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
      -- Un costo de ficha no es un precio pagado: viaja en su propio campo y
      -- la pantalla lo rotula distinto.
      comprado.last_landed_unit_cost_net,
      product.cost catalog_cost_net,
      public.inventory_available_quantity_v1(product.tenant_id, product.id)
        available,
      case when comprado.product_id is not null
        then 'comprado' else 'catalogado' end origin
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
    select unificado.*, count(*) over ()::integer total
    from unificado
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'productId', product_id,
      'name', name,
      'sku', sku,
      'brand', brand,
      'categoryPath', category_path,
      'origin', origin,
      'timesPurchased', times_purchased,
      'totalQuantity', total_quantity,
      'lastPurchaseAt', last_purchase_at,
      'lastInvoiceNumber', last_invoice_number,
      'lastLandedUnitCostNet', last_landed_unit_cost_net,
      'catalogCostNet', catalog_cost_net,
      'available', available
    ) order by orden), '[]'::jsonb), coalesce(max(total), 0)
  into v_items, v_total
  from (
    select contado.*,
      row_number() over (
        -- Lo comprado primero y lo más reciente arriba: es lo que se vuelve a
        -- pedir. Lo catalogado queda debajo, visible pero sin disfrazarse de
        -- historial.
        order by (case when origin = 'comprado' then 0 else 1 end),
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
    'returned', jsonb_array_length(v_items),
    'offset', p_offset,
    'asOf', clock_timestamp()
  );
end;
$$;

revoke all on function public.supplier_catalog_page_v1(uuid, text, integer, integer)
  from public;
grant execute on function public.supplier_catalog_page_v1(uuid, text, integer, integer)
  to authenticated;

commit;
