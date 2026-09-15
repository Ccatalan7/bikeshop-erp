-- La rama se deduce de la descripción; no se le exige al modelo.
--
-- «Cámaras 29 Schrader» se guardaba con `category_id` NULO, y de ahí colgaba
-- todo lo que después fallaba en cascada:
--
--   · «Stock interno» vacío (sin conjunto que revisar)
--   · «Falta decir qué categoría es» en Proveedores
--   · «No se pudo fijar el producto de la necesidad» al elegir uno de bodega,
--     porque `confirm_supply_need_family_choice_v1` exige un conjunto elegible
--     y sin categoría no hay ninguno.
--
-- El dueño lo dijo en una línea: «claramente la categoría es cámara». La ranura
-- existe desde el kernel y esperaba que el modelo trajera una referencia de
-- categoría resuelta. No la trae —y no tiene por qué: es un dato del catálogo,
-- no una decisión del operador—.
--
-- Se deduce de los productos a los que la descripción resuelve, con el mismo
-- resolvedor que usa el ranking, y sólo cuando hay una rama claramente
-- dominante. Si el conjunto está repartido entre varias, se conserva el nulo:
-- inventar una rama es peor que no tenerla, porque el conjunto elegible saldría
-- del lugar equivocado.

begin;

create or replace function public.supply_need_category_for_phrase_internal_v1(
  p_tenant_id uuid,
  p_phrase text
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
  with resolved as (
    select product.category_id
    from public.purchase_query_products_internal_v1(
      p_tenant_id, p_phrase, false
    ) match
    join public.products product on product.id = match.product_id
    where product.category_id is not null
  ), tally as (
    select category_id, count(*) as hits, sum(count(*)) over () as total
    from resolved
    group by category_id
  )
  select category_id
  from tally
  -- Dominante de verdad: al menos dos productos y el 60% del conjunto. Con la
  -- rama repartida se devuelve nulo y la necesidad queda como estaba.
  where hits >= 2 and hits::numeric / nullif(total, 0) >= 0.6
  order by hits desc
  limit 1
$$;

revoke all on function public.supply_need_category_for_phrase_internal_v1(
  uuid, text
) from public, anon, authenticated, service_role;

commit;
