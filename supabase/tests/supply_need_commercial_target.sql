begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- La preferencia comercial tipada de una necesidad.
--
-- Lo que estas pruebas defienden:
--   · la moneda es del servidor y no es representable en la entrada;
--   · una marca de otro taller o retirada se rechaza, no se ignora;
--   · el target vive en su propio flujo append-only, así que ningún writer
--     ajeno —el update genérico, la confirmación de familia— puede borrarlo
--     por omisión;
--   · un parche conserva lo que no toca, y limpiar es explícito.

select has_table(
  'public', 'supply_need_commercial_revisions',
  'typed commercial preferences have their own append-only stream'
);
select has_function(
  'public', 'get_supply_need_commercial_target_v1', array['uuid'],
  'the current target is readable'
);
select has_function(
  'public', 'set_supply_need_commercial_target_v1',
  array['uuid', 'bigint', 'bigint', 'jsonb', 'text'],
  'setting and clearing is one replay-safe command'
);
select has_function(
  'public', 'create_supply_need_batch_v3',
  array['text', 'jsonb', 'text', 'uuid', 'text'],
  'capture can create needs and their first target atomically'
);
select has_function(
  'public', 'create_supply_need_batch_v2',
  array['text', 'jsonb', 'text', 'uuid', 'text'],
  'and v2 stays callable, untouched'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.normalize_commercial_target_internal_v1(uuid,jsonb,jsonb)',
    'execute'
  ) and not has_function_privilege(
    'authenticated',
    'public.tenant_commercial_currency_internal_v1(uuid)',
    'execute'
  ),
  'the internal helpers carry no client grant'
);

-- ───────────────────────────── datos de prueba ─────────────────────────────
insert into public.tenants(id, shop_name, currency, timezone) values
  (
    '99a70000-0000-4000-8000-000000000001',
    'Commercial Target Tenant', 'CLP', 'America/Santiago'
  ),
  (
    '99a70000-0000-4000-8000-000000000002',
    'Otro Taller', 'CLP', 'America/Santiago'
  );
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99a70000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'commercial-target@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(
  user_id, tenant_id, role, permissions, is_active
) values (
  '99a70000-0000-4000-8000-000000000099',
  '99a70000-0000-4000-8000-000000000001',
  'admin', '{}'::jsonb, true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99a70000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99a70000-0000-4000-8000-000000000099',
  true
);

-- Cuatro marcas: propia activa, global activa, ajena y retirada.
insert into public.product_brands(id, tenant_id, name, is_active) values
  (
    '99a70000-0000-4000-8000-000000000011',
    '99a70000-0000-4000-8000-000000000001', 'KMC', true
  ),
  ('99a70000-0000-4000-8000-000000000012', null, 'Shimano Global', true),
  (
    '99a70000-0000-4000-8000-000000000013',
    '99a70000-0000-4000-8000-000000000002', 'Marca Ajena', true
  ),
  (
    '99a70000-0000-4000-8000-000000000014',
    '99a70000-0000-4000-8000-000000000001', 'Marca Retirada', false
  );

insert into public.product_categories(
  id, tenant_id, name, full_path, level, is_active
) values (
  '99a70000-0000-4000-8000-000000000021',
  '99a70000-0000-4000-8000-000000000001',
  'Cadenas', 'Transmisión / Cadenas', 1, true
);
insert into public.products(
  id, tenant_id, name, sku, category_id, is_active, price
) values (
  '99a70000-0000-4000-8000-000000000031',
  '99a70000-0000-4000-8000-000000000001',
  'Cadena KMC X10', 'KMC-X10', '99a70000-0000-4000-8000-000000000021',
  true, 19990
);

insert into public.supply_needs(
  id, tenant_id, origin_kind, original_description, product_id, quantity,
  unit, identity_state, supply_state, usage_state, version
) values (
  '99a70000-0000-4000-8000-000000000041',
  '99a70000-0000-4000-8000-000000000001',
  'ad_hoc', 'Cadena de 10 velocidades', null, 2, 'unit',
  'unresolved', 'open', 'not_applicable', 1
);
insert into public.supply_need_interpretation_revisions(
  id, tenant_id, supply_need_id, revision_no, source, raw_description,
  identity_state, category_id, constraints, clarifications, formula_version
) values (
  '99a70000-0000-4000-8000-000000000051',
  '99a70000-0000-4000-8000-000000000001',
  '99a70000-0000-4000-8000-000000000041', 1, 'ai',
  'Necesito una cadena de 10 velocidades, gama económica', 'unresolved',
  '99a70000-0000-4000-8000-000000000021',
  jsonb_build_array(
    jsonb_build_object('kind', 'ranking_profile', 'value', 'balanced'),
    jsonb_build_object('kind', 'commercial_preference',
      'value', 'gama económica pero con buen margen')
  ),
  '[]'::jsonb, 'ai-supply-request-v2'
);

-- ──────────────── la moneda la pone el servidor, siempre ───────────────────
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000041'
  ) ->> 'currencyCode'),
  'CLP',
  'the currency is derived from the tenant, not asked for'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000041'
  ) ->> 'targetRevisionNo')::bigint,
  0::bigint,
  'a need that never had a target reads revision zero, not null'
);
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 1, 0,
      jsonb_build_object('gama', 'economica', 'currencyCode', 'USD'),
      'ct-spoof'
    )$$,
  '22023',
  'La moneda del objetivo comercial la fija el servidor.',
  'a client cannot represent the currency, let alone override it'
);
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 1, 0,
      jsonb_build_object('descuento', 10), 'ct-unknown-key'
    )$$,
  '22023',
  'Campo desconocido en el objetivo comercial: descuento',
  'an unknown field is refused instead of quietly dropped'
);

-- ───────────────────────── la preferencia legada ───────────────────────────
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000041'
  ) -> 'legacyPreferenceNote' ->> 'drivesRanking')::boolean,
  false,
  'the legacy free text is a note and says so: it drives no ranking'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000041'
  ) -> 'legacyPreferenceNote' ->> 'text'),
  'gama económica pero con buen margen',
  'and it travels verbatim, never parsed into a typed field'
);

-- ───────────────────────────── marcas visibles ─────────────────────────────
select lives_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 1, 0,
      jsonb_build_object(
        'preferredBrandId', '99a70000-0000-4000-8000-000000000011'
      ),
      'ct-brand-own'
    )$$,
  'a brand of this tenant is accepted'
);
select lives_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 2, 1,
      jsonb_build_object(
        'preferredBrandId', '99a70000-0000-4000-8000-000000000012'
      ),
      'ct-brand-global'
    )$$,
  'and so is a global brand with no tenant'
);
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 3, 2,
      jsonb_build_object(
        'preferredBrandId', '99a70000-0000-4000-8000-000000000013'
      ),
      'ct-brand-foreign'
    )$$,
  '23514',
  'La marca preferida no está disponible para este taller.',
  'a brand of another shop is refused, not ignored'
);
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 3, 2,
      jsonb_build_object(
        'preferredBrandId', '99a70000-0000-4000-8000-000000000014'
      ),
      'ct-brand-inactive'
    )$$,
  '23514',
  'La marca preferida no está disponible para este taller.',
  'a retired brand is refused too: the operator believes they chose something'
);
select ok(
  not exists (
    select 1 from public.supply_need_commercial_revisions revision
    where revision.tenant_id = '99a70000-0000-4000-8000-000000000001'
      and revision.preferred_brand_id is not null
      and revision.preferred_brand_id not in (
        '99a70000-0000-4000-8000-000000000011',
        '99a70000-0000-4000-8000-000000000012'
      )
  ),
  'no refused brand ever reached the stream'
);
select is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'supply_need_commercial_revisions'
      and column_name in ('brand_name', 'brand', 'category_path', 'gama_label')
  ),
  0,
  'no derived gloss is stored: only durable identities'
);

-- ───────────────────────────── rangos numéricos ────────────────────────────
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 3, 2,
      jsonb_build_object('maxLandedUnitCostNet', 0), 'ct-cost-zero'
    )$$,
  '22023',
  'El tope de costo aterrizado está fuera de rango.',
  'a ceiling of zero is not a preference, it is a mistake'
);
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 3, 2,
      jsonb_build_object('maxLandedUnitCostNet', 1e12), 'ct-cost-huge'
    )$$,
  '22023',
  'El tope de costo aterrizado está fuera de rango.',
  'and a ceiling above a billion is a typo'
);
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 3, 2,
      jsonb_build_object('minGrossMarginRatio', 1.5), 'ct-margin-high'
    )$$,
  '22023',
  'El margen mínimo está fuera de rango.',
  'a margin ratio above one is out of range'
);
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 3, 2,
      jsonb_build_object('minGrossMarginRatio', -0.2), 'ct-margin-negative'
    )$$,
  '22023',
  'El margen mínimo está fuera de rango.',
  'and so is a negative one'
);
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 3, 2,
      '{"maxLandedUnitCostNet": "NaN"}'::jsonb, 'ct-cost-nan'
    )$$,
  '22023',
  'El tope de costo aterrizado debe ser un número.',
  'NaN as a string is not a number'
);
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 3, 2,
      jsonb_build_object('gama', 'premium'), 'ct-gama-invalid'
    )$$,
  '22023',
  'La gama del objetivo comercial no es válida.',
  'the band vocabulary is closed'
);

-- ─────────────────── parche: conserva lo que no toca ───────────────────────
select lives_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 3, 2,
      jsonb_build_object('gama', 'economica', 'maxLandedUnitCostNet', 12000),
      'ct-set-more'
    )$$,
  'a patch adds fields to the existing target'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000041'
  ) -> 'target'),
  jsonb_build_object(
    'preferredBrandId', '99a70000-0000-4000-8000-000000000012',
    'gama', 'economica',
    'maxLandedUnitCostNet', 12000.0000
  ),
  'and the brand set two revisions ago is still there: a patch preserves'
);

-- Limpiar UN campo: la clave presente en null.
select lives_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 4, 3,
      '{"gama": null}'::jsonb, 'ct-clear-gama'
    )$$,
  'an explicit null clears exactly that field'
);
select ok(
  not (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000041'
  ) -> 'target' ? 'gama'),
  'the band is gone'
);
select ok(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000041'
  ) -> 'target') ?& array['preferredBrandId', 'maxLandedUnitCostNet'],
  'and the untouched fields survived'
);

-- No-op: el mismo parche otra vez no escribe nada ni mueve la versión.
select is(
  (
    (public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 5, 4,
      '{"gama": null}'::jsonb, 'ct-noop'
    ) ->> 'changed')::boolean
  ),
  false,
  'clearing what is already clear is a no-op'
);
select is(
  (
    select need.version
    from public.supply_needs need
    where need.id = '99a70000-0000-4000-8000-000000000041'
  ),
  5::bigint,
  'and a no-op does not bump the version: nothing changed'
);
select is(
  (
    select count(*)::integer
    from public.supply_need_commercial_revisions revision
    where revision.supply_need_id = '99a70000-0000-4000-8000-000000000041'
  ),
  4,
  'nor does it append a revision'
);

-- Limpieza TOTAL: target SQL null.
select lives_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 5, 4, null, 'ct-clear-all'
    )$$,
  'a SQL null target clears everything'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000041'
  ) -> 'target'),
  '{}'::jsonb,
  'the target is empty'
);
select is(
  (
    select revision.cleared
    from public.supply_need_commercial_revisions revision
    where revision.supply_need_id = '99a70000-0000-4000-8000-000000000041'
    order by revision.revision_no desc limit 1
  ),
  true,
  'and the stream says it was cleared, not that it never existed'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000041'
  ) ->> 'targetRevisionNo')::bigint,
  5::bigint,
  'a clearing revision still counts: reads must not confuse it with zero'
);

-- ─────────────────── replay, colisión y concurrencia ───────────────────────
select is(
  (
    (public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 5, 4, null, 'ct-clear-all'
    ) ->> 'replay')::boolean
  ),
  true,
  'the same key with the same request replays'
);
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 6, 5,
      jsonb_build_object('gama', 'alta'), 'ct-clear-all'
    )$$,
  '23505',
  'La clave de operación pertenece a otro objetivo comercial.',
  'and the same key with a different request is refused'
);
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 99, 5,
      jsonb_build_object('gama', 'alta'), 'ct-stale-version'
    )$$,
  '40001',
  'La necesidad cambió; vuelve a cargarla antes de fijar el objetivo.',
  'a stale need version is refused'
);
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 6, 99,
      jsonb_build_object('gama', 'alta'), 'ct-stale-target'
    )$$,
  '40001',
  'El objetivo comercial cambió; vuelve a cargarlo.',
  'and so is a stale commercial revision, even with the right need version'
);
select is(
  (
    select need.version
    from public.supply_needs need
    where need.id = '99a70000-0000-4000-8000-000000000041'
  ),
  6::bigint,
  'an effective change bumped the need version to invalidate in-flight reads'
);

-- ─────────── ningún writer ajeno puede borrar el target por omisión ────────
select lives_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 6, 5,
      jsonb_build_object('gama', 'media', 'minGrossMarginRatio', 0.35),
      'ct-before-edits'
    )$$,
  'a target is set before the legacy writers run'
);

-- `update_supply_need_v1` escribe su revisión de interpretación con
-- `constraints '[]'` y sin categoría: si el target viviera ahí, esto lo
-- borraría. Vive en su propio flujo, así que sobrevive.
select lives_ok(
  $$select public.update_supply_need_v1(
      '99a70000-0000-4000-8000-000000000041', 7,
      'Cadena de 10 velocidades, revisada', null, 3, 'unit',
      'El operador corrigió la cantidad.'
    )$$,
  'the generic update command runs'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000041'
  ) -> 'target'),
  jsonb_build_object('gama', 'media', 'minGrossMarginRatio', 0.35000),
  'and the commercial target survived it untouched'
);

-- Confirmar una alternativa de familia tampoco lo toca.
--
-- Va sobre una necesidad aparte a propósito: `update_supply_need_v1` deja la
-- interpretación sin categoría —ése es su defecto conocido, y la razón de que
-- la convergencia sea un comando propio—, así que encadenar las dos en la
-- misma necesidad dejaría el conjunto elegible vacío y la prueba mediría eso
-- en vez del target.
insert into public.supply_needs(
  id, tenant_id, origin_kind, original_description, product_id, quantity,
  unit, identity_state, supply_state, usage_state, version
) values (
  '99a70000-0000-4000-8000-000000000042',
  '99a70000-0000-4000-8000-000000000001',
  'ad_hoc', 'Otra cadena de 10 velocidades', null, 1, 'unit',
  'unresolved', 'open', 'not_applicable', 1
);
insert into public.supply_need_interpretation_revisions(
  id, tenant_id, supply_need_id, revision_no, source, raw_description,
  identity_state, category_id, constraints, clarifications, formula_version
) values (
  '99a70000-0000-4000-8000-000000000052',
  '99a70000-0000-4000-8000-000000000001',
  '99a70000-0000-4000-8000-000000000042', 1, 'ai',
  'Otra cadena de 10 velocidades', 'unresolved',
  '99a70000-0000-4000-8000-000000000021', '[]'::jsonb, '[]'::jsonb,
  'ai-supply-request-v2'
);

select lives_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000042', 1, 0,
      jsonb_build_object('gama', 'alta'), 'ct-before-confirm'
    )$$,
  'a target is set before converging'
);
select lives_ok(
  $$select public.confirm_supply_need_family_choice_v1(
      '99a70000-0000-4000-8000-000000000042', 2, 1,
      '99a70000-0000-4000-8000-000000000031', 'ct-confirm'
    )$$,
  'confirming a family alternative runs'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000042'
  ) -> 'target'),
  jsonb_build_object('gama', 'alta'),
  'and the target survived that too'
);
select is(
  (
    select need.identity_state
    from public.supply_needs need
    where need.id = '99a70000-0000-4000-8000-000000000042'
  ),
  'confirmed',
  'the convergence did happen: this is not a false positive'
);

-- ─────────────────────── captura atómica con v3 ────────────────────────────
select lives_ok(
  $$select public.create_supply_need_batch_v3(
      'Necesito dos cadenas económicas y una cámara cualquiera',
      jsonb_build_array(
        jsonb_build_object(
          'lineRef', 'line-1', 'description', 'Cadena de 10 velocidades',
          'productId', null, 'categoryId', null, 'quantity', 2, 'unit', 'unit',
          'technicalPredicates', '[]'::jsonb, 'preference', null,
          'clarification', null, 'clarificationRequired', false,
          'commercialTarget', jsonb_build_object(
            'gama', 'economica', 'maxLandedUnitCostNet', 9000
          )
        ),
        jsonb_build_object(
          'lineRef', 'line-2', 'description', 'Cámara 27,5',
          'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
          'technicalPredicates', '[]'::jsonb, 'preference', null,
          'clarification', null, 'clarificationRequired', false
        )
      ),
      'balanced', null, 'ct-batch-v3'
    )$$,
  'v3 creates needs and their first commercial target atomically'
);
select is(
  (
    select revision.gama
    from public.supply_need_commercial_revisions revision
    join public.supply_needs need on need.id = revision.supply_need_id
    where need.original_description = 'Cadena de 10 velocidades'
      and need.tenant_id = '99a70000-0000-4000-8000-000000000001'
  ),
  'economica',
  'the line that carried a target has one'
);
select is(
  (
    select count(*)::integer
    from public.supply_need_commercial_revisions revision
    join public.supply_needs need on need.id = revision.supply_need_id
    where need.original_description = 'Cámara 27,5'
  ),
  0,
  'and the line without an actionable target writes no empty revision'
);
select is(
  (
    select (public.get_supply_need_commercial_target_v1(need.id)
      ->> 'targetRevisionNo')::bigint
    from public.supply_needs need
    where need.original_description = 'Cámara 27,5'
      and need.tenant_id = '99a70000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'it still reads revision zero'
);
select is(
  (
    select public.get_supply_need_commercial_target_v1(need.id)
      ->> 'currencyCode'
    from public.supply_needs need
    where need.original_description = 'Cámara 27,5'
      and need.tenant_id = '99a70000-0000-4000-8000-000000000001'
  ),
  'CLP',
  'and still reports the server-owned currency'
);

-- v2 sigue intacta y no escribe nada comercial.
select lives_ok(
  $$select public.create_supply_need_batch_v2(
      'Una necesidad sin objetivo comercial',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1', 'description', 'Pastillas de freno',
        'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
        'technicalPredicates', '[]'::jsonb, 'preference', null,
        'clarification', null, 'clarificationRequired', false
      )),
      'balanced', null, 'ct-batch-v2'
    )$$,
  'v2 still works exactly as before'
);
select is(
  (
    select count(*)::integer
    from public.supply_need_commercial_revisions revision
    join public.supply_needs need on need.id = revision.supply_need_id
    where need.original_description = 'Pastillas de freno'
  ),
  0,
  'and writes nothing into the commercial stream'
);

-- ────────────────────────── aislamiento y evidencia ────────────────────────
select is(
  (
    select revision.currency_code
    from public.supply_need_commercial_revisions revision
    where revision.tenant_id = '99a70000-0000-4000-8000-000000000001'
    order by revision.created_at desc limit 1
  ),
  'CLP',
  'every revision records the shop currency it was denominated in'
);
select is(
  (
    select event.action
    from public.supply_need_events event
    where event.operation_key = 'ct-clear-all'
  ),
  'commercial_target_cleared',
  'clearing is a typed action in the ledger'
);
select is(
  (
    select event.action
    from public.supply_need_events event
    where event.operation_key = 'ct-before-edits'
  ),
  'commercial_target_set',
  'and setting is another'
);
select throws_ok(
  $$update public.supply_need_commercial_revisions
    set gama = 'alta'
    where supply_need_id = '99a70000-0000-4000-8000-000000000041'$$,
  '55000',
  'Supply kernel evidence is append-only',
  'the commercial stream cannot be rewritten'
);

-- ═══════════════ los cinco defectos que la auditoría encontró ══════════════

-- ── 1 · la clave de operación de v3 cubre el objetivo ──────────────────────
select is(
  (
    (public.create_supply_need_batch_v3(
      'Necesito dos cadenas económicas y una cámara cualquiera',
      jsonb_build_array(
        jsonb_build_object(
          'lineRef', 'line-1', 'description', 'Cadena de 10 velocidades',
          'productId', null, 'categoryId', null, 'quantity', 2, 'unit', 'unit',
          'technicalPredicates', '[]'::jsonb, 'preference', null,
          'clarification', null, 'clarificationRequired', false,
          'commercialTarget', jsonb_build_object(
            'gama', 'economica', 'maxLandedUnitCostNet', 9000
          )
        ),
        jsonb_build_object(
          'lineRef', 'line-2', 'description', 'Cámara 27,5',
          'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
          'technicalPredicates', '[]'::jsonb, 'preference', null,
          'clarification', null, 'clarificationRequired', false
        )
      ),
      'balanced', null, 'ct-batch-v3'
    ) ->> 'replay')::boolean
  ),
  true,
  'the exact same v3 request replays'
);
-- El mismo lote con OTRO objetivo: antes v2 replayaba y el `do nothing` se
-- tragaba la diferencia. Ahora es una colisión.
select throws_ok(
  $$select public.create_supply_need_batch_v3(
      'Necesito dos cadenas económicas y una cámara cualquiera',
      jsonb_build_array(
        jsonb_build_object(
          'lineRef', 'line-1', 'description', 'Cadena de 10 velocidades',
          'productId', null, 'categoryId', null, 'quantity', 2, 'unit', 'unit',
          'technicalPredicates', '[]'::jsonb, 'preference', null,
          'clarification', null, 'clarificationRequired', false,
          'commercialTarget', jsonb_build_object('gama', 'alta')
        ),
        jsonb_build_object(
          'lineRef', 'line-2', 'description', 'Cámara 27,5',
          'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
          'technicalPredicates', '[]'::jsonb, 'preference', null,
          'clarification', null, 'clarificationRequired', false
        )
      ),
      'balanced', null, 'ct-batch-v3'
    )$$,
  '23505',
  'La clave de operación pertenece a otra petición.',
  'the same key with a different commercial target is a collision, not a replay'
);
select is(
  (
    select revision.gama
    from public.supply_need_commercial_revisions revision
    join public.supply_needs need on need.id = revision.supply_need_id
    where need.original_description = 'Cadena de 10 velocidades'
      and need.tenant_id = '99a70000-0000-4000-8000-000000000001'
  ),
  'economica',
  'and the refused call left the first target standing'
);
-- Que el target viejo siga visible no basta: se cuentan filas antes y después
-- para que una necesidad o una revisión de más también muerdan.
create temporary table ct_collision_counts on commit drop as
select
  (select count(*) from public.supply_needs
   where tenant_id = '99a70000-0000-4000-8000-000000000001') as needs,
  (select count(*) from public.supply_need_commercial_revisions
   where tenant_id = '99a70000-0000-4000-8000-000000000001') as revisions,
  (select count(*) from public.supply_need_batch_receipts
   where tenant_id = '99a70000-0000-4000-8000-000000000001') as receipts;

select throws_ok(
  $$select public.create_supply_need_batch_v3(
      'Necesito dos cadenas económicas y una cámara cualquiera',
      jsonb_build_array(
        jsonb_build_object(
          'lineRef', 'line-1', 'description', 'Cadena de 10 velocidades',
          'productId', null, 'categoryId', null, 'quantity', 2, 'unit', 'unit',
          'technicalPredicates', '[]'::jsonb, 'preference', null,
          'clarification', null, 'clarificationRequired', false,
          'commercialTarget', jsonb_build_object('gama', 'media')
        ),
        jsonb_build_object(
          'lineRef', 'line-2', 'description', 'Cámara 27,5',
          'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
          'technicalPredicates', '[]'::jsonb, 'preference', null,
          'clarification', null, 'clarificationRequired', false
        )
      ),
      'balanced', null, 'ct-batch-v3'
    )$$,
  '23505',
  'La clave de operación pertenece a otra petición.',
  'a second differing target under the same key also collides'
);
select is(
  (
    select array[needs, revisions, receipts] from ct_collision_counts
  ),
  array[
    (select count(*) from public.supply_needs
     where tenant_id = '99a70000-0000-4000-8000-000000000001'),
    (select count(*) from public.supply_need_commercial_revisions
     where tenant_id = '99a70000-0000-4000-8000-000000000001'),
    (select count(*) from public.supply_need_batch_receipts
     where tenant_id = '99a70000-0000-4000-8000-000000000001')
  ],
  'the collision created no need, no revision and no receipt'
);
-- El espacio de nombres es compartido: una clave que usó v2 no la puede
-- reutilizar v3.
select throws_ok(
  $$select public.create_supply_need_batch_v3(
      'Otra cosa', jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1', 'description', 'Otra pieza',
        'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
        'technicalPredicates', '[]'::jsonb, 'preference', null,
        'clarification', null, 'clarificationRequired', false
      )), 'balanced', null, 'ct-batch-v2'
    )$$,
  '23505',
  'La clave de operación pertenece a otra petición.',
  'a key already consumed by v2 cannot be reused by v3'
);

-- ── 2 · el objetivo se mapea por lineRef real, no por posición ─────────────
select lives_ok(
  $$select public.create_supply_need_batch_v3(
      'Dos líneas en orden invertido',
      jsonb_build_array(
        jsonb_build_object(
          'lineRef', 'line-2', 'description', 'Segunda con objetivo',
          'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
          'technicalPredicates', '[]'::jsonb, 'preference', null,
          'clarification', null, 'clarificationRequired', false,
          'commercialTarget', jsonb_build_object('gama', 'alta')
        ),
        jsonb_build_object(
          'lineRef', 'line-1', 'description', 'Primera sin objetivo',
          'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
          'technicalPredicates', '[]'::jsonb, 'preference', null,
          'clarification', null, 'clarificationRequired', false
        )
      ),
      'balanced', null, 'ct-batch-unordered'
    )$$,
  'v2 accepts line refs in any order, so v3 must too'
);
select is(
  (
    select revision.gama
    from public.supply_need_commercial_revisions revision
    join public.supply_needs need on need.id = revision.supply_need_id
    where need.original_description = 'Segunda con objetivo'
  ),
  'alta',
  'the target landed on the line that carried it, not on the first one'
);
select is(
  (
    select count(*)::integer
    from public.supply_need_commercial_revisions revision
    join public.supply_needs need on need.id = revision.supply_need_id
    where need.original_description = 'Primera sin objetivo'
  ),
  0,
  'and the line without a target got none'
);

-- ── 3 · un objetivo inválido revierte el lote entero ───────────────────────
select throws_ok(
  $$select public.create_supply_need_batch_v3(
      'Un lote con un objetivo imposible',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1', 'description', 'Pieza que no debe existir',
        'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
        'technicalPredicates', '[]'::jsonb, 'preference', null,
        'clarification', null, 'clarificationRequired', false,
        'commercialTarget', jsonb_build_object(
          'preferredBrandId', '99a70000-0000-4000-8000-000000000013'
        )
      )), 'balanced', null, 'ct-batch-invalid'
    )$$,
  '23514',
  'La marca preferida no está disponible para este taller.',
  'an invalid target refuses the batch'
);
select is(
  (
    select count(*)::integer
    from public.supply_needs need
    where need.original_description = 'Pieza que no debe existir'
  ),
  0,
  'and no need was created: the whole batch rolled back'
);

-- ── 4 · el no-op consume su clave ──────────────────────────────────────────
select is(
  (
    select event.changed
    from public.supply_need_events event
    where event.operation_key = 'ct-noop'
  ),
  false,
  'a no-op writes a receipt marked unchanged'
);
select is(
  (
    (public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 5, 4,
      '{"gama": null}'::jsonb, 'ct-noop'
    ) ->> 'replay')::boolean
  ),
  true,
  'and replaying it returns replay true instead of silently redoing nothing'
);
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000041', 8, 6,
      jsonb_build_object('gama', 'alta'), 'ct-noop'
    )$$,
  '23505',
  'La clave de operación pertenece a otro objetivo comercial.',
  'a different payload under the no-op key is a collision: the key was consumed'
);
-- Y las dos ramas devuelven la misma forma.
select ok(
  (public.set_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000041', 5, 4,
    '{"gama": null}'::jsonb, 'ct-noop'
  )) ?& array['action', 'changed', 'operation_key', 'target', 'version'],
  'the no-op response carries the same receipt shape as an effective change'
);

-- ── 5 · la moneda no se reinterpreta ───────────────────────────────────────
select lives_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000042',
      (select version from public.supply_needs
       where id = '99a70000-0000-4000-8000-000000000042'),
      (select max(revision_no) from public.supply_need_commercial_revisions
       where supply_need_id = '99a70000-0000-4000-8000-000000000042'),
      jsonb_build_object('maxLandedUnitCostNet', 12000), 'ct-currency-base'
    )$$,
  'a ceiling is set while the shop is on CLP'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000042'
  ) ->> 'currencyCode'),
  'CLP',
  'and reads back in CLP'
);

update public.tenants set currency = 'USD'
where id = '99a70000-0000-4000-8000-000000000001';

select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000042'
  ) ->> 'currencyCode'),
  'CLP',
  'after the shop switches to USD the stored ceiling still reads in the currency it was set in'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000042'
  ) ->> 'tenantCurrencyCode'),
  'USD',
  'and the current shop currency is reported separately, for comparison'
);
-- Un parche que NO toca el tope arrastraría 12.000 a una revisión en USD: eso
-- es una conversión implícita y se rechaza.
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000042',
      (select version from public.supply_needs
       where id = '99a70000-0000-4000-8000-000000000042'),
      (select max(revision_no) from public.supply_need_commercial_revisions
       where supply_need_id = '99a70000-0000-4000-8000-000000000042'),
      jsonb_build_object('gama', 'media'), 'ct-currency-drift'
    )$$,
  '23514',
  'La moneda del taller cambió de CLP a USD: reemplaza o limpia el tope de costo antes de editar el objetivo.',
  'editing around a stale-currency ceiling is refused instead of converting it'
);
-- Reemplazarlo explícitamente sí: la revisión nueva se denomina en USD.
select lives_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000042',
      (select version from public.supply_needs
       where id = '99a70000-0000-4000-8000-000000000042'),
      (select max(revision_no) from public.supply_need_commercial_revisions
       where supply_need_id = '99a70000-0000-4000-8000-000000000042'),
      jsonb_build_object('maxLandedUnitCostNet', 15), 'ct-currency-rebase'
    )$$,
  'replacing the ceiling explicitly is the way through'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000042'
  ) ->> 'currencyCode'),
  'USD',
  'and the new revision is denominated in the current currency'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000042'
  ) -> 'target' ->> 'maxLandedUnitCostNet')::numeric,
  15.0000::numeric,
  'with the number the operator wrote, never a converted one'
);
update public.tenants set currency = 'CLP'
where id = '99a70000-0000-4000-8000-000000000001';

-- ── 6 · la lectura es autocontenida ────────────────────────────────────────
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000042'
  ) ->> 'needVersion')::bigint,
  (
    select need.version from public.supply_needs need
    where need.id = '99a70000-0000-4000-8000-000000000042'
  ),
  'the read carries the need version the set command demands'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000042'
  ) ->> 'needSupplyState'),
  'open',
  'and the state, so a caller knows whether editing is even allowed'
);

-- Una necesidad cerrada no admite objetivo, igual que en el update genérico.
update public.supply_needs
set supply_state = 'covered'
where id = '99a70000-0000-4000-8000-000000000042';
select throws_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000042',
      (select version from public.supply_needs
       where id = '99a70000-0000-4000-8000-000000000042'),
      (select max(revision_no) from public.supply_need_commercial_revisions
       where supply_need_id = '99a70000-0000-4000-8000-000000000042'),
      jsonb_build_object('gama', 'media'), 'ct-covered'
    )$$,
  '55000',
  'La necesidad ya está cerrada; no admite objetivo comercial.',
  'a covered need takes no more commercial decisions'
);

-- ── 1b · re-denominar con el MISMO número sí es un cambio ──────────────────
--
-- El acto explícito cambia el significado: 12.000 deja de ser pesos y pasa a
-- ser dólares. Comparar sólo los números lo daría por no-op y la lectura
-- seguiría diciendo la moneda vieja.
insert into public.supply_needs(
  id, tenant_id, origin_kind, original_description, product_id, quantity,
  unit, identity_state, supply_state, usage_state, version
) values (
  '99a70000-0000-4000-8000-000000000043',
  '99a70000-0000-4000-8000-000000000001',
  'ad_hoc', 'Necesidad para rebase exacto', null, 1, 'unit',
  'unresolved', 'open', 'not_applicable', 1
);
select lives_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000043', 1, 0,
      jsonb_build_object('maxLandedUnitCostNet', 12000), 'ct-rebase-base'
    )$$,
  'a ceiling of 12000 is set in CLP'
);
update public.tenants set currency = 'USD'
where id = '99a70000-0000-4000-8000-000000000001';

select is(
  (
    (public.set_supply_need_commercial_target_v1(
      '99a70000-0000-4000-8000-000000000043', 2, 1,
      jsonb_build_object('maxLandedUnitCostNet', 12000), 'ct-rebase-same'
    ) ->> 'changed')::boolean
  ),
  true,
  're-entering the same number under another currency is a change'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000043'
  ) ->> 'targetRevisionNo')::bigint,
  2::bigint,
  'it appended a revision'
);
select is(
  (
    select need.version from public.supply_needs need
    where need.id = '99a70000-0000-4000-8000-000000000043'
  ),
  3::bigint,
  'and bumped the need version'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000043'
  ) ->> 'currencyCode'),
  'USD',
  'the target now reads in USD'
);
select is(
  (public.get_supply_need_commercial_target_v1(
    '99a70000-0000-4000-8000-000000000043'
  ) -> 'target' ->> 'maxLandedUnitCostNet')::numeric,
  12000.0000::numeric,
  'with the same number the operator re-entered, never converted'
);
update public.tenants set currency = 'CLP'
where id = '99a70000-0000-4000-8000-000000000001';

-- ── 2b · el replay de v3 es semántico, no textual ──────────────────────────
select lives_ok(
  $$select public.create_supply_need_batch_v3(
      'Un lote para comparar replays',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1', 'description', 'Pieza de replay',
        'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
        'technicalPredicates', '[]'::jsonb, 'preference', null,
        'clarification', null, 'clarificationRequired', false,
        'commercialTarget', jsonb_build_object('maxLandedUnitCostNet', 9000)
      )), 'balanced', null, 'ct-semantic'
    )$$,
  'a batch with a numeric target is created'
);
-- Mismo lote con el número en otra forma y un objetivo vacío añadido en la
-- otra línea: es la misma petición.
select is(
  (
    (public.create_supply_need_batch_v3(
      '  Un lote para comparar replays  ',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1', 'description', 'Pieza de replay',
        'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
        'technicalPredicates', '[]'::jsonb, 'preference', null,
        'clarification', null, 'clarificationRequired', false,
        'commercialTarget', jsonb_build_object('maxLandedUnitCostNet', 9000.0)
      )), 'balanced', null, 'ct-semantic'
    ) ->> 'replay')::boolean
  ),
  true,
  'whitespace and numeric form do not make it a different request'
);
select throws_ok(
  $$select public.create_supply_need_batch_v3(
      'Un lote para comparar replays',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1', 'description', 'Pieza de replay',
        'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
        'technicalPredicates', '[]'::jsonb, 'preference', null,
        'clarification', null, 'clarificationRequired', false,
        'commercialTarget', jsonb_build_object('maxLandedUnitCostNet', 9500)
      )), 'balanced', null, 'ct-semantic'
    )$$,
  '23505',
  'La clave de operación pertenece a otra petición.',
  'but a real difference in the target still collides'
);
-- Un `commercialTarget` vacío o nulo equivale a no traerlo.
select lives_ok(
  $$select public.create_supply_need_batch_v3(
      'Lote sin objetivo',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1', 'description', 'Pieza sin objetivo',
        'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
        'technicalPredicates', '[]'::jsonb, 'preference', null,
        'clarification', null, 'clarificationRequired', false,
        'commercialTarget', '{}'::jsonb
      )), 'balanced', null, 'ct-empty-target'
    )$$,
  'an empty commercial target is accepted'
);
select is(
  (
    (public.create_supply_need_batch_v3(
      'Lote sin objetivo',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1', 'description', 'Pieza sin objetivo',
        'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
        'technicalPredicates', '[]'::jsonb, 'preference', null,
        'clarification', null, 'clarificationRequired', false,
        'commercialTarget', null
      )), 'balanced', null, 'ct-empty-target'
    ) ->> 'replay')::boolean
  ),
  true,
  'and an explicit null target is the same request as an empty one'
);
select is(
  (
    select count(*)::integer
    from public.supply_need_commercial_revisions revision
    join public.supply_needs need on need.id = revision.supply_need_id
    where need.original_description = 'Pieza sin objetivo'
  ),
  0,
  'neither wrote a revision'
);

-- ── 3b · el límite público de la clave sigue siendo 160 bytes ──────────────
select lives_ok(
  $$select public.create_supply_need_batch_v3(
      'Clave de 160 bytes',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1', 'description', 'Pieza con clave larga',
        'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
        'technicalPredicates', '[]'::jsonb, 'preference', null,
        'clarification', null, 'clarificationRequired', false
      )), 'balanced', null, repeat('k', 160)
    )$$,
  'a 160-byte operation key still works: the public limit was not reduced'
);
select throws_ok(
  format($$select public.create_supply_need_batch_v3(
      'Clave de 161 bytes',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1', 'description', 'Pieza con clave larguísima',
        'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
        'technicalPredicates', '[]'::jsonb, 'preference', null,
        'clarification', null, 'clarificationRequired', false
      )), 'balanced', null, %L
    )$$, repeat('k', 161)),
  '22023',
  'La petición de abastecimiento no es válida.',
  'and 161 is refused'
);
select ok(
  (
    select max(octet_length(revision.operation_key)) <= 60
    from public.supply_need_commercial_revisions revision
    where revision.source = 'ai'
      and revision.tenant_id = '99a70000-0000-4000-8000-000000000001'
  ),
  'internal target keys are fixed size, not a suffix on the public one'
);

-- ══════════════════ integridad bajo concurrencia y siembra ═════════════════

-- ── 1 · el lock se toma ANTES de leer el recibo ────────────────────────────
--
-- pgTAP corre en una sola sesión y una transacción, así que no puede montar la
-- carrera real: dos peticiones idénticas simultáneas. Lo que sí se puede
-- afirmar sobre la definición viva es el **orden**, que es donde estaba el
-- defecto: consultar el recibo antes de serializar deja pasar a las dos, y la
-- segunda termina en 40001 o en una violación cruda en vez de ver replay.
select ok(
  position(
    'pg_advisory_xact_lock' in pg_get_functiondef(
      'public.set_supply_need_commercial_target_v1(uuid,bigint,bigint,jsonb,text)'::regprocedure
    )
  ) > 0,
  'the set command serializes on its operation key'
);
select ok(
  position(
    'pg_advisory_xact_lock' in pg_get_functiondef(
      'public.set_supply_need_commercial_target_v1(uuid,bigint,bigint,jsonb,text)'::regprocedure
    )
  ) < position(
    'from public.supply_need_events' in pg_get_functiondef(
      'public.set_supply_need_commercial_target_v1(uuid,bigint,bigint,jsonb,text)'::regprocedure
    )
  ),
  'and it takes the lock before reading the receipt, not after'
);
select ok(
  position(
    'supply_need_commercial_target' in pg_get_functiondef(
      'public.set_supply_need_commercial_target_v1(uuid,bigint,bigint,jsonb,text)'::regprocedure
    )
  ) > 0
  and position(
    'v_tenant_id::text ||' in pg_get_functiondef(
      'public.set_supply_need_commercial_target_v1(uuid,bigint,bigint,jsonb,text)'::regprocedure
    )
  ) > 0,
  'the lock is tenant-scoped: two shops sharing a key do not block each other'
);

-- ── 2 · la clave interna de v3 no es presembrable ──────────────────────────
--
-- La fórmula vieja era `v3-core:md5(tenant:clave)`. Cualquiera del mismo taller
-- podía llamar antes a v2 con exactamente esa clave y una petición base; v3
-- habría encontrado ese recibo, replayado **necesidades viejas** y colgado los
-- objetivos nuevos sobre ellas.
select lives_ok(
  $$select public.create_supply_need_batch_v2(
      'Lote sembrado por un tercero',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1', 'description', 'Necesidad sembrada',
        'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
        'technicalPredicates', '[]'::jsonb, 'preference', null,
        'clarification', null, 'clarificationRequired', false
      )), 'balanced', null,
      'v3-core:' || md5('99a70000-0000-4000-8000-000000000001'
        || ':' || 'ct-preseed')
    )$$,
  'an actor pre-seeds the key the old deterministic formula would have used'
);
select lives_ok(
  $$select public.create_supply_need_batch_v3(
      'Mi lote propio',
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1', 'description', 'Necesidad legítima',
        'productId', null, 'categoryId', null, 'quantity', 1, 'unit', 'unit',
        'technicalPredicates', '[]'::jsonb, 'preference', null,
        'clarification', null, 'clarificationRequired', false,
        'commercialTarget', jsonb_build_object('gama', 'media')
      )), 'balanced', null, 'ct-preseed'
    )$$,
  'and v3 still runs: the pre-seeded key is not the one it derives'
);
select is(
  (
    select count(*)::integer
    from public.supply_needs need
    where need.original_description = 'Necesidad legítima'
      and need.tenant_id = '99a70000-0000-4000-8000-000000000001'
  ),
  1,
  'v3 created its own batch instead of replaying the pre-seeded one'
);
select is(
  (
    select count(*)::integer
    from public.supply_need_commercial_revisions revision
    join public.supply_needs need on need.id = revision.supply_need_id
    where need.original_description = 'Necesidad sembrada'
  ),
  0,
  'and the pre-seeded need got no target attached to it'
);
select is(
  (
    select revision.gama
    from public.supply_need_commercial_revisions revision
    join public.supply_needs need on need.id = revision.supply_need_id
    where need.original_description = 'Necesidad legítima'
  ),
  'media',
  'the target landed on the need v3 actually created'
);

-- La semilla es la identidad del recibo, así que la traza es auditable.
select ok(
  exists (
    select 1
    from public.supply_need_batch_receipts receipt
    join public.supply_need_commercial_revisions revision
      on revision.operation_key
        = 'v3-target:' || receipt.id::text || ':line-1'
    where receipt.tenant_id = '99a70000-0000-4000-8000-000000000001'
      and receipt.operation_key = 'ct-preseed'
  ),
  'the internal target key traces back to the receipt that minted it'
);
select ok(
  not exists (
    select 1 from public.supply_need_batch_receipts receipt
    where receipt.tenant_id = '99a70000-0000-4000-8000-000000000001'
      and receipt.operation_key = 'v3-core:'
        || md5('99a70000-0000-4000-8000-000000000001' || ':' || 'ct-preseed')
      and receipt.request_snapshot -> 'items' -> 0 ->> 'description'
        = 'Necesidad legítima'
  ),
  'no legitimate batch was ever written under the guessable key'
);
select ok(
  (
    select max(octet_length(receipt.operation_key)) <= 60
    from public.supply_need_batch_receipts receipt
    where receipt.tenant_id = '99a70000-0000-4000-8000-000000000001'
      and receipt.operation_key like 'v3-core:%'
  ),
  'the derived core key stays bounded'
);

select * from finish();
rollback;
