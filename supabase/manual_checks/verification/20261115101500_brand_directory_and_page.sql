-- Read-back de 20261115101500_brand_directory_and_page.
-- Sólo `select` planos (corre en lectura remota): cada uno revienta si falta
-- la definición o si el invariante no se cumple. Las funciones exigen un
-- miembro activo del taller, así que su contenido se lee aparte, con la
-- lectura de la lista de Marcas.

-- 1. Las dos lecturas existen.
select 1 / (
  to_regprocedure('public.brand_directory_v1(uuid)') is not null
  and to_regprocedure('public.brand_page_v1(uuid,uuid)') is not null
)::int as lecturas_de_marcas_existen;

-- 2. Corren como su dueño, con la ruta de búsqueda fija.
select 1 / (count(*) = 2)::int as definer_con_ruta_fija
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('brand_directory_v1', 'brand_page_v1')
   and p.prosecdef
   and array_to_string(p.proconfig, ',')
       like '%search_path=pg_catalog, public, pg_temp%';

-- 3. Las llama la app con su sesión; nunca alguien sin sesión.
select 1 / (
  has_function_privilege('authenticated',
    'public.brand_directory_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.brand_page_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.brand_directory_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.brand_page_v1(uuid,uuid)', 'EXECUTE')
)::int as solo_con_sesion;
