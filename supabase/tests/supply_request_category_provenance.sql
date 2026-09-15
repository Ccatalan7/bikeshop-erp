begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Fase A — la categoría sobrevive a la captura, con su autoridad clara.
--
-- Lo que estas pruebas defienden no es un formato sino tres fronteras:
--   · la ficha exacta manda sobre la categoría y el modelo no puede
--     contradecirla;
--   · una categoría de otro tenant o retirada no existe para este taller;
--   · un predicado de una línea sin producto exige fundamento completo:
--     categoría resuelta, plantilla activa y pertenencia a esa plantilla. Sin
--     mapeo o sin plantilla la línea sobrevive, pero sólo con predicados
--     vacíos: no hay repliegue a `is_filterable` global.

select has_function(
  'public', 'assistant_inspect_inventory_schema_v3',
  array['text', 'text'],
  'the inspector publishes the category identity it already resolved'
);
select has_function(
  'public', 'supply_request_category_scope_internal_v1',
  array['uuid', 'uuid'],
  'category scope resolution is one tenant-bound server function'
);
select has_function(
  'public', 'normalize_supply_request_items_internal_v2',
  array['uuid', 'jsonb'],
  'draft normalization carries category provenance'
);
select has_function(
  'public', 'assistant_prepare_supply_request_v2',
  array['jsonb', 'text'],
  'the read-only draft projection has a category-aware version'
);
select has_function(
  'public', 'create_supply_need_batch_v2',
  array['text', 'jsonb', 'text', 'uuid', 'text'],
  'the durable batch command has a category-aware version'
);

-- v1 sigue existiendo: forward-only no significa romper a quien no migró.
select has_function(
  'public', 'assistant_prepare_supply_request_v1',
  array['jsonb', 'text'],
  'the previous draft projection stays callable'
);
select has_function(
  'public', 'create_supply_need_batch_v1',
  array['text', 'jsonb', 'text', 'uuid', 'text'],
  'the previous batch command stays callable'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.assistant_inspect_inventory_schema_v3(text,text)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.assistant_inspect_inventory_schema_v3(text,text)',
    'execute'
  ),
  'only an authenticated session can inspect the catalog schema'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.supply_request_category_scope_internal_v1(uuid,uuid)',
    'execute'
  ),
  'category scope resolution is internal and never client-callable'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.normalize_supply_request_items_internal_v2(uuid,jsonb)',
    'execute'
  ),
  'draft normalization is internal and never client-callable'
);

-- ───────────────────────────── datos de prueba ─────────────────────────────
insert into public.tenants(id, shop_name, currency, timezone) values
  (
    '99c30000-0000-4000-8000-000000000001',
    'Category Provenance Tenant', 'CLP', 'America/Santiago'
  ),
  (
    '99c30000-0000-4000-8000-000000000002',
    'Foreign Tenant', 'CLP', 'America/Santiago'
  );

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99c30000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'category-provenance@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(
  user_id, tenant_id, role, permissions, is_active
) values (
  '99c30000-0000-4000-8000-000000000099',
  '99c30000-0000-4000-8000-000000000001',
  'admin', '{}'::jsonb, true
);

insert into public.product_categories(
  id, tenant_id, name, full_path, level, is_active
) values
  (
    '99c30000-0000-4000-8000-000000000011',
    '99c30000-0000-4000-8000-000000000001',
    'Cadenas', 'Transmisión / Cadenas', 1, true
  ),
  (
    '99c30000-0000-4000-8000-000000000012',
    '99c30000-0000-4000-8000-000000000001',
    'Retirada', 'Transmisión / Retirada', 1, false
  ),
  (
    '99c30000-0000-4000-8000-000000000013',
    '99c30000-0000-4000-8000-000000000002',
    'Cadenas Ajenas', 'Transmisión / Cadenas Ajenas', 1, true
  ),
  -- Categoría real del tenant y **sin** `category_tech_mappings`: es el taller
  -- que todavía no mapeó su árbol.
  (
    '99c30000-0000-4000-8000-000000000014',
    '99c30000-0000-4000-8000-000000000001',
    'Sin Mapear', 'Transmisión / Sin Mapear', 1, true
  );

insert into public.spec_definitions(
  id, tenant_id, key, label, data_type, is_filterable
) values
  (
    '99c30000-0000-4000-8000-000000000021',
    '99c30000-0000-4000-8000-000000000001',
    'chain_speeds', 'Velocidades', 'number', true
  ),
  -- Filtrable y del mismo tenant, pero **ajena a la plantilla** de Cadenas:
  -- ésta es la que la Fase A tiene que rechazar en una línea sin producto.
  (
    '99c30000-0000-4000-8000-000000000022',
    '99c30000-0000-4000-8000-000000000001',
    'tire_width', 'Ancho de neumático', 'number', true
  );

insert into public.spec_templates(
  id, tenant_id, key, name, technical_family, is_active
) values (
  '99c30000-0000-4000-8000-000000000031',
  '99c30000-0000-4000-8000-000000000001',
  'chain_template', 'Cadenas', 'chain', true
);
insert into public.spec_template_fields(
  id, tenant_id, template_id, spec_definition_id
) values (
  '99c30000-0000-4000-8000-000000000041',
  '99c30000-0000-4000-8000-000000000001',
  '99c30000-0000-4000-8000-000000000031',
  '99c30000-0000-4000-8000-000000000021'
);
insert into public.category_tech_mappings(
  id, tenant_id, category_id, technical_family, template_id, status
) values (
  '99c30000-0000-4000-8000-000000000051',
  '99c30000-0000-4000-8000-000000000001',
  '99c30000-0000-4000-8000-000000000011',
  'chain',
  '99c30000-0000-4000-8000-000000000031',
  'active'
);

insert into public.products(
  id, tenant_id, name, sku, category_id, is_active, price
) values (
  '99c30000-0000-4000-8000-000000000061',
  '99c30000-0000-4000-8000-000000000001',
  'Cadena KMC X10 116L', 'KMC-X10-116',
  '99c30000-0000-4000-8000-000000000011', true, 19990
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99c30000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99c30000-0000-4000-8000-000000000099',
  true
);

-- ────────────────────── resolución de ámbito de categoría ──────────────────
select is(
  (
    select scope.technical_family
    from public.supply_request_category_scope_internal_v1(
      '99c30000-0000-4000-8000-000000000001',
      '99c30000-0000-4000-8000-000000000011'
    ) scope
  ),
  'chain',
  'the technical family is derived from the mapping, never stored'
);

select throws_ok(
  $$select * from public.supply_request_category_scope_internal_v1(
      '99c30000-0000-4000-8000-000000000001',
      '99c30000-0000-4000-8000-000000000013'
    )$$,
  '23514',
  'Supply request category is unavailable',
  'another tenant category does not exist for this shop'
);
select throws_ok(
  $$select * from public.supply_request_category_scope_internal_v1(
      '99c30000-0000-4000-8000-000000000001',
      '99c30000-0000-4000-8000-000000000012'
    )$$,
  '23514',
  'Supply request category is unavailable',
  'a retired category cannot govern a new need'
);
select throws_ok(
  $$select * from public.supply_request_category_scope_internal_v1(
      '99c30000-0000-4000-8000-000000000001',
      '99c30000-0000-4000-8000-0000000000ff'
    )$$,
  '23514',
  'Supply request category is unavailable',
  'an invented category identity resolves to nothing'
);

-- ─────────────────────────── normalización del borrador ────────────────────
select is(
  (
    select item.value ->> 'categoryPath'
    from jsonb_array_elements(
      public.normalize_supply_request_items_internal_v2(
        '99c30000-0000-4000-8000-000000000001',
        jsonb_build_array(jsonb_build_object(
          'lineRef', 'line-1',
          'description', 'Cadena de 10 velocidades',
          'productId', null,
          'categoryId', '99c30000-0000-4000-8000-000000000011',
          'quantity', 1,
          'unit', 'unit',
          'technicalPredicates', jsonb_build_array(jsonb_build_object(
            'field', 'chain_speeds', 'operator', 'eq',
            'values', jsonb_build_array(10)
          )),
          'preference', null,
          'clarification', null,
          'clarificationRequired', false
        ))
      )
    ) item
  ),
  'Transmisión / Cadenas',
  'a line without a product keeps the model-resolved category'
);

select is(
  (
    select item.value ->> 'categoryId'
    from jsonb_array_elements(
      public.normalize_supply_request_items_internal_v2(
        '99c30000-0000-4000-8000-000000000001',
        jsonb_build_array(jsonb_build_object(
          'lineRef', 'line-1',
          'description', 'Cadena KMC X10',
          'productId', '99c30000-0000-4000-8000-000000000061',
          'categoryId', null,
          'quantity', 1,
          'unit', 'unit',
          'technicalPredicates', '[]'::jsonb,
          'preference', null,
          'clarification', null,
          'clarificationRequired', false
        ))
      )
    ) item
  ),
  '99c30000-0000-4000-8000-000000000011',
  'an exact product derives its own category server-side'
);

select throws_ok(
  $$select public.normalize_supply_request_items_internal_v2(
      '99c30000-0000-4000-8000-000000000001',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1',
        'description', 'Cadena KMC X10',
        'productId', '99c30000-0000-4000-8000-000000000061',
        'categoryId', '99c30000-0000-4000-8000-000000000012',
        'quantity', 1,
        'unit', 'unit',
        'technicalPredicates', '[]'::jsonb,
        'preference', null,
        'clarification', null,
        'clarificationRequired', false
      ))
    )$$,
  '23514',
  'Catalog product does not belong to the requested category',
  'the exact catalog product outranks a contradicting category'
);

select throws_ok(
  $$select public.normalize_supply_request_items_internal_v2(
      '99c30000-0000-4000-8000-000000000001',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1',
        'description', 'Cadena de 10 velocidades',
        'productId', null,
        'categoryId', '99c30000-0000-4000-8000-000000000011',
        'quantity', 1,
        'unit', 'unit',
        'technicalPredicates', jsonb_build_array(jsonb_build_object(
          'field', 'tire_width', 'operator', 'gt',
          'values', jsonb_build_array(2)
        )),
        'preference', null,
        'clarification', null,
        'clarificationRequired', false
      ))
    )$$,
  '23514',
  'Technical predicate does not belong to the category template',
  'a filterable field from another family cannot bound this category'
);

select throws_ok(
  $$select public.normalize_supply_request_items_internal_v2(
      '99c30000-0000-4000-8000-000000000001',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1',
        'description', 'Cadena de 10 velocidades',
        'productId', null,
        'categoryId', '99c30000-0000-4000-8000-000000000013',
        'quantity', 1,
        'unit', 'unit',
        'technicalPredicates', '[]'::jsonb,
        'preference', null,
        'clarification', null,
        'clarificationRequired', false
      ))
    )$$,
  '23514',
  'Supply request category is unavailable',
  'a foreign-tenant category is unreachable through the draft'
);

-- ─────────────────── corte duro: ningún criterio sin fundamento ────────────
select throws_ok(
  $$select public.normalize_supply_request_items_internal_v2(
      '99c30000-0000-4000-8000-000000000001',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1',
        'description', 'Algo con 10 velocidades',
        'productId', null,
        'categoryId', null,
        'quantity', 1,
        'unit', 'unit',
        'technicalPredicates', jsonb_build_array(jsonb_build_object(
          'field', 'chain_speeds', 'operator', 'eq',
          'values', jsonb_build_array(10)
        )),
        'preference', null,
        'clarification', null,
        'clarificationRequired', false
      ))
    )$$,
  '23514',
  'Technical predicates require a resolved category',
  'a predicate without a category has nothing backing it'
);

select throws_ok(
  $$select public.normalize_supply_request_items_internal_v2(
      '99c30000-0000-4000-8000-000000000001',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1',
        'description', 'Pieza sin plantilla',
        'productId', null,
        'categoryId', '99c30000-0000-4000-8000-000000000014',
        'quantity', 1,
        'unit', 'unit',
        'technicalPredicates', jsonb_build_array(jsonb_build_object(
          'field', 'chain_speeds', 'operator', 'eq',
          'values', jsonb_build_array(10)
        )),
        'preference', null,
        'clarification', null,
        'clarificationRequired', false
      ))
    )$$,
  '23514',
  'Technical predicates require an active category template',
  'a category the tenant never mapped cannot bound a technical criterion'
);

select is(
  (
    select item.value ->> 'categoryId'
    from jsonb_array_elements(
      public.normalize_supply_request_items_internal_v2(
        '99c30000-0000-4000-8000-000000000001',
        jsonb_build_array(jsonb_build_object(
          'lineRef', 'line-1',
          'description', 'Pieza sin plantilla',
          'productId', null,
          'categoryId', '99c30000-0000-4000-8000-000000000014',
          'quantity', 1,
          'unit', 'unit',
          'technicalPredicates', '[]'::jsonb,
          'preference', null,
          'clarification', null,
          'clarificationRequired', false
        ))
      )
    ) item
  ),
  '99c30000-0000-4000-8000-000000000014',
  'the need and its category survive without a template; only criteria do not'
);

select throws_ok(
  $$select public.normalize_supply_request_items_internal_v2(
      '99c30000-0000-4000-8000-000000000001',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1',
        'description', 'Cadena de 10 velocidades',
        'productId', null,
        'categoryId', 'no-es-un-uuid',
        'quantity', 1,
        'unit', 'unit',
        'technicalPredicates', '[]'::jsonb,
        'preference', null,
        'clarification', null,
        'clarificationRequired', false
      ))
    )$$,
  '22023',
  'Invalid supply request category',
  'a malformed category identity is rejected before any lookup'
);

-- ─────────────────────────── el comando durable ────────────────────────────
select lives_ok(
  $$select public.create_supply_need_batch_v2(
      'Necesito una cadena de 10 velocidades',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1',
        'description', 'Cadena de 10 velocidades',
        'productId', null,
        'categoryId', '99c30000-0000-4000-8000-000000000011',
        'quantity', 1,
        'unit', 'unit',
        'technicalPredicates', jsonb_build_array(jsonb_build_object(
          'field', 'chain_speeds', 'operator', 'eq',
          'values', jsonb_build_array(10)
        )),
        'preference', null,
        'clarification', null,
        'clarificationRequired', false
      )),
      'balanced',
      null,
      'category-provenance-key-1'
    )$$,
  'a reviewed batch with a resolved category is created'
);

select is(
  (
    select revision.category_id
    from public.supply_need_interpretation_revisions revision
    where revision.tenant_id = '99c30000-0000-4000-8000-000000000001'
    order by revision.created_at desc
    limit 1
  ),
  '99c30000-0000-4000-8000-000000000011'::uuid,
  'the durable revision finally fills the category slot the kernel already had'
);

-- La familia derivada no se guarda en ningún sitio durable: ni columna, ni
-- evidencia, ni snapshot de replay. Su dueño responde por ella en cada lectura.
select is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'supply_need_interpretation_revisions'
      and column_name = 'technical_family'
  ),
  0,
  'no technical_family column exists: the family stays derived'
);

select ok(
  not exists (
    select 1
    from public.supply_need_interpretation_revisions revision
    where revision.tenant_id = '99c30000-0000-4000-8000-000000000001'
      and (revision.evidence_snapshot ? 'technical_family'
        or revision.evidence_snapshot ? 'category_path')
  ),
  'derived labels never enter the interpretation evidence'
);

select ok(
  not exists (
    select 1
    from public.supply_need_batch_receipts receipt
    where receipt.tenant_id = '99c30000-0000-4000-8000-000000000001'
      and (receipt.request_snapshot::text like '%technicalFamily%'
        or receipt.request_snapshot::text like '%categoryPath%')
  ),
  'the idempotency snapshot rests on stable identities, not derived labels'
);

select ok(
  not exists (
    select 1
    from public.supply_need_events event
    where event.tenant_id = '99c30000-0000-4000-8000-000000000001'
      and (event.request_snapshot::text like '%technical_family%'
        or event.request_snapshot::text like '%category_path%')
  ),
  'durable events carry the category identity, never its glosses'
);

select ok(
  exists (
    select 1
    from public.supply_need_batch_receipts receipt
    where receipt.tenant_id = '99c30000-0000-4000-8000-000000000001'
      and receipt.request_snapshot::text like '%categoryId%'
  ),
  'the stable category identity does stay in the snapshot'
);

-- El replay devuelve el mismo recibo y no crea una segunda necesidad.
select is(
  (
    select (public.create_supply_need_batch_v2(
      'Necesito una cadena de 10 velocidades',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1',
        'description', 'Cadena de 10 velocidades',
        'productId', null,
        'categoryId', '99c30000-0000-4000-8000-000000000011',
        'quantity', 1,
        'unit', 'unit',
        'technicalPredicates', jsonb_build_array(jsonb_build_object(
          'field', 'chain_speeds', 'operator', 'eq',
          'values', jsonb_build_array(10)
        )),
        'preference', null,
        'clarification', null,
        'clarificationRequired', false
      )),
      'balanced',
      null,
      'category-provenance-key-1'
    ) ->> 'replay')::boolean
  ),
  true,
  'the same operation key replays instead of creating a second need'
);

select is(
  (
    select count(*)::integer
    from public.supply_needs need
    where need.tenant_id = '99c30000-0000-4000-8000-000000000001'
  ),
  1,
  'replay created no extra need'
);

select throws_ok(
  $$select public.create_supply_need_batch_v2(
      'Otra petición distinta',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1',
        'description', 'Cadena de 11 velocidades',
        'productId', null,
        'categoryId', '99c30000-0000-4000-8000-000000000011',
        'quantity', 1,
        'unit', 'unit',
        'technicalPredicates', '[]'::jsonb,
        'preference', null,
        'clarification', null,
        'clarificationRequired', false
      )),
      'balanced',
      null,
      'category-provenance-key-1'
    )$$,
  '23505',
  'La clave de operación pertenece a otra petición.',
  'a reused operation key with a different request is refused'
);

-- Una línea sin categoría sigue siendo válida: la Fase A no obliga a resolver.
select lives_ok(
  $$select public.create_supply_need_batch_v2(
      'Algo que todavía no sé nombrar',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1',
        'description', 'Una pieza rara del cambio trasero',
        'productId', null,
        'categoryId', null,
        'quantity', 1,
        'unit', 'unit',
        'technicalPredicates', '[]'::jsonb,
        'preference', null,
        'clarification', 'Confirma de qué pieza se trata.',
        'clarificationRequired', true
      )),
      'balanced',
      null,
      'category-provenance-key-2'
    )$$,
  'an unresolved line without a category is still a legitimate need'
);

select is(
  (
    select revision.category_id
    from public.supply_need_interpretation_revisions revision
    join public.supply_needs need
      on need.id = revision.supply_need_id
    where revision.tenant_id = '99c30000-0000-4000-8000-000000000001'
      and need.original_description = 'Una pieza rara del cambio trasero'
  ),
  null,
  'nothing is invented when the model could not resolve a category'
);

select * from finish();
rollback;
