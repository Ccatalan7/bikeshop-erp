-- 20261024010000: the product page ranks its related products by the spec
-- values they share. Fails without the function or when a 700 x 23C road
-- tyre (SKU 19167) is not followed by 700c tyres, or still lists a 20-inch one.
select 1 / case
  when to_regprocedure('public.get_public_related_fit_v1(uuid,uuid,uuid[])') is not null
  then 1 else 0 end as fit_function_exists;

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
