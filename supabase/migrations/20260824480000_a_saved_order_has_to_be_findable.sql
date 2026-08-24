-- Un pedido guardado tiene que poder encontrarse.
--
-- `save_purchase_order_draft_v1` escribía en `purchase_orders` y **ninguna
-- pantalla de la app leía esa tabla**: el operador apretaba «Guardar
-- borrador», salía un folio, y el pedido desaparecía. Guardar en un lugar que
-- nadie puede abrir no es guardar.
--
-- Un solo motor con dos puertas, como el resto del módulo:
--
--   * la ficha del proveedor lo llama con `p_supplier_id` para mostrar los
--     pedidos abiertos con ÉSE proveedor, donde el operador ya está mirando;
--   * la lista de pedidos lo llama sin proveedor.
--
-- Y `purchase_order_lines_v1` devuelve las líneas para **retomar** un borrador:
-- sin eso, reabrir un pedido sería rearmarlo a mano, que es lo mismo que no
-- poder abrirlo.

begin;

create or replace function public.purchase_orders_page_v1(
  p_supplier_id uuid default null,
  p_statuses text[] default array['draft', 'ordered'],
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
  v_items jsonb;
  v_total integer := 0;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if p_limit not between 1 and 120 or p_offset < 0 then
    raise exception 'Invalid order page arguments' using errcode = '22023';
  end if;

  with alcance as (
    select orders.id,
      orders.order_number,
      orders.status,
      orders.order_date,
      orders.expected_date,
      orders.subtotal,
      orders.tax_amount,
      orders.total,
      orders.notes,
      orders.created_at,
      orders.supplier_id,
      supplier.name supplier_name,
      (select count(*) from public.purchase_order_items item
        where item.purchase_order_id = orders.id)::integer line_count,
      (select coalesce(sum(item.quantity), 0) from public.purchase_order_items item
        where item.purchase_order_id = orders.id) unit_count
    from public.purchase_orders orders
    left join public.suppliers supplier
      on supplier.id = orders.supplier_id
      and supplier.tenant_id = v_tenant_id
    where orders.tenant_id = v_tenant_id
      and (p_supplier_id is null or orders.supplier_id = p_supplier_id)
      and (p_statuses is null
           or orders.status::text = any(p_statuses))
  ), contado as (
    select alcance.*, count(*) over ()::integer total_rows
    from alcance
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'orderId', id,
      'orderNumber', order_number,
      'status', status,
      'supplierId', supplier_id,
      'supplierName', coalesce(supplier_name, 'Proveedor sin registro'),
      'orderDate', order_date,
      'expectedDate', expected_date,
      'netTotal', subtotal,
      'ivaAmount', tax_amount,
      'total', total,
      'lineCount', line_count,
      'unitCount', unit_count,
      'notes', notes,
      'createdAt', created_at
    ) order by orden), '[]'::jsonb), coalesce(max(total_rows), 0)
  into v_items, v_total
  from (
    select contado.*,
      row_number() over (
        -- Los borradores primero: son los que esperan una decisión. Dentro de
        -- cada grupo, lo último tocado arriba.
        order by (case when status = 'draft' then 0 else 1 end),
          created_at desc
      ) orden
    from contado
  ) ordenado
  where orden > p_offset and orden <= p_offset + p_limit;

  return jsonb_build_object(
    'items', v_items,
    'total', v_total,
    'returned', jsonb_array_length(v_items),
    'offset', p_offset,
    'asOf', clock_timestamp()
  );
end;
$$;

create or replace function public.purchase_order_lines_v1(
  p_order_id uuid
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
  v_lines jsonb;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.purchase_orders orders
    where orders.id = p_order_id and orders.tenant_id = v_tenant_id
  ) then
    raise exception 'Order not found' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'productId', item.product_id,
      'name', item.description,
      'sku', product.sku,
      'brand', product.brand,
      'quantity', item.quantity,
      'unitCostNet', item.unit_cost
    ) order by item.created_at), '[]'::jsonb)
  into v_lines
  from public.purchase_order_items item
  left join public.products product
    on product.id = item.product_id
    and product.tenant_id = v_tenant_id
  where item.purchase_order_id = p_order_id
    and item.tenant_id = v_tenant_id;

  return jsonb_build_object('lines', v_lines);
end;
$$;

revoke all on function public.purchase_orders_page_v1(uuid, text[], integer, integer)
  from public;
grant execute on function public.purchase_orders_page_v1(uuid, text[], integer, integer)
  to authenticated;
revoke all on function public.purchase_order_lines_v1(uuid) from public;
grant execute on function public.purchase_order_lines_v1(uuid) to authenticated;

commit;
