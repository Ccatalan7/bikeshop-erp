-- Read-back de `20260830080000_restore_installed_client_stubs`.
--
-- Ejecuta las tres rutas reales. Los stubs son `immutable` y no escriben, así
-- que acá sí se pueden **llamar de verdad** y comprobar su respuesta; la de 13
-- se resuelve con `explain`, que hace el despacho sin ejecutar el cuerpo.

-- 1. La app instalada de 7 argumentos recibe una respuesta ordenada.
select 1 / (
  case when public.record_supplier_need_portal_search_v1(
    '00000000-0000-0000-0000-000000000000'::uuid,
    '00000000-0000-0000-0000-000000000000'::uuid,
    'camara', 'completed', null, '[]'::jsonb, '{}'::jsonb
  ) ->> 'status' = 'client_upgrade_required' then 1 else 0 end
) as stub_de_siete_responde;

select 1 / (
  case when public.record_supplier_need_portal_search_v1(
    '00000000-0000-0000-0000-000000000000'::uuid,
    '00000000-0000-0000-0000-000000000000'::uuid,
    'camara', 'completed', null, '[]'::jsonb, '{}'::jsonb
  ) ->> 'recorded' = 'false' then 1 else 0 end
) as stub_de_siete_no_guarda;

-- 2. La de 8 argumentos, igual.
select 1 / (
  case when public.record_supplier_need_portal_search_v1(
    '00000000-0000-0000-0000-000000000000'::uuid,
    '00000000-0000-0000-0000-000000000000'::uuid,
    'camara', 'completed', null, '[]'::jsonb, '{}'::jsonb, '{}'::jsonb
  ) ->> 'status' = 'client_upgrade_required' then 1 else 0 end
) as stub_de_ocho_responde;

-- 3. La ruta vigente de 13 sigue resolviendo sin ambigüedad.
explain (costs off)
select public.record_supplier_need_portal_search_v1(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '00000000-0000-0000-0000-000000000000'::uuid,
  'camara', 'completed', null,
  '[]'::jsonb, '{}'::jsonb, '{}'::jsonb,
  1::bigint, 1::bigint, null::uuid, 'tube', 'read-back-nunca-escribe'
);

-- 4. Y la de 12 —la que sí competía— sigue retirada, así que la llamada corta
--    del cliente vigente resuelve contra la de 13 por su default.
select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as la_firma_de_doce_sigue_retirada
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'record_supplier_need_portal_search_v1'
  and p.pronargs = 12;

explain (costs off)
select public.record_supplier_need_portal_search_v1(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '00000000-0000-0000-0000-000000000000'::uuid,
  'camara', 'completed', null,
  '[]'::jsonb, '{}'::jsonb, '{}'::jsonb,
  1::bigint, 1::bigint, null::uuid, 'tube'
);

-- 5. El conjunto exacto: los dos stubs y la firma vigente. Ni una más.
select 1 / (
  case when count(*) = 3 then 1 else 0 end
) as tres_firmas_exactas
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'record_supplier_need_portal_search_v1';

-- 6. Nada de esto escribió una fila.
select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as el_readback_no_escribio
from public.supplier_need_portal_searches
where operation_key = 'read-back-nunca-escribe';
