-- 20261024020000: a tyre's page offers the tubes that fit it. Fails without
-- the function, or when the 700 x 23C road tyre (SKU 19167) gets no tubes
-- or a tube that is not 700c.
select 1 / case
  when to_regprocedure('public.get_public_product_fits_v1(uuid,uuid,integer)') is not null
  then 1 else 0 end as fits_function_exists;

with page as (
  select public.get_public_product_page_v2(
           '5443b130-cc28-45af-a420-cd500b288890', '19167') as body
), items as (
  select item.value->>'name' as name
    from page,
         jsonb_array_elements(coalesce(page.body->'fits'->'items', '[]'::jsonb))
           as item(value)
)
select 1 / case
  when (select body->'fits'->>'kind' from page) = 'tubes'
   and exists (select 1 from items)
   and not exists (select 1 from items where name not ilike '%700%')
  then 1 else 0 end as road_tyre_gets_700c_tubes;
