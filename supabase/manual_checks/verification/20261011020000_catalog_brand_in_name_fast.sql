-- Read-back de 20261011020000: la lista del catálogo normaliza las marcas
-- una vez y la regla encuentra lo mismo que antes.

select 1 / case
  when pg_get_functiondef('public.catalog_web_items_v1(uuid)'::regprocedure)
       ~ 'brand_words as materialized'
   and pg_get_functiondef('public.catalog_web_items_v1(uuid)'::regprocedure)
       ~ 'catalog_brand_from_words_v1\('
   and pg_get_function_result('public.catalog_web_items_v1(uuid)'::regprocedure)
       ~ 'suggested_brand_id uuid, suggested_brand text, updated_at'
  then 1 else 0
end as assert_catalog_reads_brand_words_once;

select 1 / case
  when public.catalog_brand_from_name_v1(
         '5443b130-cc28-45af-a420-cd500b288890', 'Oliva y pin para manguera Shimano BH59') is null
   and public.catalog_brand_from_name_v1(
         '5443b130-cc28-45af-a420-cd500b288890', 'Llanta aro 29 doble pared negra') is null
   and public.catalog_brand_from_name_v1(
         '5443b130-cc28-45af-a420-cd500b288890', 'Llanta Vision aro 26 doble pared')
       = (select b.id from public.product_brands b where b.name = 'Vision')
  then 1 else 0
end as assert_same_rule;

select 1 / case
  when not has_function_privilege('anon', 'public.catalog_brand_from_words_v1(text,uuid[],text[])', 'execute')
   and not has_function_privilege('anon', 'public.catalog_brand_words_v1(uuid)', 'execute')
  then 1 else 0
end as assert_brand_helpers_closed_to_anon;
