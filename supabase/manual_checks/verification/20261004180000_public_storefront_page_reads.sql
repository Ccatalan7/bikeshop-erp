-- Read-back of 20261004180000: the HTML storefront reads a product page and
-- the shared shell in one call each. Both functions are security invoker with
-- a fixed search_path, the public key can call them, and as anon they return
-- the real H911 page (with its website fields and sheet, without cost) and
-- Viñabike's menus, pages and categories, while an unknown SKU has no page.
-- Read-only; division by zero fails it.
set local role anon;

select public.get_public_product_page_v1(
         '5443b130-cc28-45af-a420-cd500b288890', 'H911') #>> '{product,sku}' as ficha,
       jsonb_array_length(public.get_public_product_page_v1(
         '5443b130-cc28-45af-a420-cd500b288890', 'H911') -> 'specs') as filas_ficha_tecnica,
       jsonb_array_length(public.get_public_storefront_shell_v1(
         '5443b130-cc28-45af-a420-cd500b288890') -> 'navigation') as menus;

select 1/(case when
 (select not p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']
    from pg_proc p
   where p.oid = to_regprocedure('public.get_public_product_page_v1(uuid,text)'))
 and (select not p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']
    from pg_proc p
   where p.oid = to_regprocedure('public.get_public_storefront_shell_v1(uuid)'))
 and has_function_privilege('anon', 'public.get_public_product_page_v1(uuid,text)', 'EXECUTE')
 and has_function_privilege('anon', 'public.get_public_storefront_shell_v1(uuid)', 'EXECUTE')
 and public.get_public_product_page_v1('5443b130-cc28-45af-a420-cd500b288890', 'H911')
       #>> '{product,sku}' = 'H911'
 and not (public.get_public_product_page_v1('5443b130-cc28-45af-a420-cd500b288890', 'H911')
       -> 'product') ? 'cost'
 and (public.get_public_product_page_v1('5443b130-cc28-45af-a420-cd500b288890', 'H911')
       -> 'product') ? 'website_image_urls'
 and jsonb_array_length(public.get_public_product_page_v1(
       '5443b130-cc28-45af-a420-cd500b288890', 'H911') -> 'specs') > 0
 and public.get_public_product_page_v1('5443b130-cc28-45af-a420-cd500b288890',
       '__no_existe__') is null
 and jsonb_array_length(public.get_public_storefront_shell_v1(
       '5443b130-cc28-45af-a420-cd500b288890') -> 'navigation') > 0
 and jsonb_array_length(public.get_public_storefront_shell_v1(
       '5443b130-cc28-45af-a420-cd500b288890') -> 'categories') > 0
 and public.get_public_storefront_shell_v1('5443b130-cc28-45af-a420-cd500b288890')
       #>> '{settings,store_name}' is not null
then 1 else 0 end) as lectura_unica_de_la_ficha;
