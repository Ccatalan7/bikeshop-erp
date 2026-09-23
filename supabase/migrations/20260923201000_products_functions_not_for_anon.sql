-- Dos búsquedas internas de productos dejan de estar abiertas a anónimo.
--
-- `search_products` y `match_products_semantic` corren con los permisos de
-- quien las llama (SECURITY INVOKER) y anónimo podía ejecutarlas.
-- `search_products` devuelve `p.*`: hasta 20260923180000 le entregaba a
-- cualquiera el costo y el proveedor, y desde entonces le falla con 42501. La
-- tienda no llama a ninguna de las dos; `match_products_semantic` la usa el
-- inventario del ERP, con sesión. En los registros de la API de las últimas
-- 24 h no hay llamadas a ninguna. Lo encontró la revisión de Codex.
--
-- `authenticated` y `service_role` conservan su permiso explícito.

-- Las bases armadas desde el esquema histórico no tienen la búsqueda por
-- vectores; en producción existen las dos.
do $$
declare
  funcion regprocedure;
begin
  foreach funcion in array array[
    to_regprocedure('public.search_products(text,uuid,integer)'),
    to_regprocedure(
      'public.match_products_semantic(vector,uuid,double precision,integer)')
  ] loop
    if funcion is not null then
      execute format('revoke execute on function %s from public, anon',
        funcion);
    end if;
  end loop;
end;
$$;
