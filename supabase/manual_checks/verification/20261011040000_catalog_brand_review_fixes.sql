-- Read-back de 20261011040000: deshacer valida la marca y compara enlace y
-- texto, el comando pide lo mismo que la lista, el «para» se mira sin
-- puntuación, sólo marcas en uso, sin acentos, y destacados toma los nuevos.

select 1 / case
  when pg_get_functiondef('public.catalog_restore_brands_v1(uuid,jsonb)'::regprocedure)
       ~ $re$p\.brand is not distinct from \(entry ->> 'brand'\)$re$
   and pg_get_functiondef('public.catalog_restore_brands_v1(uuid,jsonb)'::regprocedure)
       ~ 'previous\.tenant_id is null or previous\.tenant_id = p_tenant_id'
   and pg_get_functiondef('public.catalog_apply_brand_from_name_v1(uuid,uuid[])'::regprocedure)
       ~ 'catalog_product_web_block_v1\(p, public\.catalog_web_policy_v1\(p_tenant_id\)\) is null'
   and pg_get_functiondef('public.catalog_replace_featured_v1(uuid,uuid[])'::regprocedure)
       ~ 'for share of p'
   and pg_get_functiondef('public.catalog_brand_words_v1(uuid)'::regprocedure)
       ~ 'used\.brand_id = b\.id'
  then 1 else 0
end as assert_review_fixes_in_place;

select 1 / case
  when public.catalog_brand_text_v1('Piñón Öhlins, compatible con: Shimano') = ' pinon ohlins compatible con shimano '
   and public.catalog_brand_from_name_v1('5443b130-cc28-45af-a420-cd500b288890', 'Adaptador compatible con: Shimano') is null
   and public.catalog_brand_from_name_v1('5443b130-cc28-45af-a420-cd500b288890', 'Llanta Vision aro 26 doble pared')
       = (select b.id from public.product_brands b where b.name = 'Vision')
  then 1 else 0
end as assert_rule_reads_words;
