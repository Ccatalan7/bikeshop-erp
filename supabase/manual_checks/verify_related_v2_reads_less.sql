-- 20261121030000: get_public_related_v2 reads only the page's product and
-- what could be shown, with the same result. Fails before the change (its
-- definition has no such filter) or when the Leatt 3DF knee pad stops
-- showing the AirFlex first, then gloves and helmets.
select position('20261121030000' in pg_get_functiondef(
         'public.get_public_related_v2(uuid,uuid,integer)'::regprocedure)) > 0 as reads_less;

select 1 / case
  when position('20261121030000' in pg_get_functiondef(
         'public.get_public_related_v2(uuid,uuid,integer)'::regprocedure)) > 0
  then 1 else 0 end as reads_less_deployed;

select related.place, related.kind, product.name
  from public.get_public_related_v2(
         '5443b130-cc28-45af-a420-cd500b288890',
         '8976e819-1c52-5465-ba31-90fd99904161') related
  join public.products product on product.id = related.product_id
 order by related.place;

with related as (
  select related.place, product.name
    from public.get_public_related_v2(
           '5443b130-cc28-45af-a420-cd500b288890',
           '8976e819-1c52-5465-ba31-90fd99904161') related
    join public.products product on product.id = related.product_id
)
select 1 / case
  when (select name from related where place = 1) ilike 'Rodillera Leatt AirFlex%'
   and exists (select 1 from related where name ilike 'Guante%')
   and exists (select 1 from related where name ilike 'Casco%')
   and not exists (select 1 from related where name ilike '%mochila%')
  then 1 else 0 end as knee_pad_related_unchanged;
