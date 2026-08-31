begin;

select no_plan();

-- Cobertura del catálogo: existe, está separada del estado, no se puede mentir
-- con ella, y el caché de taxonomía es del servidor.
--
-- **Esta prueba siembra lo suyo.** La versión anterior afirmaba sobre la fila
-- real de RBX y pasaba o fallaba según qué datos tuviera la base donde
-- corriera: en local, con cero filas en `supplier_portal_probes`, no probaba
-- nada. La afirmación sobre la fila sembrada vive ahora en el read-back de
-- producción, que es donde esa pregunta tiene sentido.

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------

select has_column(
  'public', 'supplier_portal_probes', 'catalog_taxonomy',
  'a portal can keep the taxonomy that was discovered for it'
);
select has_column(
  'public', 'supplier_portal_probes', 'catalog_taxonomy_discovered_at',
  'a cached taxonomy carries when it was read, so it can expire'
);
select has_column(
  'public', 'supplier_need_portal_searches', 'coverage',
  'how much of the catalogue was enumerated is its own fact'
);
select has_function(
  'public', 'record_supplier_portal_catalog_taxonomy_v1',
  array['uuid', 'jsonb'],
  'the guarded taxonomy write exists'
);
select has_function(
  'public', 'record_supplier_need_portal_search_v1',
  array['uuid', 'uuid', 'text', 'text', 'text', 'jsonb', 'jsonb', 'jsonb',
        'bigint', 'bigint', 'uuid', 'text'],
  'the receipt accepts coverage and the captured interpretation stamp'
);
select has_trigger(
  'public', 'supplier_portal_probes',
  'supplier_portal_probes_guard_catalog_cache',
  'the server-owned cache columns are guarded on the table itself'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.record_supplier_portal_catalog_taxonomy_v1(uuid,jsonb)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.record_supplier_portal_catalog_taxonomy_v1(uuid,jsonb)',
    'execute'
  ),
  'only the authenticated ERP can persist a discovered taxonomy'
);
-- El disparador es `security invoker` a propósito: con `security definer` el
-- `current_user` sería su propio dueño y la comprobación se auto-aprobaría.
select ok(
  (select not prosecdef
   from pg_proc proc
   join pg_namespace namespace on namespace.oid = proc.pronamespace
   where namespace.nspname = 'public'
     and proc.proname = 'supplier_portal_probes_guard_catalog_cache'),
  'the cache guard runs as the caller, or it would approve itself'
);

-- ---------------------------------------------------------------------------
-- Semilla propia
-- ---------------------------------------------------------------------------

insert into public.tenants (id, shop_name, owner_email, timezone)
values (
  'c0be0000-0000-4000-8000-000000000001', 'Coverage tenant',
  'coverage@example.invalid', 'America/Santiago'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'c0be0000-0000-4000-8000-000000000011', 'authenticated', 'authenticated',
  'coverage-buyer@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
  now(), now()
);

insert into public.user_profiles (user_id, tenant_id, role, permissions)
values (
  'c0be0000-0000-4000-8000-000000000011',
  'c0be0000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb
);

insert into public.suppliers (id, tenant_id, name)
values
  ('c0be0000-0000-4000-8000-000000000021',
   'c0be0000-0000-4000-8000-000000000001', 'Coverage portal supplier'),
  ('c0be0000-0000-4000-8000-000000000022',
   'c0be0000-0000-4000-8000-000000000001', 'Coverage other supplier');

insert into public.supplier_portal_probes (
  tenant_id, supplier_id, search_url_template, is_enabled,
  need_search_url_template, need_search_term_limit, need_search_adapter
) values (
  'c0be0000-0000-4000-8000-000000000001',
  'c0be0000-0000-4000-8000-000000000021',
  'https://portal.example.invalid/buscar?codigo={code}',
  true,
  'https://portal.example.invalid/buscar?palabra={query}',
  15,
  jsonb_build_object(
    'version', 1,
    -- Sólo-genérico, sin `families` ni `categories`: es el caso que el CHECK
    -- anterior rechazaba y que el adaptador Dart siempre aceptó.
    'generic_family_search', true,
    'result_cap', 2,
    'catalog_route', jsonb_build_object(
      'url_template',
        'https://portal.example.invalid/cat?n={node}&p={page}&s={page_size}',
      'page_size', 9
    ),
    'taxonomy_discovery', jsonb_build_object(
      'url', 'https://portal.example.invalid/seleccion',
      'parent_field', 'Clasificacion1',
      'child_field', 'Clasificacion2'
    )
  )
);

insert into public.supply_needs (
  id, tenant_id, origin_kind, original_description, quantity
) values (
  'c0be0000-0000-4000-8000-000000000031',
  'c0be0000-0000-4000-8000-000000000001', 'ad_hoc',
  'Cámaras aro 700 para reposición del taller', 3
);

-- Un recibo de portal se estampa con la revisión y el alcance vigentes, así
-- que una necesidad SIN interpretación resuelta no puede registrar búsquedas.
-- La semilla lo refleja en vez de esquivarlo.
insert into public.product_categories (id, tenant_id, name, full_path)
values (
  'c0be0000-0000-4000-8000-000000000051',
  'c0be0000-0000-4000-8000-000000000001', 'Cámaras',
  'Componentes / Ruedas / Cámaras'
);

insert into public.supply_need_interpretation_revisions (
  tenant_id, supply_need_id, revision_no, source, raw_description,
  identity_state, category_id, constraints, formula_version,
  continuity, technical_family
) values (
  'c0be0000-0000-4000-8000-000000000001',
  'c0be0000-0000-4000-8000-000000000031', 1, 'ai',
  'Cámaras aro 700 para reposición del taller', 'unresolved',
  'c0be0000-0000-4000-8000-000000000051',
  '[{"field":"wheel_size","operator":"eq","values":["700c"]}]'::jsonb,
  'assistant-v1', 'initial', 'tube'
);

-- ---------------------------------------------------------------------------
-- El CHECK real de la tabla, no una copia en una tabla temporal
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into public.supplier_need_portal_searches (
      tenant_id, supplier_id, supply_need_id, search_query, status, coverage
      , need_version_at_search, interpretation_revision_no,
      interpretation_category_id, interpretation_technical_family
    ) values (
      'c0be0000-0000-4000-8000-000000000001',
      'c0be0000-0000-4000-8000-000000000021',
      'c0be0000-0000-4000-8000-000000000031',
      'camara', 'completed',
      '{"method":"taxonomy","complete":true,"limit":"session_expired"}'::jsonb,
      1, 1, 'c0be0000-0000-4000-8000-000000000051', 'tube'
    )$$,
  '23514',
  null,
  'an expired session can never be stored as a complete catalogue'
);
select lives_ok(
  $$insert into public.supplier_need_portal_searches (
      tenant_id, supplier_id, supply_need_id, search_query, status, coverage
      , need_version_at_search, interpretation_revision_no,
      interpretation_category_id, interpretation_technical_family
    ) values (
      'c0be0000-0000-4000-8000-000000000001',
      'c0be0000-0000-4000-8000-000000000021',
      'c0be0000-0000-4000-8000-000000000031',
      'camara', 'completed',
      '{"method":"taxonomy","complete":true,"limit":"enumerated"}'::jsonb,
      1, 1, 'c0be0000-0000-4000-8000-000000000051', 'tube'
    )$$,
  'an enumeration that finished may declare a complete catalogue'
);

-- ---------------------------------------------------------------------------
-- Escritura forjada: el rol del API no puede tocar el caché
--
-- `supplier_portal_probes` concede DML completo a `anon` y `authenticated` y su
-- política es `for all` por tenant. Sin el disparador, cualquier usuario del
-- tenant escribe estas columnas por PostgREST sin pasar por el recibo.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'c0be0000-0000-4000-8000-000000000011',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'c0be0000-0000-4000-8000-000000000011', true);
set local role authenticated;

-- Sin esto, un UPDATE de cero filas «pasaría» sin disparar nada y la
-- regresión de abajo sería verde en el vacío.
select is(
  (select count(*)::int from public.supplier_portal_probes
   where supplier_id = 'c0be0000-0000-4000-8000-000000000021'),
  1,
  'the seeded probe row is visible to the authenticated tenant user'
);

-- Compatibilidad: la edición de configuración de siempre sigue funcionando.
select lives_ok(
  $$update public.supplier_portal_probes
    set need_search_term_limit = 20
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  'a legitimate config edit is untouched by the cache guard'
);

select throws_ok(
  $$update public.supplier_portal_probes
    set catalog_taxonomy = '{"nodes":[{"id":"666","label":"FORJADO"}],'
      '"fingerprint":"deadbeef"}'::jsonb
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  '42501',
  'catalog_taxonomy is written only through record_supplier_portal_catalog_taxonomy_v1',
  'the API role cannot forge the taxonomy cache with a direct write'
);

select throws_ok(
  $$update public.supplier_portal_probes
    set catalog_taxonomy_discovered_at = now() + interval '10 years'
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  '42501',
  'catalog_taxonomy is written only through record_supplier_portal_catalog_taxonomy_v1',
  'the API role cannot future-date the cache to stop rediscovery'
);

select throws_ok(
  $$insert into public.supplier_portal_probes (
      tenant_id, supplier_id, search_url_template, is_enabled, catalog_taxonomy
    ) values (
      'c0be0000-0000-4000-8000-000000000001',
      'c0be0000-0000-4000-8000-000000000021',
      'https://portal.example.invalid/otro?codigo={code}', true,
      '{"nodes":[{"id":"1","label":"X"}],"fingerprint":"aa"}'::jsonb
    )$$,
  '42501',
  'catalog_taxonomy is written only through record_supplier_portal_catalog_taxonomy_v1',
  'the cache cannot be planted through an insert either'
);

-- El camino legítimo sí pasa por el mismo disparador.
select lives_ok(
  $$select public.record_supplier_portal_catalog_taxonomy_v1(
      'c0be0000-0000-4000-8000-000000000021',
      '{"nodes":[{"id":"171","label":"CAMARAS RUTA"}],'
      '"fingerprint":"abc12345"}'::jsonb
    )$$,
  'the guarded receipt writes the cache the direct path cannot'
);

-- ---------------------------------------------------------------------------
-- Un caché no sobrevive al cambio de identidad ni de ruta
--
-- La taxonomía la produjo un proveedor concreto leyendo una ruta concreta. Si
-- cambia el proveedor o el adaptador, lo guardado describe otra cosa: dejarlo
-- vigente lo haría heredable, y el ERP enumeraría nodos que ya no existen.
-- ---------------------------------------------------------------------------

-- Punto de partida: hay caché vigente, escrito por el camino legítimo.
select isnt(
  (select catalog_taxonomy from public.supplier_portal_probes
   where supplier_id = 'c0be0000-0000-4000-8000-000000000021'),
  null,
  'the guarded write left a live cache to invalidate'
);

-- Una edición inocua NO lo borra: invalidar de más obligaría a redescubrir el
-- catálogo entero cada vez que alguien corrige una nota.
select lives_ok(
  $$update public.supplier_portal_probes
    set notes = 'contacto nuevo del vendedor'
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  'an innocuous config edit is allowed'
);
select isnt(
  (select catalog_taxonomy from public.supplier_portal_probes
   where supplier_id = 'c0be0000-0000-4000-8000-000000000021'),
  null,
  'an innocuous config edit keeps the cache'
);

-- Cambiar el adaptador cambia dónde se lee la taxonomía y cómo se recorre.
select lives_ok(
  $$update public.supplier_portal_probes
    set need_search_adapter = need_search_adapter
      || '{"taxonomy_discovery":{"url":"https://portal.example.invalid/otra",'
         '"parent_field":"C1","child_field":"C2"}}'::jsonb
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  'changing the adapter is a legitimate config edit'
);
select is(
  (select catalog_taxonomy from public.supplier_portal_probes
   where supplier_id = 'c0be0000-0000-4000-8000-000000000021'),
  null,
  'changing the route invalidates the cache it produced'
);
select is(
  (select catalog_taxonomy_discovered_at from public.supplier_portal_probes
   where supplier_id = 'c0be0000-0000-4000-8000-000000000021'),
  null,
  'the discovery stamp goes with the cache it dated'
);

-- Y lo mismo con la identidad: un caché no se hereda por otro proveedor.
select lives_ok(
  $$select public.record_supplier_portal_catalog_taxonomy_v1(
      'c0be0000-0000-4000-8000-000000000021',
      '{"nodes":[{"id":"171","label":"CAMARAS RUTA"}],'
      '"fingerprint":"abc12345"}'::jsonb
    )$$,
  'the cache is written again through the receipt'
);
select lives_ok(
  $$update public.supplier_portal_probes
    set supplier_id = 'c0be0000-0000-4000-8000-000000000022'
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  'repointing a probe at another supplier is allowed'
);
select is(
  (select catalog_taxonomy from public.supplier_portal_probes
   where supplier_id = 'c0be0000-0000-4000-8000-000000000022'),
  null,
  'a live cache is never inherited by another supplier'
);

-- Se devuelve el portal a su proveedor y se repone el caché para lo que sigue.
select lives_ok(
  $$update public.supplier_portal_probes
    set supplier_id = 'c0be0000-0000-4000-8000-000000000021'
    where supplier_id = 'c0be0000-0000-4000-8000-000000000022'$$,
  'the fixture probe goes back to its supplier'
);
select lives_ok(
  $$select public.record_supplier_portal_catalog_taxonomy_v1(
      'c0be0000-0000-4000-8000-000000000021',
      '{"nodes":[{"id":"171","label":"CAMARAS RUTA"}],'
      '"fingerprint":"abc12345",'
      '"discoveredAt":"2099-01-01T00:00:00Z"}'::jsonb
    )$$,
  'the receipt writes the cache the direct path cannot'
);

-- ---------------------------------------------------------------------------
-- El tope de filas sale del adaptador (reemplaza la afirmación sobre RBX)
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select public.record_supplier_need_portal_search_v1(
      'c0be0000-0000-4000-8000-000000000021',
      'c0be0000-0000-4000-8000-000000000031',
      'camara', 'completed', null,
      jsonb_build_array(
        jsonb_build_object('code','1','name','A','matchState','exact'),
        jsonb_build_object('code','2','name','B','matchState','exact'),
        jsonb_build_object('code','3','name','C','matchState','exact')
      ),
      '{}'::jsonb, '{}'::jsonb,
      1, 1, 'c0be0000-0000-4000-8000-000000000051', 'tube'
    )$$,
  '22023',
  'Invalid need portal search',
  'the receipt refuses more rows than the adapter told the client to send'
);
select lives_ok(
  $$select public.record_supplier_need_portal_search_v1(
      'c0be0000-0000-4000-8000-000000000021',
      'c0be0000-0000-4000-8000-000000000031',
      'camara', 'completed', null,
      jsonb_build_array(
        jsonb_build_object('code','1','name','A','matchState','exact'),
        jsonb_build_object('code','2','name','B','matchState','exact')
      ),
      '{}'::jsonb,
      '{"method":"taxonomy","complete":true,"limit":"enumerated"}'::jsonb,
      1, 1, 'c0be0000-0000-4000-8000-000000000051', 'tube'
    )$$,
  'a payload within the adapter cap is accepted with its coverage'
);
select throws_ok(
  $$select public.record_supplier_need_portal_search_v1(
      'c0be0000-0000-4000-8000-000000000021',
      'c0be0000-0000-4000-8000-000000000031',
      'camara', 'completed', null, '[]'::jsonb, '{}'::jsonb,
      '{"method":"word_search","complete":true,"limit":"word_search_only"}'::jsonb,
      1, 1, 'c0be0000-0000-4000-8000-000000000051', 'tube'
    )$$,
  '22023',
  'Coverage cannot claim a complete catalogue',
  'the word search can never claim it saw the whole catalogue'
);

reset role;

-- ---------------------------------------------------------------------------
-- La hora del descubrimiento es del servidor, de punta a punta
-- ---------------------------------------------------------------------------

select ok(
  (select catalog_taxonomy_discovered_at
   from public.supplier_portal_probes
   where supplier_id = 'c0be0000-0000-4000-8000-000000000021')
  between now() - interval '1 minute' and now() + interval '1 minute',
  'the stored discovery column is stamped by the server, not by the caller'
);
select ok(
  (select (catalog_taxonomy ->> 'discoveredAt')::timestamptz
   from public.supplier_portal_probes
   where supplier_id = 'c0be0000-0000-4000-8000-000000000021')
  < now() + interval '1 minute',
  'a caller cannot future-date the cached taxonomy to stop rediscovery'
);
select isnt(
  (select catalog_taxonomy ->> 'discoveredAt'
   from public.supplier_portal_probes
   where supplier_id = 'c0be0000-0000-4000-8000-000000000021'),
  '2099-01-01T00:00:00Z',
  'the client-authored discovery time is discarded, not stored'
);
select is(
  (select catalog_taxonomy ->> 'fingerprint'
   from public.supplier_portal_probes
   where supplier_id = 'c0be0000-0000-4000-8000-000000000021'),
  'abc12345',
  'everything else the caller sent is kept as discovered'
);

-- ---------------------------------------------------------------------------
-- El CHECK del adaptador acepta lo que el cliente acepta, y nada más
--
-- Va al final a propósito: cada uno de estos UPDATE cambia el adaptador, y eso
-- invalida el caché. Antes de las aserciones de la hora del servidor dejaría
-- esas lecturas en null y la prueba mediría el orden, no la regla.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$update public.supplier_portal_probes
    set need_search_adapter =
      '{"version":"1","generic_family_search":true}'::jsonb
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  'a portal that only publishes its word search is configurable'
);
select throws_ok(
  $$update public.supplier_portal_probes
    set need_search_adapter = '{"version":"1"}'::jsonb
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  '23514',
  null,
  'an adapter that declares no capability at all is refused'
);
select throws_ok(
  $$update public.supplier_portal_probes
    set need_search_adapter = '{}'::jsonb
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  '23514',
  null,
  'an adapter without a version is refused instead of passing on a NULL'
);
select throws_ok(
  $$update public.supplier_portal_probes
    set need_search_adapter =
      '{"version":"1","generic_family_search":"true"}'::jsonb
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  '23514',
  null,
  'the generic flag counts only as a real boolean, never as a string'
);
select throws_ok(
  $$update public.supplier_portal_probes
    set need_search_adapter =
      '{"version":"2","generic_family_search":true}'::jsonb
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  '23514',
  null,
  'an unknown adapter version is refused'
);
select throws_ok(
  $$update public.supplier_portal_probes
    set need_search_adapter = '{"version":"1","families":[]}'::jsonb
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  '23514',
  null,
  'families must be an object, not merely present'
);

-- **Presente no es lo mismo que declarado.** Un mapa vacío pasa el chequeo de
-- tipo, pero el adaptador Dart lo lee vacío y lanza `FormatException`, que
-- apaga la capacidad en silencio: el portal queda «configurado» y no busca
-- nada. La base no puede aceptar lo que el cliente ignora.
select throws_ok(
  $$update public.supplier_portal_probes
    set need_search_adapter = '{"version":"1","families":{}}'::jsonb
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  '23514',
  null,
  'an empty families map is not a declared capability'
);
select throws_ok(
  $$update public.supplier_portal_probes
    set need_search_adapter = '{"version":"1","categories":{}}'::jsonb
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  '23514',
  null,
  'an empty categories map is not a declared capability either'
);
select throws_ok(
  $$update public.supplier_portal_probes
    set need_search_adapter =
      '{"version":"1","families":{},"categories":{}}'::jsonb
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  '23514',
  null,
  'two empty maps do not add up to one capability'
);

-- El caso legítimo sigue entrando: una familia de verdad, sin flag genérico.
select lives_ok(
  $$update public.supplier_portal_probes
    set need_search_adapter =
      '{"version":"1","families":{"tube":{"identity_family":"tube",'
      '"search_terms":["camara"]}}}'::jsonb
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  'a real configured family is still accepted without the generic flag'
);
-- Y un mapa vacío acompañado del flag genérico también: la capacidad la
-- declara el flag, no el mapa.
select lives_ok(
  $$update public.supplier_portal_probes
    set need_search_adapter =
      '{"version":"1","families":{},"generic_family_search":true}'::jsonb
    where supplier_id = 'c0be0000-0000-4000-8000-000000000021'$$,
  'an empty map rides along when the generic flag carries the capability'
);

select * from finish();

rollback;
