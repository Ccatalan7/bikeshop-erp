-- 20261121020000: los relacionados por lo que es cada producto y por lo que
-- el local vende junto. Falla sin las funciones y las señales nuevas, o
-- cuando una ficha real vuelve a mostrar algo que no tiene que ver: la
-- rodillera Leatt 3DF con fundas de mochila (2026-11-21, el dueño), un
-- neumático 29 con otro aro, un cassette de 8 con una cadena de una
-- velocidad, o el neumático de ruta 700 x 23C sin 700c primero.

select to_regprocedure('public.get_public_related_v2(uuid,uuid,integer)') as related_v2,
       to_regprocedure('public.catalog_related_signals_refresh_v1(uuid)') as refresh_v1,
       to_regprocedure('public.catalog_related_signals_refresh_all_v1()') as refresh_all_v1;

select 1 / case
  when to_regprocedure('public.get_public_related_v2(uuid,uuid,integer)') is not null
   and to_regprocedure('public.catalog_related_signals_refresh_v1(uuid)') is not null
   and to_regprocedure('public.catalog_related_signals_refresh_all_v1()') is not null
  then 1 else 0 end as functions_exist;

-- Lo que se vende junto: ventas (cadena con cassette) y pares de taller
-- (rodillera con casco); lo que más se vende de cada producto.
select part, other_part, together, strength, lift, source, workshop
  from public.catalog_part_affinity
 where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and (part, other_part) in (('cadena', 'cassette'), ('rodillera', 'casco'), ('neumatico', 'camara'));

select 1 / case
  when exists (
         select 1 from public.catalog_part_affinity
          where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
            and part = 'cadena' and other_part = 'cassette'
            -- 43 boletas pagadas en 24 meses al 2026-11-21, seis veces el azar.
            and together >= 20 and lift >= 3)
   and exists (
         select 1 from public.catalog_part_affinity
          where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
            and part = 'rodillera' and other_part = 'casco' and workshop)
   and exists (
         select 1 from public.catalog_product_popularity
          where tenant_id = '5443b130-cc28-45af-a420-cd500b288890' and tickets > 0)
  then 1 else 0 end as signals_built;

-- El vocabulario: una rodillera es rodillera, no «protector».
select 1 / case
  when (select own_parts from public.catalog_search_documents
         where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
           and product_id = '8976e819-1c52-5465-ba31-90fd99904161') = array['rodillera']
  then 1 else 0 end as knee_pad_is_a_knee_pad;

-- La rodillera 3DF: primero la AirFlex, después guantes y cascos, y ninguna
-- funda de mochila.
with page as (
  select public.get_public_product_page_v2(
           p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
           p_product_id := '8976e819-1c52-5465-ba31-90fd99904161',
           p_group_models := true) as body
), related as (
  select item.value->>'name' as name, item.ordinality
    from page, jsonb_array_elements(page.body->'related') with ordinality as item(value, ordinality)
)
select ordinality, name from related order by ordinality;

with page as (
  select public.get_public_product_page_v2(
           p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
           p_product_id := '8976e819-1c52-5465-ba31-90fd99904161',
           p_group_models := true) as body
), related as (
  select item.value->>'name' as name, item.ordinality
    from page, jsonb_array_elements(page.body->'related') with ordinality as item(value, ordinality)
)
select 1 / case
  when (select name from related where ordinality = 1) ilike 'Rodillera Leatt AirFlex%'
   and exists (select 1 from related where name ilike 'Guante%')
   and exists (select 1 from related where name ilike 'Casco%')
   and not exists (select 1 from related where name ilike '%mochila%')
  then 1 else 0 end as knee_pad_related;

-- El neumático Maxxis 29 x 2.25: nada de otro aro (27.5, 26, 20, 700).
with page as (
  select public.get_public_product_page_v2(
           p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
           p_product_id := 'a9da66aa-694b-4c58-bfc7-c64bf0b3dd86',
           p_group_models := true) as body
), related as (
  select item.value->>'name' as name
    from page, jsonb_array_elements(page.body->'related') item
)
select 1 / case
  when exists (select 1 from related where name ~* 'c[aá]mara')
   and not exists (select 1 from related where name ~* '(27[.,]5|26 ?x|20 ?x|700 ?x)')
  then 1 else 0 end as tyre_29_related_fit;

-- El cassette Eclipse de 8: cadenas sí, ninguna de 1/8 (una velocidad).
with page as (
  select public.get_public_product_page_v2(
           p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
           p_product_id := '819fb98c-1f05-4ef8-8800-b8ca84fc6f28',
           p_group_models := true) as body
), related as (
  select item.value->>'name' as name
    from page, jsonb_array_elements(page.body->'related') item
)
select 1 / case
  when exists (select 1 from related where name ilike 'cadena%')
   and not exists (select 1 from related where name ilike '%1/8%')
  then 1 else 0 end as cassette_8_chains_fit;

-- 20261024010000, sigue en pie: el neumático de ruta 700 x 23C (SKU 19167)
-- con 700c primero y ningún aro 20.
with page as (
  select public.get_public_product_page_v2(
           '5443b130-cc28-45af-a420-cd500b288890', '19167') as body
), related as (
  select item.value->>'name' as name, item.ordinality
    from page,
         jsonb_array_elements(page.body->'related')
           with ordinality as item(value, ordinality)
)
select 1 / case
  when (select name from related where ordinality = 1) ilike '%700%'
   and not exists (select 1 from related where name ilike '% 20 x %')
  then 1 else 0 end as road_tyre_gets_700c_first;

-- Las señales se rehacen cada noche.
select 1 / case
  when exists (select 1 from cron.job where jobname = 'vinabike_catalog_related_signals')
  then 1 else 0 end as nightly_refresh_scheduled;
