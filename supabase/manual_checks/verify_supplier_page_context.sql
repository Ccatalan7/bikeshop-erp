-- Con la necesidad puesta, lo que coincide encabeza la lista y trae su foto.
select set_config(
  'request.jwt.claim.sub',
  (select up.user_id::text from public.user_profiles up
    where up.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and up.user_id is not null and up.role in ('owner','admin','manager')
    order by case up.role when 'owner' then 1 when 'admin' then 2 else 3 end,
             up.created_at asc nulls last limit 1),
  true) as actor;
select set_config('request.jwt.claim.role', 'authenticated', true) as rol;

with proveedor as (
  select s.id from public.suppliers s
  where s.tenant_id = '5443b130-cc28-45af-a420-cd500b288890' and s.name = 'RBX'
  limit 1
), sin_contexto as (
  select public.supplier_catalog_page_v1((select id from proveedor)) page
), con_contexto as (
  select public.supplier_catalog_page_v1(
    (select id from proveedor), null, 40, 0,
    'Cámaras 29 con válvula Schrader') page
)
select
  (select (page->'items'->0->>'name') from sin_contexto) primero_sin_contexto,
  (select (page->'items'->0->>'name') from con_contexto) primero_con_contexto,
  (select (page->'items'->0->>'matchesNeed')::boolean from con_contexto)
    el_primero_coincide,
  (select (page->>'matched')::int from con_contexto) cuantos_coinciden,
  (select count(*) from con_contexto,
    jsonb_array_elements(page->'items') item
    where item->>'imageUrl' is not null) filas_con_foto,
  (select (page->>'returned')::int from con_contexto) filas_devueltas;
