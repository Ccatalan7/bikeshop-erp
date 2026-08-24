-- La ficha publica qué tuvo que soltar la búsqueda para poder contestar.
select set_config(
  'request.jwt.claim.sub',
  (select up.user_id::text from public.user_profiles up
    where up.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and up.user_id is not null and up.role in ('owner','admin','manager')
    order by case up.role when 'owner' then 1 when 'admin' then 2 else 3 end,
             up.created_at asc nulls last limit 1),
  true) as actor;
select set_config('request.jwt.claim.role', 'authenticated', true) as rol;

select
  (page->>'matched')::int coinciden,
  (page->>'droppedWords') solto_palabras,
  (page->>'droppedFilters') solto_medidas,
  (page->'items'->0->>'name') primero,
  (page->'items'->0->>'imageUrl') is not null primero_con_foto
from (
  select public.supplier_catalog_page_v1(
    (select s.id from public.suppliers s
      where s.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
        and s.name = 'RBX' limit 1),
    null, 40, 0, 'Cámaras 29 con válvula Schrader') page
) probe;
