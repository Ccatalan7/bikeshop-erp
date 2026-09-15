-- Lo confirmado tiene que llegar a la pantalla, o no sirve de nada.
--
-- El chequeo escribe en `supplier_availability_checks` y hasta acá nadie lo
-- lee. Esta lectura devuelve, por proveedor, lo ÚLTIMO que dijo su portal sobre
-- los productos que el operador está mirando.
--
-- **El historial y lo confirmado conviven, nunca se pisan.** El historial dice
-- a quién le compramos esto; el chequeo dice qué contestó hoy su portal. Son
-- dos preguntas distintas y la interfaz las muestra como dos cosas distintas.
--
-- Se devuelve SIEMPRE el último chequeo, incluso si fue `session_expired` o
-- `unreadable`: saber que el último intento no concluyó es información, y
-- esconderlo haría que la pantalla parezca no tener datos cuando lo que pasa es
-- que la consulta falló.

begin;

create or replace function public.supplier_last_availability_v1(
  p_supplier_id uuid,
  p_limit integer default 8
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_items jsonb;
  v_summary jsonb;
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
      -- Lo que cambió desde la última compra. Es la razón por la que un
      -- operador miraría esta pantalla: un 18% arriba cambia a quién le pide.
      case
        when product.cost is null or product.cost <= 0 then null
        when latest.price_net is null then null
        else round(100 * (latest.price_net - product.cost) / product.cost, 1)
      end drift_percent,
      row_number() over (order by latest.checked_at desc) rank
    from latest
    join public.products product on product.id = latest.product_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'productId', product_id,
      'name', name,
      'supplierCode', supplier_code,
      'status', status,
      'priceNet', price_net,
      'stockQuantity', stock_quantity,
      'ourCost', our_cost,
      'driftPercent', drift_percent,
      'checkedAt', checked_at,
      'ageMinutes',
        (extract(epoch from (statement_timestamp() - checked_at)) / 60)::integer
    ) order by rank) filter (where rank <= p_limit), '[]'::jsonb),
    jsonb_build_object(
      'checked', count(*),
      'available', count(*) filter (where status = 'available'),
      'outOfStock', count(*) filter (where status = 'out_of_stock'),
      'notFound', count(*) filter (where status = 'not_found'),
      -- Se cuentan aparte a propósito: una corrida con sesión caída no es una
      -- corrida con resultados, y sumarlas juntas lo escondería.
      'inconclusive', count(*) filter (
        where status in ('session_expired', 'unreadable')
      ),
      'lastCheckedAt', max(checked_at)
    )
  into v_items, v_summary
  from joined;

  return jsonb_build_object(
    'asOf', clock_timestamp(),
    'supplierId', p_supplier_id,
    'items', v_items,
    'summary', coalesce(v_summary, '{}'::jsonb)
  );
end;
$$;

revoke all on function public.supplier_last_availability_v1(uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.supplier_last_availability_v1(uuid, integer)
  to authenticated;

commit;
