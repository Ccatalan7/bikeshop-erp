-- La ficha del proveedor devuelve cabecera, métricas y catálogo paginado,
-- distinguiendo lo comprado de lo sólo catalogado.
--
-- La función es `security definer` sobre `user_tenant_id()`: sin un JWT en la
-- sesión responde «No tenant context», que es correcto y no dice nada sobre la
-- función. Se fija un actor real del tenant con `set_config` suelto — el
-- corredor de lecturas rechaza un bloque `do $$ ... $$` porque su `begin`/`end`
-- le parece manejo de transacción.
select set_config(
  'request.jwt.claim.sub',
  (select up.user_id::text
     from public.user_profiles up
    where up.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and up.user_id is not null
      and up.role in ('owner', 'admin', 'manager')
    order by case up.role
               when 'owner' then 1
               when 'admin' then 2
               when 'manager' then 3
               else 99
             end,
             up.created_at asc nulls last
    limit 1),
  true
) as actor_fijado;

select set_config('request.jwt.claim.role', 'authenticated', true) as rol_fijado;

select
  (page->'supplier'->>'name') proveedor,
  (page->'metrics'->>'purchaseLines')::int lineas,
  (page->'metrics'->>'purchaseInvoices')::int facturas,
  (page->>'total')::int total_productos,
  (page->>'returned')::int devueltos,
  (select count(*) from jsonb_array_elements(page->'items') item
    where item->>'origin' = 'comprado') comprados,
  (select count(*) from jsonb_array_elements(page->'items') item
    where item->>'origin' = 'catalogado') catalogados
from (
  select public.supplier_catalog_page_v1(
    (select observation.supplier_id
       from public.purchase_line_landed_cost_observations_v1 observation
      where observation.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
        and observation.supplier_id is not null
      group by observation.supplier_id
      order by count(*) desc
      limit 1),
    null, 40, 0
  ) page
) probe;
