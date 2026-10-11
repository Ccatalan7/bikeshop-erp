-- Read-back de 20261011030000: la sugerencia lee el nombre que se ve, enlaza
-- la marca escrita a mano y no pisa una que diga otra.

select 1 / case
  when pg_get_functiondef('public.catalog_web_items_v1(uuid)'::regprocedure)
       ~ 'catalog_brand_agrees_v1\(sg\.brand, sg\.named_brand\)'
   and pg_get_functiondef('public.catalog_web_items_v1(uuid)'::regprocedure)
       !~ $re$coalesce\(nullif\(btrim\(st\.website_name\), ''\), st\.name\) \|\| ' '$re$
   and pg_get_functiondef('public.catalog_apply_brand_from_name_v1(uuid,uuid[])'::regprocedure)
       ~ 'catalog_brand_agrees_v1\(target\.written_brand, target\.suggestion\)'
  then 1 else 0
end as assert_brand_rule_reads_the_shown_name;

select 1 / case
  when public.catalog_brand_agrees_v1(null, (select id from public.product_brands where name = 'Shimano'))
   and public.catalog_brand_agrees_v1('Andes Industrial', (select id from public.product_brands where name = 'Shimano'))
   and public.catalog_brand_agrees_v1('shimano', (select id from public.product_brands where name = 'Shimano'))
   and not public.catalog_brand_agrees_v1('SRAM', (select id from public.product_brands where name = 'Shimano'))
  then 1 else 0
end as assert_written_brand_is_respected;

select 1 / case
  when not has_function_privilege('anon', 'public.catalog_brand_agrees_v1(text,uuid)', 'execute')
  then 1 else 0
end as assert_agrees_closed_to_anon;
