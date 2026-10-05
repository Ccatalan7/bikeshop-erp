-- Read-back of 20261005100000: the shared shell hands out each category's
-- description, image and order beside its name, still as security invoker
-- with a fixed search_path and callable by the public key; as anon it returns
-- Viñabike's categories with the three new keys and its settings.
-- Read-only; division by zero fails it.
set local role anon;

select jsonb_array_length(public.get_public_storefront_shell_v1(
         '5443b130-cc28-45af-a420-cd500b288890') -> 'categories') as categorias;

select 1/(case when
 (select not p.prosecdef
     and p.prosrc like '%pc.description, pc.image_url, pc.sort_order%'
    from pg_proc p
   where p.oid = to_regprocedure('public.get_public_storefront_shell_v1(uuid)'))
 and has_function_privilege('anon', 'public.get_public_storefront_shell_v1(uuid)', 'EXECUTE')
 and jsonb_array_length(public.get_public_storefront_shell_v1(
       '5443b130-cc28-45af-a420-cd500b288890') -> 'categories') > 0
 and not exists (
       select 1
         from jsonb_array_elements(public.get_public_storefront_shell_v1(
           '5443b130-cc28-45af-a420-cd500b288890') -> 'categories') category
        where not (category ? 'description' and category ? 'image_url'
                   and category ? 'sort_order' and category ? 'show_on_website'))
 and public.get_public_storefront_shell_v1('5443b130-cc28-45af-a420-cd500b288890')
       #>> '{settings,store_url}' is not null
then 1 else 0 end) as categorias_con_descripcion_imagen_y_orden;
