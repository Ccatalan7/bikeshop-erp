-- Corrección de la prioridad de compra: el nombre del producto no vive en
-- `supply_needs`.
--
-- La versión 20260817122000 llegó a producción con `need.product_name` en la
-- rama de taller. Esa columna no existe: `supply_needs` guarda la descripción
-- del operador y el nombre del catálogo vive en `products`. La función quedó
-- instalada pero reventaba al ejecutarse, y el módulo lo absorbió sin romperse
-- —el panel de prioridad simplemente no aparecía—.
--
-- Por qué no lo atrapó la verificación: el read-back sólo grepeaba el TEXTO de
-- la función. Un `create function` acepta una consulta que no resuelve hasta
-- que se ejecuta, así que verificar la definición no verifica nada. El
-- read-back de esta versión ejecuta la función con un tenant real y exige la
-- forma de la respuesta.
--
-- Las migraciones son inmutables: esto es una versión nueva, no una edición.
--
-- Segunda corrección de la misma raíz: la columna es `original_description`,
-- no `description`. Escribí la rama de taller desde el modelo Dart —que sí
-- expone `description`— en vez de leer la tabla. El modelo nombra distinto que
-- el esquema, y sólo la ejecución lo revela.

begin;


create or replace function public.purchase_priority_feed_v1(
  p_limit integer default 40,
  p_rotation_days integer default 120
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
  v_total integer;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if p_limit not between 1 and 200
     or p_rotation_days not between 7 and 730 then
    raise exception 'Invalid priority feed arguments' using errcode = '22023';
  end if;

  with rotation as (
    -- Rotación real: lo que salió por venta. No se infiere de un nombre ni de
    -- que exista una ficha.
    select
      movement.product_id,
      count(*)::integer as sale_count,
      sum(abs(movement.quantity))::numeric as sold_units,
      max(movement.created_at) as last_sold_at
    from public.stock_movements movement
    where movement.tenant_id = v_tenant_id
      and movement.movement_type in ('sale', 'sales_invoice')
      and movement.created_at > now() - make_interval(days => p_rotation_days)
      and movement.product_id is not null
    group by 1
  ), already_needed as (
    -- Lo que ya está en una necesidad abierta no se propone de nuevo: la
    -- persona ya lo tomó.
    select distinct need.product_id
    from public.supply_needs need
    where need.tenant_id = v_tenant_id
      and need.supply_state = 'open'
      and need.product_id is not null
  ), workshop as (
    -- 1. Un trabajo esperando un repuesto. Tiene cliente y fecha: va primero.
    select
      'workshop'::text as source,
      need.id as entity_id,
      need.product_id,
      -- `supply_needs` guarda la descripción del operador; el nombre del
      -- catálogo vive en `products` y sólo existe si la identidad se confirmó.
      coalesce(product.name, need.original_description) as title,
      need.quantity as suggested_quantity,
      need.unit,
      1 as urgency_rank,
      'Un trabajo de taller lo está esperando' as reason,
      need.created_at as signal_at
    from public.supply_needs need
    left join public.products product
      on product.tenant_id = need.tenant_id
     and product.id = need.product_id
    where need.tenant_id = v_tenant_id
      and need.supply_state = 'open'
      and need.origin_kind = 'mechanic_job'
  ), stockout as (
    -- 2. Se agotó algo que se vende. El quiebre sin rotación no es urgente.
    select
      'stockout'::text as source,
      product.id as entity_id,
      product.id as product_id,
      product.name as title,
      greatest(
        coalesce(product.min_stock_level, 0),
        ceil(rotation.sold_units / greatest(p_rotation_days, 1)::numeric * 30)
      ) as suggested_quantity,
      'unit'::text as unit,
      2 as urgency_rank,
      'Se agotó y se vendió ' || rotation.sale_count || ' ' ||
        case when rotation.sale_count = 1 then 'vez' else 'veces' end ||
        ' en los últimos ' || p_rotation_days || ' días' as reason,
      rotation.last_sold_at as signal_at
    from public.products product
    join rotation on rotation.product_id = product.id
    where product.tenant_id = v_tenant_id
      and product.is_active
      and product.track_stock
      and coalesce(product.stock_quantity, 0) <= 0
      and product.id not in (select product_id from already_needed)
  ), below_minimum as (
    -- 3. Bajo el mínimo, con rotación. Todavía queda algo: aprieta menos.
    select
      'below_minimum'::text as source,
      product.id as entity_id,
      product.id as product_id,
      product.name as title,
      greatest(
        coalesce(product.min_stock_level, 0) - coalesce(product.stock_quantity, 0),
        1
      ) as suggested_quantity,
      'unit'::text as unit,
      3 as urgency_rank,
      'Quedan ' || coalesce(product.stock_quantity, 0)::text ||
        ' y el mínimo es ' || coalesce(product.min_stock_level, 0)::text as reason,
      rotation.last_sold_at as signal_at
    from public.products product
    join rotation on rotation.product_id = product.id
    where product.tenant_id = v_tenant_id
      and product.is_active
      and product.track_stock
      and coalesce(product.min_stock_level, 0) > 0
      and coalesce(product.stock_quantity, 0) > 0
      and coalesce(product.stock_quantity, 0) <= product.min_stock_level
      and product.id not in (select product_id from already_needed)
  ), unioned as (
    select * from workshop
    union all select * from stockout
    union all select * from below_minimum
  ), numbered as (
    select
      unioned.*,
      row_number() over (
        order by urgency_rank, signal_at desc nulls last, title
      )::integer as rank,
      count(*) over()::integer as matched_count
    from unioned
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank,
      'source', source,
      'entityId', entity_id,
      'productId', product_id,
      'title', title,
      'suggestedQuantity', suggested_quantity,
      'unit', unit,
      'reason', reason,
      'signalAt', signal_at
    ) order by rank) filter (where rank <= p_limit), '[]'::jsonb),
    coalesce(max(matched_count), 0)
  into v_items, v_total
  from numbered;

  return jsonb_build_object(
    'asOf', clock_timestamp(),
    'status', case when v_total = 0 then 'verifiedEmpty' else 'success' end,
    'items', v_items,
    'resultCount', jsonb_array_length(v_items),
    'hasMore', v_total > p_limit,
    'rotationDays', p_rotation_days
  );
end;
$$;

revoke all on function public.purchase_priority_feed_v1(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.purchase_priority_feed_v1(integer, integer)
  to authenticated;

comment on function public.purchase_priority_feed_v1(integer, integer) is
  'Prioridad de compra levantada por el sistema: taller esperando repuesto, quiebre de lo que rota y bajo mínimo de lo que rota. Cada fila trae su razón en palabras. No propone lo que ya está en una necesidad abierta.';

commit;
