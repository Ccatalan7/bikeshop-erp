-- El costo de compra por marca y las funciones de prueba salen de la API.
--
-- Diagnóstico de seguridad del 2026-09-23 (fila 12, permisos de anónimo).
-- Con la llave pública de la tienda y sin sesión:
--
-- * `GET /rest/v1/product_gama_v1` devolvía el costo neto promedio de compra
--   (`average_landed_unit_cost_net`) de cada marca por categoría: 107 filas.
--   La vista es SECURITY INVOKER, pero lee `product_gama_bands_mv`, y una
--   vista materializada no tiene RLS: además de anónimo, una sesión de
--   cualquier tenant leía los costos de todos. Nada en la app ni en las Edge
--   Functions la lee. La usan `purchase_candidate_scores_internal_v1` y
--   `purchase_supplier_concentration_internal_v1`, SECURITY DEFINER sin
--   permiso para clientes, y `refresh_product_gama_bands_v1` también es
--   SECURITY DEFINER: ninguna depende del permiso de quien llama.
-- * pgTAP estaba instalado en `public`: sus 1.074 funciones y dos vistas
--   quedaban en la API. `GET /rest/v1/tap_funky` listaba cada función del
--   esquema y cuáles son SECURITY DEFINER, y `POST /rest/v1/rpc/lives_ok`
--   ejecuta el SQL que recibe (con el rol anónimo). Sus objetos son de
--   `supabase_admin`, así que un `revoke` de `postgres` no les quita nada: se
--   reinstala en `extensions`, que PostgREST no expone. Ningún rol lo usa en
--   producción (pg_stat_statements sin llamadas; `codex_test_runner` no
--   inicia sesión). Las pruebas lo siguen resolviendo sin prefijo porque
--   `extensions` está en el search_path de `postgres`, en producción y en
--   local; `anon` y `authenticated` tienen USAGE en ese esquema.
--
-- Las demás funciones SECURITY DEFINER que anónimo puede ejecutar quedan como
-- están: son la fachada pública de la tienda, disparadores (PostgREST no los
-- expone) o exigen la capacidad del asistente adentro.

revoke all on table public.product_gama_bands_mv
  from public, anon, authenticated;
revoke all on table public.product_gama_v1
  from public, anon, authenticated;

-- Una base que ya lo tiene fuera de `public`, o que no lo tiene, no cambia.
do $$
declare
  v_version text;
begin
  select extversion into v_version
    from pg_extension
   where extname = 'pgtap'
     and extnamespace = 'public'::regnamespace;
  if v_version is not null then
    execute 'drop extension pgtap';
    execute format(
      'create extension pgtap with schema extensions version %L',
      v_version
    );
  end if;
end;
$$;
