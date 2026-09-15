-- «Confirmado» tiene que ser confirmado **de esto**.
--
-- La columna decía «12 de 12» en la fila de RBX y el dueño no pudo relacionar
-- el 12 con nada de la pantalla. Tenía razón dos veces:
--
--   1. **El número no tenía referente.** La fila habla de «2 de 9 líneas · 2
--      facturas · 1 producto»; ningún 12 aparece por ningún lado.
--   2. **Contestaba otra pregunta.** El chequeo de portal barre lo que ese
--      proveedor tiene rotando y bajo mínimo —un barrido de reposición— y en
--      esos 12 iban cámaras de 16", 20", 24", 26", 27.5" y hasta una biela. La
--      necesidad era «Cámaras 29 con válvula Schrader». Un solo producto de los
--      doce tenía algo que ver con la pregunta de la fila.
--
-- La fila compara proveedores **para esta necesidad**. Entonces la celda cuenta
-- lo confirmado de los productos de esta necesidad, y nada más. El barrido de
-- reposición sigue existiendo y sigue sirviendo, pero se publica aparte y con
-- su referente dicho: no puede disfrazarse de respuesta a otra pregunta.

begin;

-- **`create or replace` con un parámetro nuevo NO reemplaza: sobrecarga.** La
-- firma vieja de dos argumentos seguía viva y cualquier llamada quedaba
-- ambigua («is not unique»). Se suelta explícitamente antes de crear la nueva.
drop function if exists public.supplier_last_availability_v1(uuid, integer);

create or replace function public.supplier_last_availability_v1(
  p_supplier_id uuid,
  p_limit integer default 12,
  -- Los productos de los que se está hablando. Nulo = todo lo que se le
  -- consultó al proveedor, que es la vista del barrido.
  p_product_ids uuid[] default null
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
  v_items jsonb;
  v_summary jsonb;
  v_scoped integer := 0;
  v_swept integer := 0;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if p_limit not between 1 and 40 then
    raise exception 'Invalid availability arguments' using errcode = '22023';
  end if;

  with latest as (
    select distinct on (check_row.product_id)
      check_row.product_id,
      check_row.supplier_code,
      check_row.status,
      check_row.price_net,
      check_row.stock_quantity,
      check_row.checked_at
    from public.supplier_availability_checks check_row
    where check_row.tenant_id = v_tenant_id
      and check_row.supplier_id = p_supplier_id
      and check_row.product_id is not null
      and check_row.status <> 'probe_missing'
    order by check_row.product_id, check_row.checked_at desc
  ), joined as (
    select latest.*,
      product.name,
      product.cost our_cost,
      case
        when product.cost is null or product.cost <= 0 then null
        when latest.price_net is null then null
        else round(((latest.price_net - product.cost) / product.cost) * 100, 1)
      end drift_percent,
      -- Si la consulta trae un alcance, sólo esos productos cuentan para el
      -- recuento que se publica en la fila.
      (p_product_ids is null
       or latest.product_id = any(p_product_ids)) in_scope
    from latest
    left join public.products product
      on product.id = latest.product_id
      and product.tenant_id = v_tenant_id
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'productId', product_id,
      'name', coalesce(name, 'Producto'),
      'supplierCode', supplier_code,
      'status', status,
      'priceNet', price_net,
      'stockQuantity', stock_quantity,
      'driftPercent', drift_percent,
      'checkedAt', checked_at
    ) order by checked_at desc) filter (where in_scope), '[]'::jsonb),
    jsonb_build_object(
      -- Lo de ESTA pregunta.
      'checked', count(*) filter (where in_scope),
      'available',
        count(*) filter (where in_scope and status = 'available'),
      'outOfStock',
        count(*) filter (where in_scope and status = 'out_of_stock'),
      'notFound', count(*) filter (where in_scope and status = 'not_found'),
      'inconclusive',
        count(*) filter (where in_scope
          and status not in ('available', 'out_of_stock', 'not_found')),
      'lastCheckedAt', max(checked_at) filter (where in_scope),
      -- Y el barrido entero, con su nombre propio, para que un recuento mayor
      -- nunca se lea como si fuera el de la fila.
      'sweptProducts', count(*),
      'sweptAvailable', count(*) filter (where status = 'available'),
      'sweptLastCheckedAt', max(checked_at),
      'scoped', p_product_ids is not null
    )
  into v_items, v_summary
  from joined;

  return jsonb_build_object(
    'items', jsonb_path_query_array(v_items, ('$[0 to ' || (p_limit - 1) || ']')::jsonpath),
    'summary', v_summary,
    'asOf', clock_timestamp()
  );
end;
$$;

revoke all on function public.supplier_last_availability_v1(uuid, integer, uuid[])
  from public;
grant execute on function public.supplier_last_availability_v1(uuid, integer, uuid[])
  to authenticated;

commit;
