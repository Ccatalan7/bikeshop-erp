-- Por qué ESTE proveedor: la evidencia detrás de su puesto.
--
-- El ranking dice «Derman 57%» y el operador tiene que creerlo. Esta función
-- abre la caja: qué compras suyas calzaron con lo que pidió —producto, número
-- de factura, fecha, cantidad y costo aterrizado—, y qué métricas lo pusieron
-- ahí, con el peso que cada una tiene en el puntaje.
--
-- Mira EXACTAMENTE los mismos productos que el ranking, porque usa el mismo
-- `purchase_query_products_internal_v1`. Si usara su propio criterio, el panel
-- diría un porcentaje y mostraría otras compras debajo.
--
-- **Sin historial de compra cae al inventario**, que es lo que el taller pidió:
-- que un proveedor sin compras previas de esa línea igual muestre qué tiene
-- catalogado, marcado como lo que es y nunca contado como historial.

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
as $$
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
$$;

revoke all on function public.purchase_supplier_evidence_v1(uuid, jsonb, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.purchase_supplier_evidence_v1(uuid, jsonb, integer)
  to authenticated;

commit;
