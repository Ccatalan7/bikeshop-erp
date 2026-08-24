-- La bodega contesta una descripción, no sólo un SKU.
--
-- El módulo promete «revisa primero la bodega y, si falta, encuentra dónde
-- comprarlo». Medido en la app real con «Cámaras 29 Schrader»:
--
--   get_supply_need_inventory_snapshot_v1 → identity_unresolved, components []
--
-- …teniendo el taller SIETE unidades de «CAMARA 29 X 1.75/2.35 V/AMERICANA
-- 48mm» —americana es Schrader— más una KENDA y una MAXXIS de 29. El paso
-- «Stock interno» mostraba nada y el operador habría comprado lo que ya tenía.
--
-- La causa está antes: la necesidad se guarda sin `category_id` porque el
-- modelo nunca resolvió una referencia de categoría, y todo lo que cuelga de la
-- categoría —bodega, conjunto elegible, comparación— se queda sin conjunto.
--
-- Esta lectura no espera esa categoría: resuelve la DESCRIPCIÓN con el mismo
-- `purchase_query_products_internal_v1` que usa el ranking, sobre el catálogo
-- completo y no sólo lo comprado, y devuelve lo que hay con su stock. No asigna
-- ni reserva nada: confirmar el producto sigue siendo una decisión del
-- operador, y es lo que después habilita el flujo exacto.

begin;

create or replace function public.supply_need_stock_candidates_v1(
  p_need_id uuid,
  p_limit integer default 8
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
  v_need record;
  v_items jsonb;
  v_total integer := 0;
  v_dropped_words text;
  v_dropped_filters text;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if p_limit not between 1 and 20 then
    raise exception 'Invalid stock candidate arguments' using errcode = '22023';
  end if;

  select need.id, need.original_description, need.product_id
  into v_need
  from public.supply_needs need
  where need.id = p_need_id and need.tenant_id = v_tenant_id;

  if v_need.id is null then
    raise exception 'Supply need not found' using errcode = 'P0002';
  end if;

  -- Con producto confirmado esta lectura no aplica: la bodega exacta ya la
  -- publica `get_supply_need_inventory_snapshot_v1`, que es su dueña. Dos
  -- verdades sobre el mismo stock es peor que una sola incompleta.
  if v_need.product_id is not null then
    return jsonb_build_object(
      'asOf', clock_timestamp(),
      'items', '[]'::jsonb,
      'resultCount', 0,
      'totalMatches', 0,
      'reason', 'identity_confirmed'
    );
  end if;

  with resolved as materialized (
    select * from public.purchase_query_products_internal_v1(
      v_tenant_id, v_need.original_description, false
    )
  ), stock as (
    select product.id,
      product.name,
      product.sku,
      product.brand,
      product.category_name,
      product.price,
      product.cost,
      coalesce(product.track_stock, false) tracks_inventory,
      public.inventory_available_quantity_v1(product.tenant_id, product.id)
        available,
      max(resolved.dropped_words) over () dropped_words,
      max(resolved.dropped_filters) over () dropped_filters,
      count(*) over ()::integer matched
    from public.products product
    join resolved on resolved.product_id = product.id
    where product.tenant_id = v_tenant_id
      and product.is_active is true
  ), ranked as (
    select stock.*,
      row_number() over (
        -- Lo que hay primero: un producto que calza y está en cero no le
        -- resuelve el día a nadie, pero saber que existe sí evita crearlo
        -- de nuevo.
        order by (case when available > 0 then 0 else 1 end), available desc,
          name
      )::integer rank
    from stock
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'productId', id,
      'name', name,
      'sku', sku,
      'brand', brand,
      'category', category_name,
      'available', available,
      'tracksInventory', tracks_inventory,
      'priceGross', price,
      'costNet', cost
    ) order by rank) filter (where rank <= p_limit), '[]'::jsonb),
    coalesce(max(matched), 0),
    max(dropped_words),
    max(dropped_filters)
  into v_items, v_total, v_dropped_words, v_dropped_filters
  from ranked;

  return jsonb_build_object(
    'asOf', clock_timestamp(),
    'items', v_items,
    'resultCount', jsonb_array_length(v_items),
    'totalMatches', v_total,
    'hasMore', v_total > p_limit,
    'droppedWords', v_dropped_words,
    'droppedFilters', v_dropped_filters,
    'reason', case when v_total = 0 then 'no_match' else 'candidates' end
  );
end;
$$;

revoke all on function public.supply_need_stock_candidates_v1(uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.supply_need_stock_candidates_v1(uuid, integer)
  to authenticated;

commit;
