-- Read-back de `20260830060000_one_signature_for_the_portal_receipt`.
--
-- No cuenta firmas y se da por satisfecho: **ejecuta las rutas que el cliente
-- usa de verdad** y exige que fallen por falta de contexto de negocio (42501),
-- no por ambigüedad (42725). Un `is not unique` no aparece al aplicar una
-- migración: aparece cuando alguien llama, y por eso hay que llamar acá.

-- 1. El conjunto EXACTO de firmas: una, y con `p_operation_key`.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as una_sola_firma
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'record_supplier_need_portal_search_v1';

select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as la_firma_es_la_de_trece
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'record_supplier_need_portal_search_v1'
  and pg_get_function_identity_arguments(p.oid) = 'p_supplier_id uuid, '
      || 'p_supply_need_id uuid, p_search_query text, p_status text, '
      || 'p_source_url text, p_results jsonb, p_evidence jsonb, '
      || 'p_coverage jsonb, p_expected_need_version bigint, '
      || 'p_expected_revision_no bigint, p_expected_category_id uuid, '
      || 'p_expected_technical_family text, p_operation_key text';

-- 2. Las rutas REALES se resuelven. `explain` hace el parseo y la resolución
--    de la función —que es donde estalla `42725 is not unique`— sin ejecutar su
--    cuerpo, así que prueba el despacho de verdad y no escribe una fila.
--    El guard de sólo lectura no admite bloques `do`, así que ésta es la forma
--    de ejercitar la ruta sin inventar un camino paralelo.

-- Ruta de 13 argumentos: la que usa el cliente hoy.
explain (costs off)
select public.record_supplier_need_portal_search_v1(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '00000000-0000-0000-0000-000000000000'::uuid,
  'camara', 'completed', null,
  '[]'::jsonb, '{}'::jsonb, '{}'::jsonb,
  1::bigint, 1::bigint, null::uuid, 'tube', 'read-back-nunca-escribe'
);

-- Ruta de 12 argumentos: la misma función por su default. Con la firma vieja
-- todavía presente, esta llamada es AMBIGUA y acá es donde se cae.
explain (costs off)
select public.record_supplier_need_portal_search_v1(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '00000000-0000-0000-0000-000000000000'::uuid,
  'camara', 'completed', null,
  '[]'::jsonb, '{}'::jsonb, '{}'::jsonb,
  1::bigint, 1::bigint, null::uuid, 'tube'
);

-- 3. Las firmas viejas ya no existen.
select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as sin_firmas_viejas
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'record_supplier_need_portal_search_v1'
  and p.pronargs in (7, 8, 12);

-- 4. Y nada de esto escribió una fila.
select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as el_readback_no_escribio
from public.supplier_need_portal_searches
where operation_key = 'read-back-nunca-escribe';
