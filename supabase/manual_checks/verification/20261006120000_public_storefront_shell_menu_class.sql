-- Read-back of 20261006120000: the shared shell hands out each menu item's
-- CSS class, still as security invoker with a fixed search_path and callable
-- by the public key; as anon Viñabike's «Componentes» comes with `megamenu`
-- and the categories keep their description, image and order.
-- Read-only; division by zero fails it.
set local role anon;

select item ->> 'label' as item, item ->> 'css_class' as clase
  from jsonb_array_elements(public.get_public_storefront_shell_v1(
         '5443b130-cc28-45af-a420-cd500b288890') -> 'navigation') item
 where item ->> 'parent_id' is null
   and item ->> 'menu_location' = 'header';

select 1/(case when
 (select not p.prosecdef
     and p.prosrc like '%nav.show_on_desktop, nav.show_on_mobile, nav.css_class%'
     and p.prosrc like '%pc.description, pc.image_url, pc.sort_order%'
    from pg_proc p
   where p.oid = to_regprocedure('public.get_public_storefront_shell_v1(uuid)'))
 and has_function_privilege('anon', 'public.get_public_storefront_shell_v1(uuid)', 'EXECUTE')
 and not exists (
       select 1
         from jsonb_array_elements(public.get_public_storefront_shell_v1(
           '5443b130-cc28-45af-a420-cd500b288890') -> 'navigation') item
        where not (item ? 'css_class'))
 and exists (
       select 1
         from jsonb_array_elements(public.get_public_storefront_shell_v1(
           '5443b130-cc28-45af-a420-cd500b288890') -> 'navigation') item
        where item ->> 'label' = 'Componentes'
          and item ->> 'css_class' = 'megamenu')
 and jsonb_array_length(public.get_public_storefront_shell_v1(
       '5443b130-cc28-45af-a420-cd500b288890') -> 'categories') > 0
then 1 else 0 end) as menu_con_clase;
