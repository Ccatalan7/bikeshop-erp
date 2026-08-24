-- Las ventas viven dentro del documento, no en una tabla de líneas.
--
-- `supplier_availability_targets_v1` consultaba `public.sales_invoice_lines`,
-- que no existe: las líneas de una factura de venta son un arreglo JSON en
-- `sales_invoices.items`, igual que en las de compra. La función fallaba entera
-- —«relation does not exist»— así que el chequeo no tenía a quién preguntar.
--
-- Un error que ninguna prueba de definición podía ver: la función era válida
-- al crearse y sólo revienta al ejecutarse, que es la trampa ya documentada de
-- PL/pgSQL.

begin;

create or replace function public.supplier_availability_targets_v1(
  p_supplier_id uuid,
  p_limit integer default 12
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
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if p_limit not between 1 and 40 then
    raise exception 'Invalid target arguments' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.suppliers supplier
    where supplier.id = p_supplier_id and supplier.tenant_id = v_tenant_id
  ) then
    raise exception 'Supplier not found' using errcode = 'P0002';
  end if;

  with candidates as (
    select product.id,
      product.name,
      product.supplier_code,
      public.inventory_available_quantity_v1(product.tenant_id, product.id)
        available,
      greatest(coalesce(product.min_stock_level, 0), 0) minimum,
      -- Lo que se movió en 90 días: sin esto el chequeo gasta minutos en
      -- productos que nadie pide.
      -- Las líneas de venta viven dentro del documento, no en una tabla
      -- aparte: `sales_invoices.items` es un arreglo JSON. Asumir una tabla
      -- de líneas hacía fallar la función entera.
      coalesce((
        select sum(greatest(coalesce((line ->> 'quantity')::numeric, 0), 0))
        from public.sales_invoices invoice
        cross join lateral jsonb_array_elements(invoice.items) line
        where invoice.tenant_id = product.tenant_id
          and jsonb_typeof(invoice.items) = 'array'
          and nullif(line ->> 'product_id', '')::uuid = product.id
          and invoice.date >= now() - interval '90 days'
      ), 0) sold_recently
    from public.products product
    where product.tenant_id = v_tenant_id
      and product.supplier_id = p_supplier_id
      and product.is_active is true
      and nullif(btrim(coalesce(product.supplier_code, '')), '') is not null
  ), ranked as (
    select candidates.*,
      row_number() over (
        order by (case when available <= 0 then 0 else 1 end),
          sold_recently desc, available, name
      ) rank
    from candidates
    where available <= greatest(minimum, 0)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'productId', id,
      'name', name,
      'supplierCode', supplier_code,
      'available', available,
      'minimumStock', minimum,
      'soldRecently', sold_recently
    ) order by rank) filter (where rank <= p_limit), '[]'::jsonb)
  into v_items
  from ranked;

  return jsonb_build_object(
    'asOf', clock_timestamp(),
    'supplierId', p_supplier_id,
    'items', v_items,
    'resultCount', jsonb_array_length(v_items)
  );
end;
$$;

revoke all on function public.supplier_availability_targets_v1(uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.supplier_availability_targets_v1(uuid, integer)
  to authenticated;

commit;
