-- Los dos costos llegan a la ficha y a la evidencia, y no son el mismo número.
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
  where s.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and s.name = 'Comercial Ciclo' limit 1
), ficha as (
  select public.supplier_catalog_page_v1(
    (select id from proveedor), null, 40, 0,
    'Cámaras 29 con válvula Schrader') page
), evidencia as (
  select public.purchase_supplier_evidence_v1(
    (select id from proveedor),
    jsonb_build_array('Cámaras 29 con válvula Schrader')) page
)
select
  (select count(*) from ficha, jsonb_array_elements(page->'items') item
    where item->>'lastBaseUnitCostNet' is not null) ficha_con_base,
  (select count(*) from ficha, jsonb_array_elements(page->'items') item
    where (item->>'lastLandedUnitCostNet')::numeric
        > (item->>'lastBaseUnitCostNet')::numeric) ficha_donde_difieren,
  (select count(*) from evidencia,
    jsonb_array_elements(page->'needs') need,
    jsonb_array_elements(need->'purchases') compra
    where compra->>'baseUnitCostNet' is not null) evidencia_con_base;
