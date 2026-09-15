begin;

select no_plan();

-- Tres operaciones distintas sobre una necesidad que ya existe.
--
-- La que originó todo esto: `update_supply_need_v1` escribía una revisión con
-- `constraints: []` ante CUALQUIER cambio, así que cambiar un 3 por un 4
-- borraba la ficha técnica y la categoría de una necesidad ya interpretada, en
-- silencio. Medido en producción el 2026-08-29 el daño no había ocurrido —las
-- 7 revisiones `manual-v1` eran todas `revision_no = 1`— pero estaba armado.

select has_function(
  'public', 'set_supply_need_quantity_v1',
  array['uuid', 'bigint', 'numeric', 'text', 'text'],
  'la cantidad tiene su propio comando'
);
select has_function(
  'public', 'refine_supply_need_v1',
  array['uuid', 'bigint', 'bigint', 'uuid', 'text', 'jsonb', 'text'],
  'precisar la ficha lleva su revisión esperada y la familia'
);
select hasnt_function(
  'public', 'refine_supply_need_v1',
  array['uuid', 'bigint', 'uuid', 'jsonb', 'numeric', 'text'],
  'la firma anterior, que mezclaba cantidad, ya no existe'
);
select has_column(
  'public', 'supply_need_interpretation_revisions', 'continuity',
  'una revisión dice si continúa o reemplaza'
);
select has_column(
  'public', 'supply_need_interpretation_revisions', 'supersedes_revision_no',
  'y de cuál viene'
);
select has_column(
  'public', 'supply_need_interpretation_revisions', 'technical_family',
  'la familia fija el alcance enumerable y la estampa el servidor'
);
select has_column(
  'public', 'supplier_need_portal_searches',
  'interpretation_technical_family',
  'el recibo del portal guarda el alcance, no sólo la categoría'
);

-- ---------------------------------------------------------------------------
-- Semilla
-- ---------------------------------------------------------------------------

insert into public.tenants (id, shop_name, owner_email, timezone)
values (
  'ed17e000-0000-4000-8000-000000000001', 'Edit modes tenant',
  'edit-modes@example.invalid', 'America/Santiago'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ed17e000-0000-4000-8000-000000000011', 'authenticated', 'authenticated',
  'edit-modes-buyer@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
  now(), now()
);

insert into public.user_profiles (user_id, tenant_id, role, permissions)
values (
  'ed17e000-0000-4000-8000-000000000011',
  'ed17e000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb
);

insert into public.product_categories (id, tenant_id, name, full_path)
values (
  'ed17e000-0000-4000-8000-000000000041',
  'ed17e000-0000-4000-8000-000000000001', 'Cámaras',
  'Componentes / Ruedas / Cámaras'
);

insert into public.supply_needs (
  id, tenant_id, origin_kind, original_description, quantity, unit
) values (
  'ed17e000-0000-4000-8000-000000000031',
  'ed17e000-0000-4000-8000-000000000001', 'ad_hoc',
  'Cámaras aro 700 para reposición del taller', 3, 'unidad'
);

-- La interpretación que ya existía: categoría reconocida y ficha con un
-- criterio. Es exactamente el estado que el editor viejo destruía.
insert into public.supply_need_interpretation_revisions (
  tenant_id, supply_need_id, revision_no, source, raw_description,
  identity_state, category_id, constraints, formula_version,
  continuity, technical_family
) values (
  'ed17e000-0000-4000-8000-000000000001',
  'ed17e000-0000-4000-8000-000000000031', 1, 'ai',
  'Cámaras aro 700 para reposición del taller', 'unresolved',
  'ed17e000-0000-4000-8000-000000000041',
  '[{"field":"wheel_size","operator":"eq","values":["700c"]}]'::jsonb,
  'assistant-v1', 'initial', 'tube'
);

update public.supply_needs
set version = 1
where id = 'ed17e000-0000-4000-8000-000000000031';

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'ed17e000-0000-4000-8000-000000000011',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'ed17e000-0000-4000-8000-000000000011', true);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- 1. Sólo cantidad: sube version, NO crea revisión, no pierde la ficha
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select public.set_supply_need_quantity_v1(
      'ed17e000-0000-4000-8000-000000000031', 1, 5, 'unidad',
      'ed17e000-0000-4000-8000-0000000000a1'
    )$$,
  'cambiar cuántas unidades se necesitan es una operación legítima'
);
select is(
  (select quantity::int from public.supply_needs
   where id = 'ed17e000-0000-4000-8000-000000000031'),
  5,
  'la cantidad quedó guardada'
);
select is(
  (select version from public.supply_needs
   where id = 'ed17e000-0000-4000-8000-000000000031'),
  2::bigint,
  'la fila cambió, así que su version sube'
);
select is(
  (select count(*)::int from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'),
  1,
  'la pregunta al catálogo NO cambió: ninguna revisión nueva'
);
select is(
  (select jsonb_array_length(constraints)
   from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'
   order by revision_no desc limit 1),
  1,
  'la ficha técnica sigue entera después de cambiar la cantidad'
);
select isnt(
  (select category_id from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'
   order by revision_no desc limit 1),
  null,
  'y la categoría también'
);

-- ---------------------------------------------------------------------------
-- 2. El cliente antiguo tampoco puede borrarla
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select public.update_supply_need_v1(
      'ed17e000-0000-4000-8000-000000000031', 2,
      'Cámaras aro 700 para reposición del taller', null, 7, 'unidad',
      'ed17e000-0000-4000-8000-0000000000a2'
    )$$,
  'el comando heredado sigue existiendo para clientes sin actualizar'
);
select is(
  (select count(*)::int from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'),
  1,
  'una cantidad por el camino viejo tampoco consume linaje'
);
select is(
  (select jsonb_array_length(constraints)
   from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'
   order by revision_no desc limit 1),
  1,
  'y tampoco borra la ficha: el P1 no queda vivo detrás del editor nuevo'
);

-- Corregir el texto sí crea revisión, pero arrastra la ficha en vez de
-- apagarla.
select lives_ok(
  $$select public.update_supply_need_v1(
      'ed17e000-0000-4000-8000-000000000031', 3,
      'Cámaras aro 700 para reposición del taller (urgente)', null, 7,
      'unidad', 'ed17e000-0000-4000-8000-0000000000a3'
    )$$,
  'el camino heredado puede corregir el texto'
);
select is(
  (select jsonb_array_length(constraints)
   from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'
   order by revision_no desc limit 1),
  1,
  'un texto corregido conserva los criterios'
);
select is(
  (select technical_family from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'
   order by revision_no desc limit 1),
  'tube',
  'y conserva la familia que fija el alcance'
);

-- ---------------------------------------------------------------------------
-- 3. Los dos cerrojos de precisar
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select public.refine_supply_need_v1(
      'ed17e000-0000-4000-8000-000000000031', 99, 2,
      'ed17e000-0000-4000-8000-000000000041', 'tube', '[]'::jsonb,
      'ed17e000-0000-4000-8000-0000000000b1'
    )$$,
  '40001',
  'La necesidad cambió; vuelve a cargarla antes de guardar.',
  'precisar sobre una fila que ya cambió se rechaza'
);

-- La revisión esperada es la otra mitad: la fila puede no haberse movido y la
-- pregunta sí.
select throws_ok(
  $$select public.refine_supply_need_v1(
      'ed17e000-0000-4000-8000-000000000031', 4, 1,
      'ed17e000-0000-4000-8000-000000000041', 'tube', '[]'::jsonb,
      'ed17e000-0000-4000-8000-0000000000b2'
    )$$,
  '40001',
  'La ficha cambió; vuelve a abrirla antes de guardar.',
  'precisar sobre una ficha que alguien reemplazó se rechaza'
);

-- ---------------------------------------------------------------------------
-- 4. Precisar de verdad: qué queda escrito
-- ---------------------------------------------------------------------------

-- **El normalizador es autoritativo, y esta prueba usa el registro real.**
-- `wheel_size` y `valve_type` ya existen como definiciones de sistema: sin
-- ellas `refine` rechaza los predicados con «Unknown technical predicate», que
-- es la validación funcionando. Sembrar copias propias probaría el doble, no
-- el registro.
reset role;
-- El template activo de la categoría: sin él el normalizador rechaza los
-- predicados con «Technical predicates require an active category template».
insert into public.spec_templates (
  id, tenant_id, key, name, technical_family, is_active
) values (
  'ed17e000-0000-4000-8000-000000000061',
  'ed17e000-0000-4000-8000-000000000001', 'tube-edit-modes', 'Cámaras',
  'tube', true
);

insert into public.spec_template_fields (
  tenant_id, template_id, spec_definition_id, sort_order
)
select
  'ed17e000-0000-4000-8000-000000000001',
  'ed17e000-0000-4000-8000-000000000061',
  definition.id,
  1
from public.spec_definitions definition
where definition.key = 'wheel_size'
  and definition.is_filterable is true
limit 1;

insert into public.category_tech_mappings (
  tenant_id, category_id, technical_family, template_id, status
) values (
  'ed17e000-0000-4000-8000-000000000001',
  'ed17e000-0000-4000-8000-000000000041', 'tube',
  'ed17e000-0000-4000-8000-000000000061', 'active'
);
set local role authenticated;

select lives_ok(
  $$select public.refine_supply_need_v1(
      'ed17e000-0000-4000-8000-000000000031', 4, 2,
      'ed17e000-0000-4000-8000-000000000041', 'tube',
      '[{"field":"wheel_size","operator":"eq","values":["650b"]}]'::jsonb,
      'ed17e000-0000-4000-8000-0000000000c1'
    )$$,
  'precisar la ficha dentro de la categoría reconocida funciona'
);
select is(
  (select continuity from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'
   order by revision_no desc limit 1),
  'refined',
  'la revisión nueva declara que continúa la anterior'
);
select is(
  (select supersedes_revision_no
   from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'
   order by revision_no desc limit 1),
  2::bigint,
  'y de cuál viene'
);
select is(
  (select technical_family from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'
   order by revision_no desc limit 1),
  'tube',
  'la familia quedó estampada desde el mapeo, no desde el cliente'
);

-- **`revision_no` no se deriva de `version`.** Son dos relojes: la cantidad
-- movió `version` sin tocar el linaje, así que a estas alturas no coinciden.
select ok(
  (select need.version from public.supply_needs need
   where need.id = 'ed17e000-0000-4000-8000-000000000031')
  <> (select max(revision_no)
      from public.supply_need_interpretation_revisions
      where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'),
  'version y revision_no avanzan por su cuenta'
);
select is(
  (select max(revision_no) from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'),
  3::bigint,
  'la revisión nueva es max+1, no la version de la fila'
);

-- ---------------------------------------------------------------------------
-- 5. La familia no la declara el cliente
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select public.refine_supply_need_v1(
      'ed17e000-0000-4000-8000-000000000031', 5, 3,
      'ed17e000-0000-4000-8000-000000000041', 'tire', '[]'::jsonb,
      'ed17e000-0000-4000-8000-0000000000c2'
    )$$,
  '40001',
  'La ficha técnica de esa categoría cambió; vuelve a abrirla antes de guardar.',
  'una familia distinta a la del registro se rechaza en vez de persistirse'
);

-- ---------------------------------------------------------------------------
-- 6. Una lectura que quedó vieja mientras corría se pierde, no se reetiqueta
-- ---------------------------------------------------------------------------

reset role;
insert into public.suppliers (id, tenant_id, name)
values (
  'ed17e000-0000-4000-8000-000000000021',
  'ed17e000-0000-4000-8000-000000000001', 'Portal supplier'
);
insert into public.supplier_portal_probes (
  tenant_id, supplier_id, search_url_template, is_enabled,
  need_search_url_template, need_search_term_limit, need_search_adapter
) values (
  'ed17e000-0000-4000-8000-000000000001',
  'ed17e000-0000-4000-8000-000000000021',
  'https://portal.example.invalid/buscar?codigo={code}', true,
  'https://portal.example.invalid/buscar?palabra={query}', 15,
  '{"version":"1","generic_family_search":true}'::jsonb
);
set local role authenticated;

-- La revisión vigente es 3. Un recorrido que empezó en la 2 y termina ahora
-- está entregando filas leídas contra otra ficha.
select throws_ok(
  $$select public.record_supplier_need_portal_search_v1(
      'ed17e000-0000-4000-8000-000000000021',
      'ed17e000-0000-4000-8000-000000000031',
      'camara', 'no_matches', null, '[]'::jsonb, '{}'::jsonb, '{}'::jsonb,
      5, 2, 'ed17e000-0000-4000-8000-000000000041', 'tube'
    )$$,
  '40001',
  null,
  'un recorrido que empezó en la revisión anterior se rechaza al guardar'
);

select throws_ok(
  $$select public.record_supplier_need_portal_search_v1(
      'ed17e000-0000-4000-8000-000000000021',
      'ed17e000-0000-4000-8000-000000000031',
      'camara', 'no_matches', null, '[]'::jsonb, '{}'::jsonb, '{}'::jsonb,
      null, null, null, null
    )$$,
  '23514',
  'Need search must declare the interpretation it answered',
  'un recibo sin estampa no entra: el servidor ya no la inventa'
);

select lives_ok(
  $$select public.record_supplier_need_portal_search_v1(
      'ed17e000-0000-4000-8000-000000000021',
      'ed17e000-0000-4000-8000-000000000031',
      'camara', 'no_matches', null, '[]'::jsonb, '{}'::jsonb, '{}'::jsonb,
      5, 3, 'ed17e000-0000-4000-8000-000000000041', 'tube'
    )$$,
  'una lectura que responde la revisión vigente sí se guarda'
);
select is(
  (select interpretation_revision_no
   from public.supplier_need_portal_searches
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'
   order by checked_at desc limit 1),
  3::bigint,
  'y queda estampada con lo que declaró, no con lo que el servidor supuso'
);

-- ---------------------------------------------------------------------------
-- 7. Una revisión `refined` deja cruzar; una `replaced` no
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select public.refine_supply_need_v1(
      'ed17e000-0000-4000-8000-000000000031', 5, 3,
      'ed17e000-0000-4000-8000-000000000041', 'tube',
      '[{"field":"wheel_size","operator":"eq","values":["700c"]}]'::jsonb,
      'ed17e000-0000-4000-8000-0000000000c3'
    )$$,
  'se precisa otra vez, creando la revisión 4'
);
select isnt(
  (select public.supplier_last_need_portal_search_v1(
     'ed17e000-0000-4000-8000-000000000021',
     'ed17e000-0000-4000-8000-000000000031'
   ) ->> 'status'),
  'never_searched',
  'una precisión deja reutilizar la observación anterior'
);

-- Ahora se reemplaza la petición DENTRO de la misma categoría: el caso que
-- categoría+familia no distinguían.
select lives_ok(
  $$select public.replace_supply_need_v1(
      'ed17e000-0000-4000-8000-000000000031', 6,
      'Cámaras aro 26 para el taller', 7, 'unidad',
      'ed17e000-0000-4000-8000-0000000000c4'
    )$$,
  'cambiar la petición es una operación legítima'
);
select is(
  (select continuity from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'
   order by revision_no desc limit 1),
  'replaced',
  'y queda declarada como reemplazo'
);
-- **El caso que la regla guarda de verdad.** Tras reemplazar, la familia queda
-- nula y la comparación de alcance ya rechazaría el cruce por sí sola: eso
-- haría verde esta prueba sin probar la continuidad. El estado peligroso es el
-- alcanzable reemplazando y volviendo a precisar hasta caer en la MISMA
-- categoría y la MISMA familia; se construye con un insert porque el árbol de
-- revisiones es append-only y un update lo rechaza.
reset role;
insert into public.supply_need_interpretation_revisions (
  tenant_id, supply_need_id, revision_no, source, raw_description,
  identity_state, category_id, constraints, formula_version,
  supersedes_revision_no, continuity, technical_family
)
select
  'ed17e000-0000-4000-8000-000000000001',
  'ed17e000-0000-4000-8000-000000000031',
  max(revision_no) + 1, 'manual', 'Cámaras aro 26 para el taller',
  'unresolved', 'ed17e000-0000-4000-8000-000000000041',
  '[{"field":"wheel_size","operator":"eq","values":["26\""]}]'::jsonb,
  'operator-refinement-v1', max(revision_no), 'refined', 'tube'
from public.supply_need_interpretation_revisions
where supply_need_id = 'ed17e000-0000-4000-8000-000000000031';
set local role authenticated;

select is(
  (select public.supplier_last_need_portal_search_v1(
     'ed17e000-0000-4000-8000-000000000021',
     'ed17e000-0000-4000-8000-000000000031'
   ) ->> 'status'),
  'never_searched',
  'con misma categoría y misma familia, un reemplazo intermedio corta igual'
);

-- ---------------------------------------------------------------------------
-- 7.b El cliente instalado no se rompe, y tampoco guarda evidencia vigente
--
-- Desplegar este backend con la app anterior en los equipos es el caso normal.
-- Ese cliente llama la firma de 7 argumentos y no tiene forma de mandar la
-- estampa: tiene que vivir, y no tiene que dejar nada que se vea como vigente.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from public.supplier_need_portal_searches
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'),
  1,
  'antes del cliente viejo hay exactamente una lectura guardada'
);

select is(
  (select public.record_supplier_need_portal_search_v1(
     'ed17e000-0000-4000-8000-000000000021',
     'ed17e000-0000-4000-8000-000000000031',
     'camara', 'completed', null,
     '[{"code":"9","name":"CAMARA VIEJA","matchState":"exact"}]'::jsonb,
     '{}'::jsonb
   ) ->> 'status'),
  'client_upgrade_required',
  'la app instalada recibe una respuesta, no una excepción'
);
select is(
  (select public.record_supplier_need_portal_search_v1(
     'ed17e000-0000-4000-8000-000000000021',
     'ed17e000-0000-4000-8000-000000000031',
     'camara', 'completed', null, '[]'::jsonb, '{}'::jsonb, '{}'::jsonb
   ) ->> 'recorded')::boolean,
  false,
  'y la firma intermedia con cobertura tampoco guarda'
);
select is(
  (select count(*)::int from public.supplier_need_portal_searches
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000031'),
  1,
  'ninguna de las dos creó evidencia: el portal queda «sin consultar»'
);

-- ---------------------------------------------------------------------------
-- 7.c El feed histórico sobrevive a la primera precisión
--
-- Sin el backfill de familia, un recibo anterior queda en `null`, la primera
-- precisión le pone `tube` a la revisión nueva, y la igualdad null-safe del
-- lector esconde justo el feed que había que filtrar sin red: el requisito
-- principal se rompe en el primer uso real. Medido en producción el
-- 2026-08-29: 13 búsquedas, 13 con categoría, 13 con familia autoritativa.
-- ---------------------------------------------------------------------------

reset role;

insert into public.supply_needs (
  id, tenant_id, origin_kind, original_description, quantity, unit
) values (
  'ed17e000-0000-4000-8000-000000000071',
  'ed17e000-0000-4000-8000-000000000001', 'ad_hoc',
  'Cámaras aro 700 heredadas', 2, 'unidad'
);

-- Revisión LEGACY: categoría resuelta y **sin familia**, como todo lo que hay
-- guardado hoy.
insert into public.supply_need_interpretation_revisions (
  tenant_id, supply_need_id, revision_no, source, raw_description,
  identity_state, category_id, constraints, formula_version
) values (
  'ed17e000-0000-4000-8000-000000000001',
  'ed17e000-0000-4000-8000-000000000071', 1, 'ai',
  'Cámaras aro 700 heredadas', 'unresolved',
  'ed17e000-0000-4000-8000-000000000041',
  '[{"field":"wheel_size","operator":"eq","values":["700c"]}]'::jsonb,
  'assistant-v1'
);
update public.supply_needs set version = 1
where id = 'ed17e000-0000-4000-8000-000000000071';

-- Recibo LEGACY: estampado con categoría y revisión, sin familia.
insert into public.supplier_need_portal_searches (
  tenant_id, supplier_id, supply_need_id, search_query, status, results,
  need_version_at_search, interpretation_revision_no,
  interpretation_category_id, interpretation_technical_family
) values (
  'ed17e000-0000-4000-8000-000000000001',
  'ed17e000-0000-4000-8000-000000000021',
  'ed17e000-0000-4000-8000-000000000071',
  'camara', 'completed',
  '[{"code":"10001","name":"CAMARA 700X28C","matchState":"exact"}]'::jsonb,
  1, 1, 'ed17e000-0000-4000-8000-000000000041', null
);

select is(
  (select interpretation_technical_family
   from public.supplier_need_portal_searches
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000071'),
  null,
  'el punto de partida es el estado real de hoy: sin familia'
);

-- El backfill de la migración, representado sobre estas filas.
alter table public.supply_need_interpretation_revisions
  disable trigger trg_supply_need_interpretation_revisions_immutable;
update public.supply_need_interpretation_revisions revision
set technical_family = mapping.technical_family
from public.category_tech_mappings mapping
where mapping.tenant_id = revision.tenant_id
  and mapping.category_id = revision.category_id
  and revision.supply_need_id = 'ed17e000-0000-4000-8000-000000000071'
  and revision.technical_family is null
  and mapping.technical_family is not null;
alter table public.supply_need_interpretation_revisions
  enable trigger trg_supply_need_interpretation_revisions_immutable;

update public.supplier_need_portal_searches search
set interpretation_technical_family = revision.technical_family
from public.supply_need_interpretation_revisions revision
where revision.tenant_id = search.tenant_id
  and revision.supply_need_id = search.supply_need_id
  and revision.revision_no = search.interpretation_revision_no
  and search.supply_need_id = 'ed17e000-0000-4000-8000-000000000071'
  and search.interpretation_technical_family is null;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'ed17e000-0000-4000-8000-000000000011',
  'role', 'authenticated'
)::text, true);
set local role authenticated;

-- Ahora se precisa. La revisión nueva toma `tube` del mapeo.
select lives_ok(
  $$select public.refine_supply_need_v1(
      'ed17e000-0000-4000-8000-000000000071', 1, 1,
      'ed17e000-0000-4000-8000-000000000041', 'tube',
      '[{"field":"wheel_size","operator":"eq","values":["650b"]}]'::jsonb,
      'ed17e000-0000-4000-8000-0000000000d1'
    )$$,
  'se precisa la ficha de una necesidad heredada'
);
select is(
  (select technical_family from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000071'
   order by revision_no desc limit 1),
  'tube',
  'la revisión nueva toma la familia del mapeo autoritativo'
);

-- **El requisito principal.** El feed histórico tiene que seguir llegando para
-- volver a evaluarlo sin red.
select is(
  (select public.supplier_last_need_portal_search_v1(
     'ed17e000-0000-4000-8000-000000000021',
     'ed17e000-0000-4000-8000-000000000071'
   ) ->> 'status'),
  'completed',
  'tras precisar, el feed heredado sigue disponible para volver a evaluarlo'
);
select is(
  jsonb_array_length(
    public.supplier_last_need_portal_search_v1(
      'ed17e000-0000-4000-8000-000000000021',
      'ed17e000-0000-4000-8000-000000000071'
    ) -> 'results'
  ),
  1,
  'y llega con sus filas crudas, que es lo que se vuelve a juzgar'
);

-- ---------------------------------------------------------------------------
-- 7.c-bis Tras cambiar la petición se puede buscar de inmediato
--
-- La revisión de reemplazo se insertaba con familia nula «para que la fije un
-- refine posterior». El cliente arma su petición con la familia del template
-- recién resuelto, el recibo la manda, y el guardián la comparaba contra nulo:
-- 40001 en la primera búsqueda después de «Cambiar lo que estoy buscando».
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select public.replace_supply_need_v1(
      'ed17e000-0000-4000-8000-000000000071', 2,
      'Cámaras aro 700 para el taller, otra vez', 4, 'unidad',
      'ed17e000-0000-4000-8000-0000000000d2'
    )$$,
  'se cambia la petición de la necesidad heredada'
);
select isnt(
  (select technical_family from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000071'
   order by revision_no desc limit 1),
  null,
  'la revisión de reemplazo estampa la familia de la categoría NUEVA'
);

select lives_ok(
  $$select public.record_supplier_need_portal_search_v1(
      'ed17e000-0000-4000-8000-000000000021',
      'ed17e000-0000-4000-8000-000000000071',
      'camara', 'completed', null,
      '[{"code":"20001","name":"CAMARA 700X28C","matchState":"exact"}]'::jsonb,
      '{}'::jsonb,
      '{"method":"taxonomy","complete":true,"limit":"enumerated"}'::jsonb,
      (select version from public.supply_needs
       where id = 'ed17e000-0000-4000-8000-000000000071'),
      (select max(revision_no)
       from public.supply_need_interpretation_revisions
       where supply_need_id = 'ed17e000-0000-4000-8000-000000000071'),
      (select category_id from public.supply_need_interpretation_revisions
       where supply_need_id = 'ed17e000-0000-4000-8000-000000000071'
       order by revision_no desc limit 1),
      (select technical_family from public.supply_need_interpretation_revisions
       where supply_need_id = 'ed17e000-0000-4000-8000-000000000071'
       order by revision_no desc limit 1)
    )$$,
  'la primera búsqueda después de cambiar la petición se puede guardar'
);
select is(
  (select public.supplier_last_need_portal_search_v1(
     'ed17e000-0000-4000-8000-000000000021',
     'ed17e000-0000-4000-8000-000000000071'
   ) ->> 'status'),
  'completed',
  'y queda legible de inmediato para la necesidad reemplazada'
);

-- ---------------------------------------------------------------------------
-- 7.d Una transición histórica no demostrada no deja cruzar
--
-- «Misma categoría» no prueba continuidad: una petición se puede reemplazar
-- por otra dentro de la misma categoría. Sin evidencia de que el alcance se
-- conservó, la continuidad queda nula y el puente no existe.
-- ---------------------------------------------------------------------------

reset role;
insert into public.supply_need_interpretation_revisions (
  tenant_id, supply_need_id, revision_no, source, raw_description,
  identity_state, category_id, constraints, formula_version,
  supersedes_revision_no, continuity, technical_family
)
select
  'ed17e000-0000-4000-8000-000000000001',
  'ed17e000-0000-4000-8000-000000000071', max(revision_no) + 1, 'ai',
  'Cámaras aro 26 heredadas', 'unresolved',
  'ed17e000-0000-4000-8000-000000000041',
  -- **Constraints IGUALES a la anterior y categoría igual.** Una petición poco
  -- especificada puede pasar de cámaras 700 a cámaras 26 sin mover un solo
  -- predicado: misma categoría, mismos criterios, otra pregunta. Lo único que
  -- faltaría para llamarla continua es una procedencia demostrable, y
  -- `assistant-v1` no lo es.
  (select constraints from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000071'
   order by revision_no desc limit 1),
  'assistant-v1',
  max(revision_no), null, 'tube'
from public.supply_need_interpretation_revisions
where supply_need_id = 'ed17e000-0000-4000-8000-000000000071';
set local role authenticated;

select is(
  (select public.supplier_last_need_portal_search_v1(
     'ed17e000-0000-4000-8000-000000000021',
     'ed17e000-0000-4000-8000-000000000071'
   ) ->> 'status'),
  'never_searched',
  'misma categoría, mismos criterios y fórmula desconocida: no deja cruzar'
);

-- ---------------------------------------------------------------------------
-- 7.e El backfill de continuidad exige procedencia demostrable
--
-- Ni la categoría ni los predicados iguales prueban continuidad: una petición
-- poco especificada puede pasar de cámaras 700 a cámaras 26 conservando
-- `constraints` vacíos. Sólo una operación que POR CONSTRUCCIÓN conserva el
-- alcance puede marcarse `refined`; hoy esa lista tiene un nombre.
-- ---------------------------------------------------------------------------

reset role;

insert into public.supply_needs (
  id, tenant_id, origin_kind, original_description, quantity, unit
) values (
  'ed17e000-0000-4000-8000-000000000081',
  'ed17e000-0000-4000-8000-000000000001', 'ad_hoc', 'Cámaras sin precisar',
  1, 'unidad'
);

-- Un par legacy: misma categoría, `constraints` vacíos en ambas, y una
-- fórmula que no demuestra nada.
insert into public.supply_need_interpretation_revisions (
  tenant_id, supply_need_id, revision_no, source, raw_description,
  identity_state, category_id, constraints, formula_version
) values
  ('ed17e000-0000-4000-8000-000000000001',
   'ed17e000-0000-4000-8000-000000000081', 1, 'ai', 'Cámaras 700',
   'unresolved', 'ed17e000-0000-4000-8000-000000000041', '[]'::jsonb,
   'assistant-v1'),
  ('ed17e000-0000-4000-8000-000000000001',
   'ed17e000-0000-4000-8000-000000000081', 2, 'ai', 'Cámaras 26',
   'unresolved', 'ed17e000-0000-4000-8000-000000000041', '[]'::jsonb,
   'assistant-v1'),
  -- Y una que sí: `family-choice-v1` copia categoría y criterios de la
  -- anterior para confirmar cuál producto era.
  ('ed17e000-0000-4000-8000-000000000001',
   'ed17e000-0000-4000-8000-000000000081', 3, 'manual', 'Cámaras 26',
   -- `unresolved` porque la fixture no confirma un producto; lo que se está
   -- probando es la procedencia, no la identidad.
   'unresolved', 'ed17e000-0000-4000-8000-000000000041', '[]'::jsonb,
   'family-choice-v1');

-- El backfill de la migración, representado sobre estas filas.
alter table public.supply_need_interpretation_revisions
  disable trigger trg_supply_need_interpretation_revisions_immutable;
with lineage as (
  select
    revision.id,
    revision.revision_no,
    revision.category_id,
    revision.constraints,
    revision.formula_version,
    lag(revision.revision_no) over w as previous_no,
    lag(revision.category_id) over w as previous_category_id,
    lag(revision.constraints) over w as previous_constraints
  from public.supply_need_interpretation_revisions revision
  where revision.supply_need_id = 'ed17e000-0000-4000-8000-000000000081'
  window w as (
    partition by revision.tenant_id, revision.supply_need_id
    order by revision.revision_no
  )
)
update public.supply_need_interpretation_revisions revision
set supersedes_revision_no = lineage.previous_no,
    continuity = case
      when lineage.previous_no is null then 'initial'
      when lineage.formula_version in ('family-choice-v1')
       and lineage.category_id is not null
       and lineage.category_id = lineage.previous_category_id
       and lineage.constraints = lineage.previous_constraints then 'refined'
      else null
    end
from lineage
where lineage.id = revision.id
  and revision.continuity is null;
alter table public.supply_need_interpretation_revisions
  enable trigger trg_supply_need_interpretation_revisions_immutable;

select is(
  (select continuity from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000081'
     and revision_no = 1),
  'initial',
  'la primera revisión es inicial'
);
select is(
  (select continuity from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000081'
     and revision_no = 2),
  null,
  'misma categoría y criterios vacíos con fórmula desconocida NO es continuar'
);
select is(
  (select continuity from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000081'
     and revision_no = 3),
  'refined',
  'una operación que copia categoría y criterios sí demuestra continuidad'
);

set local role authenticated;

-- ---------------------------------------------------------------------------
-- 7.f La app vieja sigue guardando, pero su edición no reutiliza el feed
--
-- El camino heredado copia categoría y criterios hacia delante para no
-- borrarlos, pero el TEXTO cambió y por esa puerta no hay forma de saber si
-- fue corregir una tilde o pedir otra cosa. Marcarlo `refined` dejaría cruzar
-- el feed de «cámaras 700» hacia una petición que ahora dice «cámaras 26».
-- ---------------------------------------------------------------------------

reset role;

insert into public.supply_needs (
  id, tenant_id, origin_kind, original_description, quantity, unit, version
) values (
  'ed17e000-0000-4000-8000-000000000091',
  'ed17e000-0000-4000-8000-000000000001', 'ad_hoc',
  'Cámaras aro 700 del cliente viejo', 2, 'unidad', 1
);

insert into public.supply_need_interpretation_revisions (
  tenant_id, supply_need_id, revision_no, source, raw_description,
  identity_state, category_id, constraints, formula_version,
  continuity, technical_family
) values (
  'ed17e000-0000-4000-8000-000000000001',
  'ed17e000-0000-4000-8000-000000000091', 1, 'ai',
  'Cámaras aro 700 del cliente viejo', 'unresolved',
  'ed17e000-0000-4000-8000-000000000041',
  '[{"field":"wheel_size","operator":"eq","values":["700c"]}]'::jsonb,
  'assistant-v1', 'initial', 'tube'
);

set local role authenticated;

-- Una búsqueda real ANTES de la edición heredada.
select lives_ok(
  $$select public.record_supplier_need_portal_search_v1(
      'ed17e000-0000-4000-8000-000000000021',
      'ed17e000-0000-4000-8000-000000000091',
      'camara', 'completed', null,
      '[{"code":"30001","name":"CAMARA 700X28C","matchState":"exact"}]'::jsonb,
      '{}'::jsonb,
      '{"method":"taxonomy","complete":true,"limit":"enumerated"}'::jsonb,
      1, 1, 'ed17e000-0000-4000-8000-000000000041', 'tube'
    )$$,
  'se lee el portal para la ficha vigente'
);
select is(
  (select public.supplier_last_need_portal_search_v1(
     'ed17e000-0000-4000-8000-000000000021',
     'ed17e000-0000-4000-8000-000000000091'
   ) ->> 'status'),
  'completed',
  'y el feed se puede reutilizar mientras la ficha no cambie'
);

-- La app vieja cambia el texto: de cámaras 700 a cámaras 26.
select lives_ok(
  $$select public.update_supply_need_v1(
      'ed17e000-0000-4000-8000-000000000091', 1,
      'Cámaras aro 26 del cliente viejo', null, 2, 'unidad',
      'ed17e000-0000-4000-8000-0000000000e1'
    )$$,
  'la app instalada sigue pudiendo guardar su edición'
);
select is(
  (select jsonb_array_length(constraints)
   from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000091'
   order by revision_no desc limit 1),
  1,
  'la ficha no se borra: eso sigue arreglado'
);
select is(
  (select continuity from public.supply_need_interpretation_revisions
   where supply_need_id = 'ed17e000-0000-4000-8000-000000000091'
   order by revision_no desc limit 1),
  null,
  'pero la continuidad queda nula: nadie puede demostrar que continúa'
);
select is(
  (select public.supplier_last_need_portal_search_v1(
     'ed17e000-0000-4000-8000-000000000021',
     'ed17e000-0000-4000-8000-000000000091'
   ) ->> 'status'),
  'never_searched',
  'y el feed anterior deja de cruzarse hacia la petición nueva'
);

-- ---------------------------------------------------------------------------
-- 8. Permisos y firmas
-- ---------------------------------------------------------------------------

reset role;

select ok(
  (select bool_and(
     has_function_privilege('authenticated', proc.oid, 'EXECUTE')
     and not has_function_privilege('anon', proc.oid, 'EXECUTE'))
   from pg_proc proc
   join pg_namespace namespace on namespace.oid = proc.pronamespace
   where namespace.nspname = 'public'
     and proc.proname in (
       'set_supply_need_quantity_v1',
       'refine_supply_need_v1',
       'replace_supply_need_v1'
     )),
  'los tres comandos son sólo para el ERP autenticado'
);
select ok(
  (select bool_and(proc.prosecdef)
   from pg_proc proc
   join pg_namespace namespace on namespace.oid = proc.pronamespace
   where namespace.nspname = 'public'
     and proc.proname in (
       'set_supply_need_quantity_v1',
       'refine_supply_need_v1',
       'replace_supply_need_v1'
     )),
  'y corren como definer con su search_path fijo'
);
select has_function(
  'public', 'record_supplier_need_portal_search_v1',
  array['uuid', 'uuid', 'text', 'text', 'text', 'jsonb', 'jsonb', 'jsonb',
        'bigint', 'bigint', 'uuid', 'text'],
  'el recibo del portal recibe la estampa capturada'
);
select has_function(
  'public', 'record_supplier_need_portal_search_v1',
  array['uuid', 'uuid', 'text', 'text', 'text', 'jsonb', 'jsonb'],
  'la firma del cliente instalado sigue existiendo, como no-op'
);
select ok(
  (select bool_and(not proc.prosecdef)
   from pg_proc proc
   join pg_namespace namespace on namespace.oid = proc.pronamespace
   where namespace.nspname = 'public'
     and proc.proname = 'record_supplier_need_portal_search_v1'
     and proc.pronargs in (7, 8)),
  'las firmas heredadas no corren como definer: no tienen nada que escribir'
);

select * from finish();

rollback;
