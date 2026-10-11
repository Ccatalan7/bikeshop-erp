-- Read-back de 20261011010000: la lista del catálogo sugiere la marca del
-- nombre, y los comandos para usarla y deshacerla existen sólo para quien
-- inicia sesión.

select 1 / case
  when pg_get_function_result('public.catalog_web_items_v1(uuid)'::regprocedure)
       ~ 'suggested_brand_id uuid, suggested_brand text, updated_at'
   and pg_get_functiondef('public.catalog_web_items_v1(uuid)'::regprocedure)
       ~ $re$then 'brand_in_name'$re$
   and pg_get_functiondef('public.catalog_dismiss_issue_v1(uuid,uuid,text,boolean)'::regprocedure)
       ~ $re$'brand_in_name'$re$
  then 1 else 0
end as assert_catalog_suggests_brand_from_name;

select 1 / case
  when not public.catalog_is_public_brand_v1('Andes Industrial')
   and not public.catalog_is_public_brand_v1('Genérico')
   and public.catalog_is_public_brand_v1('Shimano')
  then 1 else 0
end as assert_public_brand_list;

select 1 / case
  when not has_function_privilege('anon', 'public.catalog_web_items_v1(uuid)', 'execute')
   and not has_function_privilege('anon', 'public.catalog_apply_brand_from_name_v1(uuid,uuid[])', 'execute')
   and not has_function_privilege('anon', 'public.catalog_restore_brands_v1(uuid,jsonb)', 'execute')
   and has_function_privilege('authenticated', 'public.catalog_web_items_v1(uuid)', 'execute')
   and has_function_privilege('authenticated', 'public.catalog_apply_brand_from_name_v1(uuid,uuid[])', 'execute')
   and has_function_privilege('authenticated', 'public.catalog_restore_brands_v1(uuid,jsonb)', 'execute')
  then 1 else 0
end as assert_brand_commands_grants;

-- Con los datos del 2026-10-11 sugiere las dos llantas Vision.
select 1 / case
  when (select count(*)
          from public.products p
         where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
           and p.sku in ('19187', '19190')
           and public.catalog_brand_from_name_v1(p.tenant_id,
                 coalesce(nullif(btrim(p.website_name), ''), p.name) || ' ' || coalesce(p.name, ''))
               = (select b.id from public.product_brands b where b.name = 'Vision')) = 2
    or (select count(*)
          from public.products p
          join public.product_brands b on b.id = p.brand_id
         where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
           and p.sku in ('19187', '19190')
           and b.name = 'Vision') = 2
  then 1 else 0
end as assert_vision_rims_found;
