begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Fase B1 — del stock de la familia a un producto confirmado.
--
-- Lo que estas pruebas defienden:
--   · el nudo que desatasca: una necesidad sin producto podía quedar encerrada
--     porque el rechazo de stock exigía producto confirmado;
--   · `conflict` no aparece nunca y `unverified` no bloquea, porque «no lo sé»
--     no es «no cumple» y cobrarle al operador una carencia del ERP sería
--     inventarle una decisión;
--   · confirmar una alternativa **conserva** categoría, criterios y
--     aclaraciones: por ese hueco `update_supply_need_v1` borraba la
--     procedencia de la Fase A;
--   · nada de esto asigna stock ni crea plan.

select has_function(
  'public', 'supply_need_resolution_context_internal_v1',
  array['uuid', 'uuid'],
  'one owner decides which interpretation revision governs'
);
select has_function(
  'public', 'supply_need_eligible_products_internal_v1',
  array['uuid', 'uuid', 'integer'],
  'technical eligibility is resolved before any cut'
);
select has_function(
  'public', 'get_supply_need_stock_resolution_v1',
  array['uuid', 'integer', 'integer'],
  'stock-first resolution is bounded and paginated'
);
select has_function(
  'public', 'reject_supply_need_internal_stock_v2',
  array['uuid', 'bigint', 'bigint', 'text', 'text'],
  'the rejection command gained a family lane'
);
select has_function(
  'public', 'confirm_supply_need_family_choice_v1',
  array['uuid', 'bigint', 'bigint', 'uuid', 'text'],
  'convergence to an exact product is its own command'
);

-- v1 intacta: forward-only no rompe a quien no migró.
select has_function(
  'public', 'reject_supply_need_internal_stock_v1',
  array['uuid', 'bigint', 'text', 'text'],
  'the previous rejection command stays callable'
);
select has_function(
  'public', 'update_supply_need_v1',
  array['uuid', 'bigint', 'text', 'uuid', 'numeric', 'text', 'text'],
  'the generic update command is untouched'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.supply_need_resolution_context_internal_v1(uuid,uuid)',
    'execute'
  ) and not has_function_privilege(
    'authenticated',
    'public.supply_need_eligible_products_internal_v1(uuid,uuid,integer)',
    'execute'
  ) and not has_function_privilege(
    'authenticated',
    'public.supply_need_match_state_internal_v1(jsonb,integer)',
    'execute'
  ),
  'internal helpers carry no client grant'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_supply_need_stock_resolution_v1(uuid,integer,integer)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.get_supply_need_stock_resolution_v1(uuid,integer,integer)',
    'execute'
  ),
  'only an authenticated session reads a stock resolution'
);

-- ───────────────────────────── datos de prueba ─────────────────────────────
insert into public.tenants(id, shop_name, currency, timezone) values
  (
    '99d40000-0000-4000-8000-000000000001',
    'Family Resolution Tenant', 'CLP', 'America/Santiago'
  ),
  (
    '99d40000-0000-4000-8000-000000000002',
    'Other Shop', 'CLP', 'America/Santiago'
  );

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99d40000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'family-resolution@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(
  user_id, tenant_id, role, permissions, is_active
) values (
  '99d40000-0000-4000-8000-000000000099',
  '99d40000-0000-4000-8000-000000000001',
  'admin', '{}'::jsonb, true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99d40000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99d40000-0000-4000-8000-000000000099',
  true
);

insert into public.product_categories(
  id, tenant_id, name, full_path, level, is_active
) values
  (
    '99d40000-0000-4000-8000-000000000011',
    '99d40000-0000-4000-8000-000000000001',
    'Cadenas', 'Transmisión / Cadenas', 1, true
  ),
  (
    '99d40000-0000-4000-8000-000000000012',
    '99d40000-0000-4000-8000-000000000001',
    'Cadenas MTB', 'Transmisión / Cadenas / MTB', 2, true
  ),
  (
    '99d40000-0000-4000-8000-000000000013',
    '99d40000-0000-4000-8000-000000000001',
    'Cadenas Retiradas', 'Transmisión / Cadenas / Retiradas', 2, false
  ),
  (
    '99d40000-0000-4000-8000-000000000014',
    '99d40000-0000-4000-8000-000000000001',
    'Multitud', 'Transmisión / Multitud', 1, true
  );
update public.product_categories
set parent_id = '99d40000-0000-4000-8000-000000000011'
where id in (
  '99d40000-0000-4000-8000-000000000012',
  '99d40000-0000-4000-8000-000000000013'
);

insert into public.spec_definitions(
  id, tenant_id, key, label, data_type, is_filterable
) values (
  '99d40000-0000-4000-8000-000000000021',
  '99d40000-0000-4000-8000-000000000001',
  'chain_speeds', 'Velocidades', 'number', true
);
insert into public.spec_templates(
  id, tenant_id, key, name, technical_family, is_active
) values (
  '99d40000-0000-4000-8000-000000000031',
  '99d40000-0000-4000-8000-000000000001',
  'chain_template', 'Cadenas', 'chain', true
);
insert into public.spec_template_fields(
  id, tenant_id, template_id, spec_definition_id
) values (
  '99d40000-0000-4000-8000-000000000041',
  '99d40000-0000-4000-8000-000000000001',
  '99d40000-0000-4000-8000-000000000031',
  '99d40000-0000-4000-8000-000000000021'
);
insert into public.category_tech_mappings(
  id, tenant_id, category_id, technical_family, template_id, status
) values (
  '99d40000-0000-4000-8000-000000000051',
  '99d40000-0000-4000-8000-000000000001',
  '99d40000-0000-4000-8000-000000000011',
  'chain', '99d40000-0000-4000-8000-000000000031', 'active'
);

-- Cinco productos que cubren cada estado de evidencia y de cobertura.
insert into public.products(
  id, tenant_id, name, sku, category_id, is_active, price,
  track_stock, stock_quantity
) values
  -- strong + stock suficiente: éste bloquea el paso externo.
  (
    '99d40000-0000-4000-8000-000000000061',
    '99d40000-0000-4000-8000-000000000001',
    'Cadena KMC X10 116L', 'KMC-X10', '99d40000-0000-4000-8000-000000000011',
    true, 19990, true, 10
  ),
  -- conflict: la ficha dice otra cosa. No debe aparecer jamás.
  (
    '99d40000-0000-4000-8000-000000000062',
    '99d40000-0000-4000-8000-000000000001',
    'Cadena Shimano 11v', 'SHI-11', '99d40000-0000-4000-8000-000000000012',
    true, 24990, true, 20
  ),
  -- unverified: sin valor de ficha para el criterio, y con stock de sobra.
  (
    '99d40000-0000-4000-8000-000000000063',
    '99d40000-0000-4000-8000-000000000001',
    'Cadena genérica reforzada', 'GEN-RF',
    '99d40000-0000-4000-8000-000000000011', true, 9990, true, 30
  ),
  -- categoría inactiva: fuera del universo aunque el producto esté activo.
  (
    '99d40000-0000-4000-8000-000000000064',
    '99d40000-0000-4000-8000-000000000001',
    'Cadena descatalogada', 'OLD-1',
    '99d40000-0000-4000-8000-000000000013', true, 4990, true, 50
  ),
  -- otro tenant: nunca visible.
  (
    '99d40000-0000-4000-8000-000000000065',
    '99d40000-0000-4000-8000-000000000002',
    'Cadena de otro taller', 'FOR-1', null, true, 9990, true, 99
  ),
  -- producto inactivo del mismo tenant y categoría.
  (
    '99d40000-0000-4000-8000-000000000066',
    '99d40000-0000-4000-8000-000000000001',
    'Cadena dada de baja', 'DEAD-1',
    '99d40000-0000-4000-8000-000000000011', false, 9990, true, 40
  );

insert into public.product_spec_values(
  id, tenant_id, product_id, spec_definition_id, value_number
) values
  (
    '99d40000-0000-4000-8000-000000000071',
    '99d40000-0000-4000-8000-000000000001',
    '99d40000-0000-4000-8000-000000000061',
    '99d40000-0000-4000-8000-000000000021', 10
  ),
  (
    '99d40000-0000-4000-8000-000000000072',
    '99d40000-0000-4000-8000-000000000001',
    '99d40000-0000-4000-8000-000000000062',
    '99d40000-0000-4000-8000-000000000021', 11
  );

-- La necesidad del carril familia: 2 unidades, categoría Cadenas, 10v.
insert into public.supply_needs(
  id, tenant_id, origin_kind, original_description, product_id, quantity,
  unit, identity_state, supply_state, usage_state, version
) values (
  '99d40000-0000-4000-8000-000000000081',
  '99d40000-0000-4000-8000-000000000001',
  'ad_hoc', 'Cadena de 10 velocidades', null, 2, 'unit',
  'unresolved', 'open', 'not_applicable', 1
);
insert into public.supply_need_interpretation_revisions(
  id, tenant_id, supply_need_id, revision_no, source, raw_description,
  identity_state, category_id, constraints, clarifications, formula_version
) values (
  '99d40000-0000-4000-8000-000000000091',
  '99d40000-0000-4000-8000-000000000001',
  '99d40000-0000-4000-8000-000000000081', 1, 'ai',
  'Necesito una cadena de 10 velocidades', 'unresolved',
  '99d40000-0000-4000-8000-000000000011',
  jsonb_build_array(
    jsonb_build_object('field', 'chain_speeds', 'operator', 'eq',
      'values', jsonb_build_array(10)),
    jsonb_build_object('kind', 'ranking_profile', 'value', 'balanced')
  ),
  jsonb_build_array(jsonb_build_object(
    'question', '¿Es para MTB o ruta?', 'blocking', false
  )),
  'ai-supply-request-v2'
);

-- ───────────────────── elegibilidad: quién entra y quién no ────────────────
select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      public.supply_need_eligible_products_internal_v1(
        '99d40000-0000-4000-8000-000000000001',
        '99d40000-0000-4000-8000-000000000081'
      ) -> 'items'
    )
  ),
  2,
  'only the two usable products survive: conflict, inactive category, inactive product and the other tenant are all out'
);

select ok(
  not exists (
    select 1
    from jsonb_array_elements(
      public.supply_need_eligible_products_internal_v1(
        '99d40000-0000-4000-8000-000000000001',
        '99d40000-0000-4000-8000-000000000081'
      ) -> 'items'
    ) entry(value)
    where (entry.value ->> 'productId')::uuid in (
      '99d40000-0000-4000-8000-000000000062',
      '99d40000-0000-4000-8000-000000000064',
      '99d40000-0000-4000-8000-000000000065',
      '99d40000-0000-4000-8000-000000000066'
    )
  ),
  'a contradicting ficha, a retired branch, a deactivated product and another shop never appear'
);

select is(
  (
    select entry.value ->> 'matchState'
    from jsonb_array_elements(
      public.supply_need_eligible_products_internal_v1(
        '99d40000-0000-4000-8000-000000000001',
        '99d40000-0000-4000-8000-000000000081'
      ) -> 'items'
    ) entry(value)
    where (entry.value ->> 'productId')::uuid
      = '99d40000-0000-4000-8000-000000000061'
  ),
  'strong',
  'a ficha value that satisfies the criterion is strong evidence'
);
select is(
  (
    select entry.value ->> 'matchState'
    from jsonb_array_elements(
      public.supply_need_eligible_products_internal_v1(
        '99d40000-0000-4000-8000-000000000001',
        '99d40000-0000-4000-8000-000000000081'
      ) -> 'items'
    ) entry(value)
    where (entry.value ->> 'productId')::uuid
      = '99d40000-0000-4000-8000-000000000063'
  ),
  'unverified',
  'a product the ficha cannot answer for is unverified, not compatible'
);

-- ───────────────────── universo amplio: refinar, no truncar ────────────────
select is(
  (
    public.supply_need_eligible_products_internal_v1(
      '99d40000-0000-4000-8000-000000000001',
      '99d40000-0000-4000-8000-000000000081',
      2
    ) ->> 'status'
  ),
  'needs_refinement',
  'a universe over the explicit ceiling asks to refine instead of truncating'
);
select is(
  (
    public.supply_need_eligible_products_internal_v1(
      '99d40000-0000-4000-8000-000000000001',
      '99d40000-0000-4000-8000-000000000081',
      2
    ) -> 'items'
  ),
  '[]'::jsonb,
  'and it returns no items at all: a silent partial list would look complete'
);
select is(
  (
    public.supply_need_eligible_products_internal_v1(
      '99d40000-0000-4000-8000-000000000001',
      '99d40000-0000-4000-8000-000000000081',
      2
    ) -> 'availableFields'
  ),
  jsonb_build_array('chain_speeds'),
  'refining is actionable: the template fields that can narrow it are named'
);

-- Una plantilla retirada, nombrada explícitamente por el mapeo, no puede
-- seguir ofreciendo criterios: son campos que el taller ya descartó.
update public.spec_templates
set is_active = false
where id = '99d40000-0000-4000-8000-000000000031';

select is(
  (
    public.supply_need_eligible_products_internal_v1(
      '99d40000-0000-4000-8000-000000000001',
      '99d40000-0000-4000-8000-000000000081',
      2
    ) -> 'availableFields'
  ),
  '[]'::jsonb,
  'an explicitly mapped but inactive template offers no fields to refine by'
);
select is(
  (
    public.supply_need_eligible_products_internal_v1(
      '99d40000-0000-4000-8000-000000000001',
      '99d40000-0000-4000-8000-000000000081',
      2
    ) ->> 'status'
  ),
  'needs_refinement',
  'and the overflow is still reported honestly, just without a false way out'
);

update public.spec_templates
set is_active = true
where id = '99d40000-0000-4000-8000-000000000031';

-- ───────────────────────── resolución de stock ─────────────────────────────
select is(
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000081'
  ) ->> 'coverage'),
  'full',
  'a candidate with enough ATP covers the need'
);
select is(
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000081'
  ) ->> 'blocksExternal')::boolean,
  true,
  'a full strong candidate blocks the external step'
);
select is(
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000081'
  ) -> 'counts' ->> 'eligible')::integer,
  2,
  'counts describe the whole eligible set, not the page'
);
select is(
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000081', 1, 0
  ) -> 'page' ->> 'hasMore')::boolean,
  true,
  'pagination says there is more instead of pretending the page is everything'
);
select is(
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000081'
  ) ->> 'familyAggregateProvesCoverage')::boolean,
  false,
  'the family aggregate never claims interchangeable coverage'
);

-- `unverified` con stock de sobra no puede bloquear por sí solo.
update public.products
set stock_quantity = 0
where id = '99d40000-0000-4000-8000-000000000061';

select is(
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000081'
  ) ->> 'blocksExternal')::boolean,
  false,
  'an unverified candidate with plenty of stock does not block the external step'
);
select is(
  (
    select entry.value ->> 'matchState'
    from jsonb_array_elements(
      public.get_supply_need_stock_resolution_v1(
        '99d40000-0000-4000-8000-000000000081'
      ) -> 'items'
    ) entry(value)
    where (entry.value ->> 'coverage') = 'full'
  ),
  'unverified',
  'it is still shown, labelled as pending verification'
);

-- ──────────────── rechazo de familia: el nudo que desatasca ────────────────
select throws_ok(
  $$select public.reject_supply_need_internal_stock_v1(
      '99d40000-0000-4000-8000-000000000081', 1,
      'El taller quiere una cadena nueva.', 'b1-v1-attempt'
    )$$,
  '55000',
  'No existe una alternativa interna confirmada para rechazar.',
  'v1 still refuses a need without a confirmed product: that was the deadlock'
);

-- Sin candidato bloqueante tampoco hay nada que rechazar.
select throws_ok(
  $$select public.reject_supply_need_internal_stock_v2(
      '99d40000-0000-4000-8000-000000000081', 1, 1,
      'No sirve.', 'b1-no-blocking'
    )$$,
  '23514',
  'No hay stock interno asignable; no requiere rechazo.',
  'rejecting stock that does not block would record a decision nobody had to take'
);

update public.products
set stock_quantity = 10
where id = '99d40000-0000-4000-8000-000000000061';

select lives_ok(
  $$select public.reject_supply_need_internal_stock_v2(
      '99d40000-0000-4000-8000-000000000081', 1, 1,
      'El cliente pidió cadena nueva, no la del taller.', 'b1-family-reject'
    )$$,
  'a family need with no confirmed product can finally record its rejection'
);
select is(
  (
    select event.action
    from public.supply_need_events event
    where event.operation_key = 'b1-family-reject'
  ),
  'family_stock_rejected',
  'the ledger names what happened instead of calling it a generic update'
);
select is(
  (
    select need.internal_stock_rejection_reason
    from public.supply_needs need
    where need.id = '99d40000-0000-4000-8000-000000000081'
  ),
  'El cliente pidió cadena nueva, no la del taller.',
  'the reason is durable evidence on the need'
);

select is(
  (
    (public.reject_supply_need_internal_stock_v2(
      '99d40000-0000-4000-8000-000000000081', 1, 1,
      'El cliente pidió cadena nueva, no la del taller.', 'b1-family-reject'
    ) ->> 'replay')::boolean
  ),
  true,
  'the same operation key replays instead of rejecting twice'
);
select throws_ok(
  $$select public.reject_supply_need_internal_stock_v2(
      '99d40000-0000-4000-8000-000000000081', 1, 1,
      'Otro motivo distinto.', 'b1-family-reject'
    )$$,
  '23505',
  'La clave de operación pertenece a otro rechazo.',
  'a reused key with a different request is refused'
);

-- La versión va correcta a propósito: así se comprueba la guarda de la
-- revisión y no la de versión, que habría disparado antes.
select throws_ok(
  $$select public.reject_supply_need_internal_stock_v2(
      '99d40000-0000-4000-8000-000000000081', 2, 99,
      'Motivo.', 'b1-stale-revision'
    )$$,
  '40001',
  'La interpretación cambió; vuelve a revisar el stock.',
  'a rejection cannot refer to an interpretation that is no longer governing'
);

-- ───────────────────── convergencia y su procedencia ───────────────────────
select throws_ok(
  $$select public.confirm_supply_need_family_choice_v1(
      '99d40000-0000-4000-8000-000000000081', 2, 1,
      '99d40000-0000-4000-8000-000000000062', 'b1-confirm-conflict'
    )$$,
  '23514',
  'El producto no pertenece al conjunto elegible de la necesidad.',
  'a contradicting product cannot be chosen: it never was eligible'
);
select throws_ok(
  $$select public.confirm_supply_need_family_choice_v1(
      '99d40000-0000-4000-8000-000000000081', 2, 1,
      '99d40000-0000-4000-8000-000000000065', 'b1-confirm-foreign'
    )$$,
  '23514',
  'El producto no pertenece al conjunto elegible de la necesidad.',
  'another shop product is unreachable through convergence'
);

-- Elegir el `unverified` es legítimo: la decisión es de una persona.
select lives_ok(
  $$select public.confirm_supply_need_family_choice_v1(
      '99d40000-0000-4000-8000-000000000081', 2, 1,
      '99d40000-0000-4000-8000-000000000063', 'b1-confirm'
    )$$,
  'an explicit choice of an unverified alternative is allowed'
);

select is(
  (
    select need.identity_state || ':' || need.product_id::text
    from public.supply_needs need
    where need.id = '99d40000-0000-4000-8000-000000000081'
  ),
  'confirmed:99d40000-0000-4000-8000-000000000063',
  'the need converges to an exact product'
);

select is(
  (
    select revision.category_id
    from public.supply_need_interpretation_revisions revision
    where revision.supply_need_id = '99d40000-0000-4000-8000-000000000081'
    order by revision.revision_no desc
    limit 1
  ),
  '99d40000-0000-4000-8000-000000000011'::uuid,
  'confirming preserves the category: update_supply_need_v1 would have erased it'
);
select is(
  (
    select jsonb_array_length(revision.constraints)
    from public.supply_need_interpretation_revisions revision
    where revision.supply_need_id = '99d40000-0000-4000-8000-000000000081'
    order by revision.revision_no desc
    limit 1
  ),
  2,
  'and the criteria that produced the alternative survive with it'
);
select is(
  (
    select jsonb_array_length(revision.clarifications)
    from public.supply_need_interpretation_revisions revision
    where revision.supply_need_id = '99d40000-0000-4000-8000-000000000081'
    order by revision.revision_no desc
    limit 1
  ),
  1,
  'clarifications travel too: they were part of the same interpretation'
);
select is(
  (
    select revision.evidence_snapshot ->> 'match_state'
    from public.supply_need_interpretation_revisions revision
    where revision.supply_need_id = '99d40000-0000-4000-8000-000000000081'
    order by revision.revision_no desc
    limit 1
  ),
  'unverified',
  'the evidence records why the product was eligible, honestly'
);
select ok(
  not exists (
    select 1
    from public.supply_need_interpretation_revisions revision
    where revision.supply_need_id = '99d40000-0000-4000-8000-000000000081'
      and (revision.evidence_snapshot ? 'category_path'
        or revision.evidence_snapshot ? 'technical_family')
  ),
  'no derived gloss is frozen next to a source that keeps moving'
);

select is(
  (
    select need.internal_stock_rejection_reason
    from public.supply_needs need
    where need.id = '99d40000-0000-4000-8000-000000000081'
  ),
  'El cliente pidió cadena nueva, no la del taller.',
  'an earlier family rejection survives convergence: that decision was already taken'
);

select is(
  (
    select event.action
    from public.supply_need_events event
    where event.operation_key = 'b1-confirm'
  ),
  'family_choice_confirmed',
  'convergence is a typed action in the ledger'
);

-- Ni stock asignado ni plan creado.
select is(
  (
    select count(*)::integer
    from public.workshop_inventory_commitments commitment
    where commitment.tenant_id = '99d40000-0000-4000-8000-000000000001'
  ),
  0,
  'confirming an identity never commits units'
);

select is(
  (
    (public.confirm_supply_need_family_choice_v1(
      '99d40000-0000-4000-8000-000000000081', 2, 1,
      '99d40000-0000-4000-8000-000000000063', 'b1-confirm'
    ) ->> 'replay')::boolean
  ),
  true,
  'the confirmation replays under the same operation key'
);
select is(
  (
    select count(*)::integer
    from public.supply_need_interpretation_revisions revision
    where revision.supply_need_id = '99d40000-0000-4000-8000-000000000081'
  ),
  2,
  'replay created no second interpretation'
);

-- El replay feliz no basta: lo que hay que impedir es que la misma clave sirva
-- para una petición distinta. Debe fallar **antes** de tocar estado.
select throws_ok(
  $$select public.confirm_supply_need_family_choice_v1(
      '99d40000-0000-4000-8000-000000000081', 2, 1,
      '99d40000-0000-4000-8000-000000000061', 'b1-confirm'
    )$$,
  '23505',
  'La clave de operación pertenece a otra confirmación.',
  'the same operation key with a different product is refused'
);
select is(
  (
    select need.product_id
    from public.supply_needs need
    where need.id = '99d40000-0000-4000-8000-000000000081'
  ),
  '99d40000-0000-4000-8000-000000000063'::uuid,
  'and the refusal left the confirmed product untouched'
);
select is(
  (
    select count(*)::integer
    from public.supply_need_events event
    where event.supply_need_id = '99d40000-0000-4000-8000-000000000081'
      and event.action = 'family_choice_confirmed'
  ),
  1,
  'no second confirmation reached the ledger'
);

select throws_ok(
  $$select public.confirm_supply_need_family_choice_v1(
      '99d40000-0000-4000-8000-000000000081', 3, 2,
      '99d40000-0000-4000-8000-000000000061', 'b1-confirm-twice'
    )$$,
  '55000',
  'La necesidad ya tiene un producto confirmado.',
  'a need that already converged is not re-pointed through this command'
);

-- ─────────────────── el carril exacto conserva su semántica ────────────────
select is(
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000081'
  ) ->> 'lane'),
  'exact',
  'once converged, the need reads as the exact lane and does not widen'
);
select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      public.get_supply_need_stock_resolution_v1(
        '99d40000-0000-4000-8000-000000000081'
      ) -> 'items'
    )
  ),
  1,
  'the exact lane resolves exactly one product'
);

-- ───────── el carril exacto de v2, sobre una necesidad propia ──────────────
--
-- La lectura de arriba mira el carril exacto **después** de converger. Esto es
-- distinto: una necesidad que nació exacta, para comprobar que v2 conserva de
-- verdad la semántica de v1 y registra su propia acción.
insert into public.supply_needs(
  id, tenant_id, origin_kind, original_description, product_id, quantity,
  unit, identity_state, supply_state, usage_state, version
) values (
  '99d40000-0000-4000-8000-000000000082',
  '99d40000-0000-4000-8000-000000000001',
  'ad_hoc', 'Cadena KMC X10 exacta',
  '99d40000-0000-4000-8000-000000000061', 2, 'unit',
  'confirmed', 'open', 'not_applicable', 1
);
insert into public.supply_need_interpretation_revisions(
  id, tenant_id, supply_need_id, revision_no, source, raw_description,
  identity_state, canonical_product_id, category_id, constraints,
  clarifications, formula_version
) values (
  '99d40000-0000-4000-8000-000000000092',
  '99d40000-0000-4000-8000-000000000001',
  '99d40000-0000-4000-8000-000000000082', 1, 'ai',
  'La cadena KMC X10 de siempre', 'confirmed',
  '99d40000-0000-4000-8000-000000000061',
  '99d40000-0000-4000-8000-000000000011', '[]'::jsonb, '[]'::jsonb,
  'ai-supply-request-v2'
);

select is(
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000082'
  ) ->> 'lane'),
  'exact',
  'a need born exact resolves in the exact lane'
);
select is(
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000082'
  ) ->> 'blocksExternal')::boolean,
  true,
  'its own stock blocks the external step'
);

select lives_ok(
  $$select public.reject_supply_need_internal_stock_v2(
      '99d40000-0000-4000-8000-000000000082', 1, 1,
      'La del taller está gastada.', 'b1-exact-reject'
    )$$,
  'v2 accepts the exact lane exactly as v1 did'
);
select is(
  (
    select event.action
    from public.supply_need_events event
    where event.operation_key = 'b1-exact-reject'
  ),
  'internal_stock_rejected',
  'and records the original action, not the family one'
);
select is(
  (
    select event.response_snapshot ->> 'lane'
    from public.supply_need_events event
    where event.operation_key = 'b1-exact-reject'
  ),
  'exact',
  'the receipt names which lane took the decision'
);
select is(
  (
    select need.internal_stock_rejection_reason
    from public.supply_needs need
    where need.id = '99d40000-0000-4000-8000-000000000082'
  ),
  'La del taller está gastada.',
  'the reason lands on the need'
);

-- Y sin stock asignable no hay nada que rechazar, igual que en v1.
update public.products
set stock_quantity = 0
where id = '99d40000-0000-4000-8000-000000000061';

select throws_ok(
  $$select public.reject_supply_need_internal_stock_v2(
      '99d40000-0000-4000-8000-000000000082', 2, 1,
      'Otro motivo.', 'b1-exact-no-stock'
    )$$,
  '23514',
  'No hay stock interno asignable; no requiere rechazo.',
  'v2 keeps the v1 guard: rejecting stock that does not exist is not a decision'
);

-- ───────────── el envelope público, clave por clave (Fase B2) ──────────────
--
-- El bundle interno puede crecer; la respuesta pública no. La primera versión
-- de ese corte devolvía `bundle - 'orderedItems'` y filtró tres claves que la
-- rama no-ok nunca había publicado. Estas pruebas comparan el **conjunto
-- exacto** de claves, así que tanto una adición como una ausencia muerden.

-- Una necesidad sin categoría resuelta: la rama no-ok.
insert into public.supply_needs(
  id, tenant_id, origin_kind, original_description, product_id, quantity,
  unit, identity_state, supply_state, usage_state, version
) values (
  '99d40000-0000-4000-8000-000000000083',
  '99d40000-0000-4000-8000-000000000001',
  'ad_hoc', 'Algo que todavía no sé nombrar', null, 1, 'unit',
  'unresolved', 'open', 'not_applicable', 1
);
insert into public.supply_need_interpretation_revisions(
  id, tenant_id, supply_need_id, revision_no, source, raw_description,
  identity_state, category_id, constraints, clarifications, formula_version
) values (
  '99d40000-0000-4000-8000-000000000093',
  '99d40000-0000-4000-8000-000000000001',
  '99d40000-0000-4000-8000-000000000083', 1, 'ai',
  'Algo que todavía no sé nombrar', 'unresolved',
  null, '[]'::jsonb, '[]'::jsonb, 'ai-supply-request-v2'
);

select is(
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000083'
  ) ->> 'status'),
  'identity_unresolved',
  'a need with no resolved category answers the non-ok branch'
);
select is(
  (
    select array_agg(key order by key)
    from jsonb_object_keys(
      public.get_supply_need_stock_resolution_v1(
        '99d40000-0000-4000-8000-000000000083'
      )
    ) key
  ),
  array[
    'availableFields', 'blocksExternal', 'categoryId', 'counts', 'coverage',
    'items', 'lane', 'needId', 'needVersion', 'quantity', 'revisionNo',
    'safeLimit', 'status', 'unit', 'universeSize'
  ]::text[],
  'the non-ok envelope publishes exactly the fifteen legacy keys'
);
select is(
  (
    select array_agg(key order by key)
    from jsonb_object_keys(
      public.get_supply_need_stock_resolution_v1(
        '99d40000-0000-4000-8000-000000000082'
      )
    ) key
  ),
  array[
    'blocksExternal', 'categoryId', 'counts', 'coverage',
    'familyAggregateAtp', 'familyAggregateProvesCoverage',
    'internalStockRejectionReason', 'items', 'lane', 'needId', 'needVersion',
    'page', 'quantity', 'revisionNo', 'status', 'unit', 'universeSize'
  ]::text[],
  'the ok envelope publishes exactly the seventeen legacy keys'
);
-- Y las claves que cada rama NO publica, dichas una por una: el bundle las
-- tiene, la respuesta pública no.
select ok(
  not (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000083'
  ) ?| array[
    'internalStockRejectionReason', 'familyAggregateAtp',
    'familyAggregateProvesCoverage', 'page', 'orderedItems'
  ]),
  'the non-ok branch leaks no bundle metadata'
);
select ok(
  not (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000082'
  ) ?| array['safeLimit', 'availableFields', 'orderedItems']),
  'the ok branch offers no refinement handles: there is nothing to refine'
);

-- ──────────── una sola evaluación técnica por llamada (Fase B2) ────────────
--
-- La garantía es **una evaluación de elegibilidad por invocación RPC**, no por
-- sesión. Esa función compara cada predicado contra cada producto del
-- universo: llamarla dos veces dentro de una misma llamada, para responder una
-- sola pregunta, es el defecto que este corte cierra. La RPC externa de la fase
-- siguiente llamará al bundle una vez **dentro de su propia invocación**; no
-- reutiliza el resultado de la lectura de stock que la interfaz hizo antes, ni
-- podría, porque son dos peticiones y entremedio el inventario se mueve.
--
-- Se comprueba sobre la definición viva, no sobre la intención: la lectura
-- pública no puede volver a llamar a la elegibilidad por su cuenta.
select has_function(
  'public', 'supply_need_stock_bundle_internal_v1',
  array['uuid', 'uuid', 'integer'],
  'ATP, coverage and blocking have one owner'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.supply_need_stock_bundle_internal_v1(uuid,uuid,integer)',
    'execute'
  ),
  'the bundle is internal: the client reaches it only through the governed read'
);
select is(
  (
    select count(*)::integer
    from regexp_matches(
      pg_get_functiondef(
        'public.get_supply_need_stock_resolution_v1(uuid,integer,integer)'::regprocedure
      ),
      'supply_need_eligible_products_internal_v1', 'g'
    )
  ),
  0,
  'the public read never evaluates eligibility itself'
);
select is(
  (
    select count(*)::integer
    from regexp_matches(
      pg_get_functiondef(
        'public.get_supply_need_stock_resolution_v1(uuid,integer,integer)'::regprocedure
      ),
      'supply_need_stock_bundle_internal_v1', 'g'
    )
  ),
  1,
  'it calls the bundle exactly once'
);
select is(
  (
    select count(*)::integer
    from regexp_matches(
      pg_get_functiondef(
        'public.supply_need_stock_bundle_internal_v1(uuid,uuid,integer)'::regprocedure
      ),
      'supply_need_eligible_products_internal_v1', 'g'
    )
  ),
  1,
  'and the bundle evaluates eligibility exactly once'
);

-- Paginar no puede cambiar la verdad: los conteos y el bloqueo se calculan
-- sobre el conjunto entero, no sobre la página que se está mirando.
select is(
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000082', 1, 0
  ) -> 'counts'),
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000082', 50, 0
  ) -> 'counts'),
  'counts do not depend on the page'
);
select is(
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000082', 1, 5
  ) ->> 'blocksExternal'),
  (public.get_supply_need_stock_resolution_v1(
    '99d40000-0000-4000-8000-000000000082', 50, 0
  ) ->> 'blocksExternal'),
  'and neither does the block: a blocking candidate on page three blocks too'
);

select * from finish();
rollback;
