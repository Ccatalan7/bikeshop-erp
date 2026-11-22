-- 20261121230000: marcas en el menú. Falla si la lectura común de la tienda
-- no trae `brands`, si la visita perdió el permiso de leerla, o si el resto
-- de la lectura cambió (menú, páginas, categorías y tarifas siguen ahí).
-- SQL plano, sin control de transacción: corre por el envoltorio de lectura.

select 1 / case
  when position(
         '''brands''' in pg_get_functiondef(
           'public.get_public_storefront_shell_v1(uuid)'::regprocedure))
       > 0
   and has_function_privilege(
         'anon', 'public.get_public_storefront_shell_v1(uuid)', 'EXECUTE')
  then 1 else 0 end as shell_names_brands;

-- La tienda de Viñabike: la lectura sigue entera y `brands` es una lista.
select 1 / case
  when shell ? 'settings' and shell ? 'navigation' and shell ? 'pages'
   and shell ? 'categories' and shell ? 'shipping_tiers'
   and jsonb_typeof(shell -> 'brands') = 'array'
   and jsonb_array_length(shell -> 'navigation') > 0
  then 1 else 0 end as shell_whole_with_brands
  from (select public.get_public_storefront_shell_v1(
          '5443b130-cc28-45af-a420-cd500b288890'::uuid) as shell) read;

-- Cada marca que trae es una que nombra un ítem visible de marca.
select 1 / case
  when not exists (
    select 1
      from jsonb_array_elements(public.get_public_storefront_shell_v1(
             '5443b130-cc28-45af-a420-cd500b288890'::uuid) -> 'brands') brand
     where not exists (
       select 1 from public.website_navigation nav
        where nav.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
          and nav.is_visible and nav.link_type = 'brand'
          and lower(btrim(nav.link_value)) = brand ->> 'id'))
  then 1 else 0 end as brands_only_from_menu;
