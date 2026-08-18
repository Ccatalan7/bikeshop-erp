begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Las opciones externas de una necesidad: lo que tiene que seguir siendo
-- cierto cuando nadie recuerde por qué.
--
--   · el stock va primero, y saltárselo es un error, no una lista vacía;
--   · se puntúa el conjunto entero ANTES de cortar, así que el objetivo
--     comercial puede rescatar un candidato que venía en la página tres;
--   · «no lo sé» no vale cero: un `unknown` se excluye del promedio;
--   · sin ninguna señal conocida el puntaje es EXACTAMENTE el legado;
--   · una resta entre monedas distintas no es margen, en ningún camino.

-- ─────────────────────────── contrato de superficie ───────────────────────
select has_function(
  'public', 'get_supply_need_external_candidates_v1',
  array['uuid', 'integer', 'integer', 'integer', 'integer'],
  'the external candidate read exists with independent bounds per group'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_supply_need_external_candidates_v1(uuid,integer,integer,integer,integer)',
    'execute'
  ),
  'and the client can call it'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.supply_need_external_candidates_internal_v1(uuid,uuid,integer,integer,integer,integer,integer)',
    'execute'
  ) and not has_function_privilege(
    'authenticated',
    'public.supply_need_external_envelope_internal_v1(jsonb,jsonb,text,text,text,jsonb,integer,jsonb,jsonb,jsonb,jsonb)',
    'execute'
  ),
  'the internals carry no client grant: the fanout ceiling is not negotiable from a client'
);
select is(
  (
    select provolatile::text
    from pg_proc
    where oid = 'public.get_supply_need_external_candidates_v1(uuid,integer,integer,integer,integer)'::regprocedure
  ),
  's',
  'the read is stable: it proposes, it never writes'
);
select has_column(
  'public', 'purchase_candidate_metrics_v1', 'price_currency',
  'the candidate view publishes the currency its catalog price is denominated in'
);

-- **El bundle se llama UNA vez, y la vista cara se lee UNA vez fuera del
-- kernel.** Se afirma sobre el cuerpo de la función: una segunda llamada es
-- exactamente lo que esta prueba tiene que ver aparecer.
select is(
  (
    select count(*)::integer
    from regexp_matches(
      pg_get_functiondef(
        'public.supply_need_external_candidates_internal_v1(uuid,uuid,integer,integer,integer,integer,integer)'::regprocedure
      ),
      'supply_need_stock_bundle_internal_v1\s*\(', 'g'
    )
  ),
  1,
  'exactly one stock bundle call per invocation: one technical evaluation'
);
select is(
  (
    select count(*)::integer
    from regexp_matches(
      pg_get_functiondef(
        'public.supply_need_external_candidates_internal_v1(uuid,uuid,integer,integer,integer,integer,integer)'::regprocedure
      ),
      'purchase_candidate_scores_internal_v1\s*\(', 'g'
    )
  ),
  1,
  'exactly one kernel call: the whole set is scored in one pass'
);
select is(
  (
    select count(*)::integer
    from regexp_matches(
      pg_get_functiondef(
        'public.supply_need_external_candidates_internal_v1(uuid,uuid,integer,integer,integer,integer,integer)'::regprocedure
      ),
      'purchase_candidate_metrics_v1', 'g'
    )
  ),
  1,
  'and the expensive view is read once outside the kernel: no third read, no correlated shape'
);

-- ───────────────────────────── datos de prueba ─────────────────────────────
insert into public.tenants(id, shop_name, currency, timezone) values
  (
    '99c90000-0000-4000-8000-000000000001',
    'External Candidates Tenant', 'CLP', 'America/Santiago'
  ),
  (
    '99c90000-0000-4000-8000-000000000002',
    'Otro Taller', 'CLP', 'America/Santiago'
  );
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99c90000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'external-candidates@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(
  user_id, tenant_id, role, permissions, is_active
) values (
  '99c90000-0000-4000-8000-000000000099',
  '99c90000-0000-4000-8000-000000000001',
  'admin', '{}'::jsonb, true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99c90000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99c90000-0000-4000-8000-000000000099',
  true
);

-- Tres categorías: la del ranking, la del bloqueo por stock y una sin historia.
insert into public.product_categories(
  id, tenant_id, name, full_path, level, is_active
) values
  (
    '99c90000-0000-4000-8000-000000000011',
    '99c90000-0000-4000-8000-000000000001',
    'Cadenas', 'Transmisión / Cadenas', 1, true
  ),
  (
    '99c90000-0000-4000-8000-000000000012',
    '99c90000-0000-4000-8000-000000000001',
    'Frenos', 'Frenos', 1, true
  ),
  (
    '99c90000-0000-4000-8000-000000000013',
    '99c90000-0000-4000-8000-000000000001',
    'Manillas', 'Manillas', 1, true
  ),
  (
    '99c90000-0000-4000-8000-000000000014',
    '99c90000-0000-4000-8000-000000000001',
    'Piñones', 'Transmisión / Piñones', 1, true
  ),
  (
    '99c90000-0000-4000-8000-000000000015',
    '99c90000-0000-4000-8000-000000000001',
    'Ruedas', 'Ruedas', 1, true
  );

insert into public.spec_definitions(
  id, tenant_id, key, label, data_type, is_filterable
) values (
  '99c90000-0000-4000-8000-000000000021',
  '99c90000-0000-4000-8000-000000000001',
  'chain_speeds', 'Velocidades', 'number', true
);
insert into public.spec_templates(
  id, tenant_id, key, name, technical_family, is_active
) values (
  '99c90000-0000-4000-8000-000000000031',
  '99c90000-0000-4000-8000-000000000001',
  'chain_template', 'Cadenas', 'chain', true
);
insert into public.spec_template_fields(
  id, tenant_id, template_id, spec_definition_id
) values (
  '99c90000-0000-4000-8000-000000000041',
  '99c90000-0000-4000-8000-000000000001',
  '99c90000-0000-4000-8000-000000000031',
  '99c90000-0000-4000-8000-000000000021'
);
insert into public.category_tech_mappings(
  id, tenant_id, category_id, technical_family, template_id, status
) values (
  '99c90000-0000-4000-8000-000000000051',
  '99c90000-0000-4000-8000-000000000001',
  '99c90000-0000-4000-8000-000000000011',
  'chain', '99c90000-0000-4000-8000-000000000031', 'active'
);

-- Dos marcas: una del taller, una global.
insert into public.product_brands(id, tenant_id, name, is_active) values
  (
    '99c90000-0000-4000-8000-000000000061',
    '99c90000-0000-4000-8000-000000000001', 'KMC', true
  ),
  ('99c90000-0000-4000-8000-000000000062', null, 'Shimano', true);

-- Los productos cubren cada estado de marca, de moneda y de flete.
-- Todos con stock 0: nada bloquea el paso externo en esta categoría.
insert into public.products(
  id, tenant_id, name, sku, category_id, brand_id, brand, is_active, price,
  tax_rate, track_stock, stock_quantity
) values
  -- identidad de marca exacta
  (
    '99c90000-0000-4000-8000-000000000071',
    '99c90000-0000-4000-8000-000000000001',
    'Cadena X10 Pro', 'CAD-01', '99c90000-0000-4000-8000-000000000011',
    '99c90000-0000-4000-8000-000000000061', null, true, 24990, 19, true, 0
  ),
  -- otra identidad de marca: fallo conocido cuando se pide KMC
  (
    '99c90000-0000-4000-8000-000000000072',
    '99c90000-0000-4000-8000-000000000001',
    'Cadena HG54', 'CAD-02', '99c90000-0000-4000-8000-000000000011',
    '99c90000-0000-4000-8000-000000000062', null, true, 29990, 19, true, 0
  ),
  -- sin identidad, con texto legado que normaliza al nombre vigente de KMC
  (
    '99c90000-0000-4000-8000-000000000073',
    '99c90000-0000-4000-8000-000000000001',
    'Cadena legado', 'CAD-03', '99c90000-0000-4000-8000-000000000011',
    null, '  Kmc  ', true, 19990, 19, true, 0
  ),
  -- sin marca de ninguna clase: UNKNOWN, no medio punto
  (
    '99c90000-0000-4000-8000-000000000074',
    '99c90000-0000-4000-8000-000000000001',
    'Cadena sin marca', 'CAD-04', '99c90000-0000-4000-8000-000000000011',
    null, null, true, 22990, 19, true, 0
  ),
  -- texto legado que dice otra marca: fallo conocido
  (
    '99c90000-0000-4000-8000-000000000075',
    '99c90000-0000-4000-8000-000000000001',
    'Cadena alterna', 'CAD-05', '99c90000-0000-4000-8000-000000000011',
    null, 'Sram', true, 21990, 19, true, 0
  ),
  -- sin ficha para el criterio: `unverified`, va a su propio grupo
  (
    '99c90000-0000-4000-8000-000000000076',
    '99c90000-0000-4000-8000-000000000001',
    'Cadena genérica', 'CAD-06', '99c90000-0000-4000-8000-000000000011',
    '99c90000-0000-4000-8000-000000000061', null, true, 23990, 19, true, 0
  ),
  -- la ficha contradice el criterio: `conflict`, no aparece nunca
  (
    '99c90000-0000-4000-8000-000000000077',
    '99c90000-0000-4000-8000-000000000001',
    'Cadena once', 'CAD-07', '99c90000-0000-4000-8000-000000000011',
    '99c90000-0000-4000-8000-000000000061', null, true, 27990, 19, true, 0
  ),
  -- costo y margen numéricos, pero el flete no es reproducible
  (
    '99c90000-0000-4000-8000-000000000078',
    '99c90000-0000-4000-8000-000000000001',
    'Cadena flete parcial', 'CAD-08', '99c90000-0000-4000-8000-000000000011',
    '99c90000-0000-4000-8000-000000000061', null, true, 25990, 19, true, 0
  ),
  -- comprada en USD contra un precio de catálogo en CLP
  (
    '99c90000-0000-4000-8000-000000000079',
    '99c90000-0000-4000-8000-000000000001',
    'Cadena importada', 'CAD-09', '99c90000-0000-4000-8000-000000000011',
    '99c90000-0000-4000-8000-000000000061', null, true, 26990, 19, true, 0
  ),
  -- Frenos: cubre entera la necesidad, así que bloquea el paso externo.
  (
    '99c90000-0000-4000-8000-00000000007a',
    '99c90000-0000-4000-8000-000000000001',
    'Pastilla freno', 'FRE-01', '99c90000-0000-4000-8000-000000000012',
    null, null, true, 12990, 19, true, 10
  ),
  -- Manillas: elegible y sin una sola compra en la historia.
  (
    '99c90000-0000-4000-8000-00000000007b',
    '99c90000-0000-4000-8000-000000000001',
    'Manilla nueva', 'MAN-01', '99c90000-0000-4000-8000-000000000013',
    null, null, true, 15990, 19, true, 0
  ),
  -- Piñones: único producto de su categoría, y su ficha contradice el
  -- criterio. La evaluación técnica no deja a nadie en pie.
  (
    '99c90000-0000-4000-8000-00000000007c',
    '99c90000-0000-4000-8000-000000000001',
    'Piñón doce', 'PIN-01', '99c90000-0000-4000-8000-000000000014',
    null, null, true, 17990, 19, true, 0
  ),
  -- Ruedas: el catálogo la vende en USD y se compró en USD. El margen SÍ es
  -- computable — las dos puntas comparten moneda— aunque el taller opere en
  -- CLP. Es el caso que distingue `price_currency` de `tenants.currency`.
  (
    '99c90000-0000-4000-8000-00000000007d',
    '99c90000-0000-4000-8000-000000000001',
    'Rueda importada', 'RUE-01', '99c90000-0000-4000-8000-000000000015',
    '99c90000-0000-4000-8000-000000000061', null, true, 300, 19, true, 0
  );

update public.products
set price_currency = 'USD'
where id = '99c90000-0000-4000-8000-00000000007d';

insert into public.product_spec_values(
  id, tenant_id, product_id, spec_definition_id, value_number
) values
  (
    '99c90000-0000-4000-8000-000000000081',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-000000000071',
    '99c90000-0000-4000-8000-000000000021', 10
  ),
  (
    '99c90000-0000-4000-8000-000000000082',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-000000000072',
    '99c90000-0000-4000-8000-000000000021', 10
  ),
  (
    '99c90000-0000-4000-8000-000000000083',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-000000000073',
    '99c90000-0000-4000-8000-000000000021', 10
  ),
  (
    '99c90000-0000-4000-8000-000000000084',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-000000000074',
    '99c90000-0000-4000-8000-000000000021', 10
  ),
  (
    '99c90000-0000-4000-8000-000000000085',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-000000000075',
    '99c90000-0000-4000-8000-000000000021', 10
  ),
  (
    '99c90000-0000-4000-8000-000000000087',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-000000000077',
    '99c90000-0000-4000-8000-000000000021', 11
  ),
  (
    '99c90000-0000-4000-8000-000000000088',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-000000000078',
    '99c90000-0000-4000-8000-000000000021', 10
  ),
  (
    '99c90000-0000-4000-8000-000000000089',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-000000000079',
    '99c90000-0000-4000-8000-000000000021', 10
  ),
  (
    '99c90000-0000-4000-8000-00000000008a',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-00000000007c',
    '99c90000-0000-4000-8000-000000000021', 12
  );

-- El fixture exige que la vista materializada sea consultable. Su contenido
-- no es evidencia de producción: aquí sólo habilita el contrato local.
do $$
begin
  if exists (
    select 1 from pg_class
    where oid = to_regclass('public.product_gama_bands_mv')
      and not relispopulated
  ) then
    refresh materialized view public.product_gama_bands_mv;
  end if;
end
$$;

-- El test declara el valor de referencia que utiliza en vez de depender del
-- estado incidental de otra suite. En una base anterior la tabla aún puede no
-- existir, por eso el guardián.
do $$
begin
  if to_regclass('public.purchase_source_document_kinds') is not null then
    insert into public.purchase_source_document_kinds (
      code, display_name, description, workflow_kind, sort_order, is_active
    )
    select 'tax_invoice', 'Factura',
      'Documento tributario emitido como factura por el proveedor.',
      'ordered_purchase', 10, true
    where not exists (
      select 1 from public.purchase_source_document_kinds kind
      where kind.code = 'tax_invoice'
    );
  end if;
end
$$;

insert into public.suppliers(id, tenant_id, name, comuna, city) values (
  '99c90000-0000-4000-8000-000000000091',
  '99c90000-0000-4000-8000-000000000001',
  'Distribuidora Andes', 'Providencia', 'Santiago'
);

insert into public.purchase_invoices(
  id, tenant_id, supplier_id, supplier_name, invoice_number, date, status,
  tax_treatment
) values
  (
    '99c90000-0000-4000-8000-0000000000a1',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-000000000091', 'Distribuidora Andes',
    'EC-0001', current_date - 30, 'paid', 'no_tax'
  ),
  -- Factura en USD: el candidato queda denominado en USD.
  (
    '99c90000-0000-4000-8000-0000000000a2',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-000000000091', 'Distribuidora Andes',
    'EC-0002', current_date - 30, 'paid', 'no_tax'
  ),
  -- Factura con flete en otra moneda: la asignación no es reproducible.
  (
    '99c90000-0000-4000-8000-0000000000a3',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-000000000091', 'Distribuidora Andes',
    'EC-0003', current_date - 30, 'paid', 'no_tax'
  ),
  (
    '99c90000-0000-4000-8000-0000000000a4',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-000000000091', 'Distribuidora Andes',
    'EC-0004', current_date - 30, 'paid', 'no_tax'
  );

insert into public.purchase_invoice_lines(
  id, tenant_id, purchase_invoice_id, line_number, product_id, description,
  quantity, net_amount, line_kind, line_nature, classification_status,
  currency_code
) values
  (
    '99c90000-0000-4000-8000-0000000000b1',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000a1', 1,
    '99c90000-0000-4000-8000-000000000071', 'Cadena X10 Pro',
    4, 40000, 'item', 'inventory', 'classified', 'CLP'
  ),
  (
    '99c90000-0000-4000-8000-0000000000b2',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000a1', 2,
    '99c90000-0000-4000-8000-000000000072', 'Cadena HG54',
    4, 60000, 'item', 'inventory', 'classified', 'CLP'
  ),
  (
    '99c90000-0000-4000-8000-0000000000b3',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000a1', 3,
    '99c90000-0000-4000-8000-000000000073', 'Cadena legado',
    5, 50000, 'item', 'inventory', 'classified', 'CLP'
  ),
  (
    '99c90000-0000-4000-8000-0000000000b4',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000a1', 4,
    '99c90000-0000-4000-8000-000000000074', 'Cadena sin marca',
    5, 60000, 'item', 'inventory', 'classified', 'CLP'
  ),
  (
    '99c90000-0000-4000-8000-0000000000b5',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000a1', 5,
    '99c90000-0000-4000-8000-000000000075', 'Cadena alterna',
    5, 45000, 'item', 'inventory', 'classified', 'CLP'
  ),
  (
    '99c90000-0000-4000-8000-0000000000b6',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000a1', 6,
    '99c90000-0000-4000-8000-000000000076', 'Cadena genérica',
    3, 36000, 'item', 'inventory', 'classified', 'CLP'
  ),
  (
    '99c90000-0000-4000-8000-0000000000b7',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000a1', 7,
    '99c90000-0000-4000-8000-000000000077', 'Cadena once',
    2, 30000, 'item', 'inventory', 'classified', 'CLP'
  ),
  (
    '99c90000-0000-4000-8000-0000000000b8',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000a1', 8,
    '99c90000-0000-4000-8000-00000000007a', 'Pastilla freno',
    4, 20000, 'item', 'inventory', 'classified', 'CLP'
  ),
  -- USD contra un precio de catálogo en CLP.
  (
    '99c90000-0000-4000-8000-0000000000b9',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000a2', 1,
    '99c90000-0000-4000-8000-000000000079', 'Cadena importada',
    2, 200, 'item', 'inventory', 'classified', 'USD'
  ),
  -- Mercadería en CLP con flete en USD: `partial_currency`.
  (
    '99c90000-0000-4000-8000-0000000000ba',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000a3', 1,
    '99c90000-0000-4000-8000-000000000078', 'Cadena flete parcial',
    2, 30000, 'item', 'inventory', 'classified', 'CLP'
  ),
  (
    '99c90000-0000-4000-8000-0000000000bb',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000a3', 2,
    null, 'Flete internacional',
    1, 50, 'item', 'freight', 'classified', 'USD'
  ),
  -- Compra en USD de un producto cuyo catálogo también está en USD.
  (
    '99c90000-0000-4000-8000-0000000000bc',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000a4', 1,
    '99c90000-0000-4000-8000-00000000007d', 'Rueda importada',
    2, 200, 'item', 'inventory', 'classified', 'USD'
  );

-- La necesidad del carril familia: 2 cadenas de 10 velocidades.
insert into public.supply_needs(
  id, tenant_id, origin_kind, original_description, product_id, quantity,
  unit, identity_state, supply_state, usage_state, version
) values
  (
    '99c90000-0000-4000-8000-0000000000c1',
    '99c90000-0000-4000-8000-000000000001',
    'ad_hoc', 'Cadena de 10 velocidades', null, 2, 'unit',
    'unresolved', 'open', 'not_applicable', 1
  ),
  -- Frenos: hay stock interno que la cubre entera.
  (
    '99c90000-0000-4000-8000-0000000000c2',
    '99c90000-0000-4000-8000-000000000001',
    'ad_hoc', 'Pastillas de freno', null, 2, 'unit',
    'unresolved', 'open', 'not_applicable', 1
  ),
  -- Carril exacto sobre un producto con stock que cubre.
  (
    '99c90000-0000-4000-8000-0000000000c3',
    '99c90000-0000-4000-8000-000000000001',
    'ad_hoc', 'Pastilla freno exacta',
    '99c90000-0000-4000-8000-00000000007a', 2, 'unit',
    'confirmed', 'open', 'not_applicable', 1
  ),
  -- Carril exacto que contradice la ficha.
  (
    '99c90000-0000-4000-8000-0000000000c4',
    '99c90000-0000-4000-8000-000000000001',
    'ad_hoc', 'Esta cadena de 10v',
    '99c90000-0000-4000-8000-000000000077', 1, 'unit',
    'confirmed', 'open', 'not_applicable', 1
  ),
  -- Sin categoría resuelta.
  (
    '99c90000-0000-4000-8000-0000000000c5',
    '99c90000-0000-4000-8000-000000000001',
    'ad_hoc', 'Algo para la bici', null, 1, 'unit',
    'unresolved', 'open', 'not_applicable', 1
  ),
  -- Categoría elegible sin una sola compra en la historia.
  (
    '99c90000-0000-4000-8000-0000000000c6',
    '99c90000-0000-4000-8000-000000000001',
    'ad_hoc', 'Manillas', null, 1, 'unit',
    'unresolved', 'open', 'not_applicable', 1
  ),
  -- Ya cubierta: no se propone comprar.
  (
    '99c90000-0000-4000-8000-0000000000c7',
    '99c90000-0000-4000-8000-000000000001',
    'ad_hoc', 'Cadena ya resuelta', null, 2, 'unit',
    'unresolved', 'covered', 'not_applicable', 1
  ),
  -- Todo su conjunto elegible contradice la ficha.
  (
    '99c90000-0000-4000-8000-0000000000c9',
    '99c90000-0000-4000-8000-000000000001',
    'ad_hoc', 'Piñón de 10', null, 1, 'unit',
    'unresolved', 'open', 'not_applicable', 1
  ),
  -- El catálogo y la compra comparten moneda, y no es la del taller.
  (
    '99c90000-0000-4000-8000-0000000000ca',
    '99c90000-0000-4000-8000-000000000001',
    'ad_hoc', 'Rueda importada', null, 1, 'unit',
    'unresolved', 'open', 'not_applicable', 1
  ),
  -- De otro taller.
  (
    '99c90000-0000-4000-8000-0000000000c8',
    '99c90000-0000-4000-8000-000000000002',
    'ad_hoc', 'Cadena ajena', null, 2, 'unit',
    'unresolved', 'open', 'not_applicable', 1
  );

insert into public.supply_need_interpretation_revisions(
  id, tenant_id, supply_need_id, revision_no, source, raw_description,
  identity_state, canonical_product_id, category_id, constraints,
  clarifications, formula_version
) values
  (
    '99c90000-0000-4000-8000-0000000000d1',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000c1', 1, 'ai',
    'Cadena de 10 velocidades', 'unresolved', null,
    '99c90000-0000-4000-8000-000000000011',
    jsonb_build_array(
      jsonb_build_object('field', 'chain_speeds', 'operator', 'eq',
        'values', jsonb_build_array(10)),
      jsonb_build_object('kind', 'ranking_profile', 'value', 'profitability')
    ),
    '[]'::jsonb, 'ai-supply-request-v2'
  ),
  (
    '99c90000-0000-4000-8000-0000000000d2',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000c2', 1, 'ai',
    'Pastillas de freno', 'unresolved', null,
    '99c90000-0000-4000-8000-000000000012',
    jsonb_build_array(
      jsonb_build_object('kind', 'ranking_profile', 'value', 'balanced')
    ),
    '[]'::jsonb, 'ai-supply-request-v2'
  ),
  (
    '99c90000-0000-4000-8000-0000000000d3',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000c3', 1, 'ai',
    'Pastilla freno exacta', 'confirmed',
    '99c90000-0000-4000-8000-00000000007a',
    '99c90000-0000-4000-8000-000000000012',
    '[]'::jsonb, '[]'::jsonb, 'ai-supply-request-v2'
  ),
  (
    '99c90000-0000-4000-8000-0000000000d4',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000c4', 1, 'ai',
    'Esta cadena de 10v', 'confirmed',
    '99c90000-0000-4000-8000-000000000077',
    '99c90000-0000-4000-8000-000000000011',
    jsonb_build_array(
      jsonb_build_object('field', 'chain_speeds', 'operator', 'eq',
        'values', jsonb_build_array(10))
    ),
    '[]'::jsonb, 'ai-supply-request-v2'
  ),
  (
    '99c90000-0000-4000-8000-0000000000d5',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000c5', 1, 'ai',
    'Algo para la bici', 'unresolved', null,
    null, '[]'::jsonb, '[]'::jsonb, 'ai-supply-request-v2'
  ),
  (
    '99c90000-0000-4000-8000-0000000000d6',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000c6', 1, 'ai',
    'Manillas', 'unresolved', null,
    '99c90000-0000-4000-8000-000000000013',
    '[]'::jsonb, '[]'::jsonb, 'ai-supply-request-v2'
  ),
  (
    '99c90000-0000-4000-8000-0000000000d7',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000c7', 1, 'ai',
    'Cadena ya resuelta', 'unresolved', null,
    '99c90000-0000-4000-8000-000000000011',
    jsonb_build_array(
      jsonb_build_object('field', 'chain_speeds', 'operator', 'eq',
        'values', jsonb_build_array(10))
    ),
    '[]'::jsonb, 'ai-supply-request-v2'
  ),
  (
    '99c90000-0000-4000-8000-0000000000d9',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000c9', 1, 'ai',
    'Piñón de 10', 'unresolved', null,
    '99c90000-0000-4000-8000-000000000014',
    jsonb_build_array(
      jsonb_build_object('field', 'chain_speeds', 'operator', 'eq',
        'values', jsonb_build_array(10))
    ),
    '[]'::jsonb, 'ai-supply-request-v2'
  ),
  (
    '99c90000-0000-4000-8000-0000000000da',
    '99c90000-0000-4000-8000-000000000001',
    '99c90000-0000-4000-8000-0000000000ca', 1, 'ai',
    'Rueda importada', 'unresolved', null,
    '99c90000-0000-4000-8000-000000000015',
    jsonb_build_array(
      jsonb_build_object('kind', 'ranking_profile', 'value', 'balanced')
    ),
    '[]'::jsonb, 'ai-supply-request-v2'
  );

-- ═══════════════════ 1 · sin objetivo: el legado, intacto ═════════════════
--
-- La necesidad no tiene objetivo comercial: ninguna señal se pidió, así que
-- `finalScore` tiene que ser **exactamente** el puntaje del kernel. Se compara
-- como texto a propósito: una igualdad numérica toleraría un redondeo que la
-- comparación de contrato no debe tolerar.
select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'rankingScore'
      is distinct from item.value ->> 'baseRankingScore'
  ),
  0,
  'with no target at all, every final score is byte-identical to the kernel score'
);
select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where (item.value -> 'requestMatch' ->> 'blendApplied')::boolean
  ),
  0,
  'and no blend was applied, because there was nothing known to blend'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
    ) ->> 'status'
  ),
  'success',
  'a set with history is a success'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
    ) ->> 'rankingProfile'
  ),
  'profitability',
  'the ranking profile comes from the governing revision, not from a default'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
    ) ->> 'rankingProfileSource'
  ),
  'revision',
  'and its origin is published so balanced-by-omission is not read as a choice'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
    ) ->> 'supplierAvailabilitySemantics'
  ),
  'historical_only_unverified',
  'historical purchase evidence is never verified supplier availability'
);

-- ── conflict excluido, unverified separado ────────────────────────────────
select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-07'
  ),
  0,
  'a candidate whose ficha contradicts the request never appears'
);
select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'unverifiedItems'
    ) item
    where item.value ->> 'productSku' = 'CAD-07'
  ),
  0,
  'and it is not hiding in the unverified group either'
);
select results_eq(
  $$select item.value ->> 'productSku'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'unverifiedItems'
    ) item$$,
  $$values ('CAD-06')$$,
  'the product the ERP could not verify travels in its own group, labelled'
);
select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'matchState' not in ('strong', 'weak', 'no_criteria')
  ),
  0,
  'strong, weak and no_criteria stay in the main group, each labelled honestly'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
    ) -> 'counts' ->> 'candidates'
  ),
  '8',
  'the counts describe the whole eligible set, not the page'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
    ) -> 'scoreScope' ->> 'basis'
  ),
  'eligible_set',
  'and the envelope says the score is relative to that whole set'
);

-- ── páginas independientes ────────────────────────────────────────────────
select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 2, 0, 20, 0
      ) -> 'items'
    )
  ),
  2,
  'the actionable page honours its own limit'
);
select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 2, 0, 20, 0
      ) -> 'unverifiedItems'
    )
  ),
  1,
  'and the unverified page is untouched by it'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c1', 2, 0, 20, 0
    ) -> 'page' ->> 'nextOffset'
  ),
  '2',
  'a truncated actionable page names where the next one starts'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c1', 2, 0, 20, 0
    ) -> 'unverifiedPage' ->> 'nextOffset'
  ),
  null,
  'while the unverified page, which fits, offers none'
);
select is(
  (
    select item.value ->> 'productSku'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 1, 2, 20, 0
      ) -> 'items'
    ) item
  ),
  'CAD-03',
  'the actionable offset moves only the actionable window'
);
select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 1
      ) -> 'unverifiedItems'
    )
  ),
  0,
  'and the unverified offset moves only the unverified one'
);
select throws_ok(
  $$select public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c1', 0, 0, 5, 0
    )$$,
  '22023', null,
  'an out-of-range bound is rejected instead of silently clamped'
);

-- ═══════════════ 2 · el stock va primero, y saltárselo es un error ════════
--
-- Carril familia: hay una alternativa interna que cubre entera la necesidad y
-- nadie la rechazó. Devolver una lista vacía la mostraría cualquier interfaz
-- como «no hay proveedores» y el taller compraría lo que ya tiene.
select throws_ok(
  $$select public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c2'
    )$$,
  'P0001', 'stock_first_required',
  'a covering internal alternative with no explicit rejection blocks the external step'
);
-- Carril exacto: la misma regla, sobre un producto confirmado.
select throws_ok(
  $$select public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c3'
    )$$,
  'P0001', 'stock_first_required',
  'and the exact lane is not exempt from it'
);

-- Un rechazo explícito abre la compra. Es la única puerta.
select lives_ok(
  $$select public.reject_supply_need_internal_stock_v2(
      '99c90000-0000-4000-8000-0000000000c2', 1, 1,
      'El taller reserva esas pastillas para otro trabajo.',
      'ec-reject-brakes'
    )$$,
  'the family rejection is registered'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c2'
    ) ->> 'status'
  ),
  'success',
  'and after it the external candidates are proposed'
);
select isnt(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c2'
    ) ->> 'internalStockRejectionReason'
  ),
  null,
  'with the rejection that opened the door travelling in the envelope'
);

-- ═════════ 3 · estados técnicos y conflicto exacto, sin tocar el kernel ═══
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c5'
    ) ->> 'status'
  ),
  'identity_unresolved',
  'a technical status from the bundle is returned verbatim, not reinterpreted'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c5'
    ) -> 'items'
  ),
  '[]'::jsonb,
  'with empty arrays'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c5'
    ) -> 'counts' ->> 'candidates'
  ),
  '0',
  'and no candidate universe resolved: nothing reached the kernel'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c4'
    ) ->> 'status'
  ),
  'technical_conflict',
  'an exact product that contradicts its own ficha is never ranked'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c4'
    ) -> 'unverifiedItems'
  ),
  '[]'::jsonb,
  'and it does not leak into the unverified group as a consolation prize'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c9'
    ) ->> 'status'
  ),
  'no_eligible_products',
  'a set where every product conflicted is named for what it is'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c6'
    ) ->> 'status'
  ),
  'no_historical_candidates',
  'and eligible products no one ever bought are not verifiedEmpty: nothing was verified'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c7'
    ) ->> 'status'
  ),
  'supply_closed',
  'a covered need is not offered a purchase'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c7'
    ) -> 'items'
  ),
  '[]'::jsonb,
  'and it proposes nothing, even though its eligible set still exists'
);

-- **El envelope es el mismo en todos los caminos.** La Fase B1 ya pagó el
-- error de restar del bundle y publicar en una rama claves que la otra no
-- tenía; esto es lo que impide que vuelva a pasar.
select is(
  (
    select array_agg(key order by key)
    from jsonb_object_keys(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      )
    ) key
  ),
  (
    select array_agg(key order by key)
    from jsonb_object_keys(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c5'
      )
    ) key
  ),
  'the success envelope and a technical-status envelope publish the same keys'
);

-- ═══════════════════ 4 · el fanout histórico tiene techo ══════════════════
select is(
  (
    public.supply_need_external_candidates_internal_v1(
      '99c90000-0000-4000-8000-000000000001',
      '99c90000-0000-4000-8000-0000000000c1', 10, 0, 5, 0, 3
    ) ->> 'status'
  ),
  'analysis_too_broad',
  'too much product x supplier history is analysis_too_broad, not needs_refinement'
);
select is(
  (
    public.supply_need_external_candidates_internal_v1(
      '99c90000-0000-4000-8000-000000000001',
      '99c90000-0000-4000-8000-0000000000c1', 10, 0, 5, 0, 3
    ) ->> 'candidateUniverseSize'
  ),
  '8',
  'and it says how many candidates there were'
);
select is(
  (
    public.supply_need_external_candidates_internal_v1(
      '99c90000-0000-4000-8000-000000000001',
      '99c90000-0000-4000-8000-0000000000c1', 10, 0, 5, 0, 3
    ) ->> 'candidateSafeLimit'
  ),
  '3',
  'against which ceiling — with its own name, because safeLimit already counts catalog products'
);
select isnt(
  (
    public.supply_need_external_candidates_internal_v1(
      '99c90000-0000-4000-8000-000000000001',
      '99c90000-0000-4000-8000-0000000000c1', 10, 0, 5, 0, 3
    ) ->> 'safeLimit'
  ),
  '3',
  'the catalog universe ceiling is a different fact and keeps its own value'
);
select is(
  (
    public.supply_need_external_candidates_internal_v1(
      '99c90000-0000-4000-8000-000000000001',
      '99c90000-0000-4000-8000-0000000000c1', 10, 0, 5, 0, 3
    ) -> 'items'
  ),
  '[]'::jsonb,
  'and nothing partial is returned that would look complete'
);

-- ═════════════════════════ 5 · aislamiento de taller ══════════════════════
select throws_ok(
  $$select public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c8'
    )$$,
  'P0002', null,
  'a need from another shop does not exist for this session'
);

-- ═══════════ 6 · el objetivo comercial: cada señal, con su razón ══════════
--
-- Un solo objetivo recorre las nueve razones que este corte puede emitir:
-- marca por identidad, por texto legado, por texto distinto, por identidad
-- distinta y ausente; costo dentro y fuera del tope; margen sobre y bajo el
-- piso; flete no reproducible; y moneda distinta sin tipo de cambio.
select lives_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99c90000-0000-4000-8000-0000000000c1', 1, 0,
      jsonb_build_object(
        'preferredBrandId', '99c90000-0000-4000-8000-000000000061',
        'maxLandedUnitCostNet', 11000,
        'minGrossMarginRatio', 0.45
      ),
      'ec-target-full'
    )$$,
  'the typed commercial target is set'
);

create or replace function pg_temp.ec_signal(
  p_sku text, p_signal text, p_field text
)
returns text
language sql
stable
as $$
  select item.value -> 'requestMatch' -> 'signals' -> p_signal ->> p_field
  from jsonb_array_elements(
    (public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
    ) -> 'items')
    || (public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
    ) -> 'unverifiedItems')
  ) item
  where item.value ->> 'productSku' = p_sku;
$$;

-- ── marca ─────────────────────────────────────────────────────────────────
select is(
  pg_temp.ec_signal('CAD-01', 'preferredBrandId', 'reason'),
  'brand_identity_match',
  'the preferred brand matched by identity, which is what survives a rename'
);
select is(
  pg_temp.ec_signal('CAD-01', 'preferredBrandId', 'score'),
  '1',
  'and it is worth a full point'
);
select is(
  pg_temp.ec_signal('CAD-03', 'preferredBrandId', 'reason'),
  'brand_legacy_text_match',
  'a legacy free text that normalises to the brand current name is evidence'
);
select is(
  pg_temp.ec_signal('CAD-03', 'preferredBrandId', 'score'),
  '0.75',
  'but weak evidence: 0.75, never a full match'
);
select is(
  pg_temp.ec_signal('CAD-05', 'preferredBrandId', 'reason'),
  'brand_text_differs',
  'a legacy text naming another brand is a known miss'
);
select is(
  pg_temp.ec_signal('CAD-02', 'preferredBrandId', 'reason'),
  'brand_identity_differs',
  'and so is a different brand identity'
);
select is(
  pg_temp.ec_signal('CAD-02', 'preferredBrandId', 'score'),
  '0',
  'a known miss is zero, because the evidence exists and says no'
);
select is(
  pg_temp.ec_signal('CAD-04', 'preferredBrandId', 'status'),
  'unknown',
  'no brand at all is unknown'
);
select is(
  pg_temp.ec_signal('CAD-04', 'preferredBrandId', 'score'),
  null,
  'and unknown carries no score: it is excluded from the average, never worth half a point'
);

-- ── costo aterrizado y margen ────────────────────────────────────────────
select is(
  pg_temp.ec_signal('CAD-01', 'maxLandedUnitCostNet', 'reason'),
  'cost_within_ceiling',
  'a landed cost under the ceiling meets it'
);
select is(
  pg_temp.ec_signal('CAD-02', 'maxLandedUnitCostNet', 'reason'),
  'cost_above_ceiling',
  'and one over it misses, with evidence'
);
select is(
  pg_temp.ec_signal('CAD-01', 'minGrossMarginRatio', 'reason'),
  'margin_meets_floor',
  'a projected margin over the floor meets it'
);
select is(
  pg_temp.ec_signal('CAD-03', 'minGrossMarginRatio', 'reason'),
  'margin_below_floor',
  'and one under it misses'
);

-- **Flete incompleto: el costo base existe, pero el costo aterrizado y el
-- margen no son evidencia.** Compararlos premiaría falsamente al candidato
-- cuya asignación de flete nadie puede reproducir.
select isnt(
  (
    select metric.latest_landed_unit_cost_net
    from public.purchase_candidate_metrics_v1 metric
    where metric.tenant_id = '99c90000-0000-4000-8000-000000000001'
      and metric.product_id = '99c90000-0000-4000-8000-000000000078'
  ),
  null,
  'the partial-freight candidate does have a numeric landed cost'
);
select is(
  (
    select metric.projected_gross_margin_ratio
    from public.purchase_candidate_metrics_v1 metric
    where metric.tenant_id = '99c90000-0000-4000-8000-000000000001'
      and metric.product_id = '99c90000-0000-4000-8000-000000000078'
  ),
  null,
  'and the view refuses to publish a margin derived from incomplete freight'
);
select is(
  (
    select metric.projected_unit_gross_profit
    from public.purchase_candidate_metrics_v1 metric
    where metric.tenant_id = '99c90000-0000-4000-8000-000000000001'
      and metric.product_id = '99c90000-0000-4000-8000-000000000078'
  ),
  null,
  'the raw projected profit is withheld for the same reason'
);
select is(
  (
    select metric.latest_freight_evidence_status
    from public.purchase_candidate_metrics_v1 metric
    where metric.tenant_id = '99c90000-0000-4000-8000-000000000001'
      and metric.product_id = '99c90000-0000-4000-8000-000000000078'
  ),
  'partial_currency',
  'what is missing is a reproducible freight allocation'
);
select is(
  pg_temp.ec_signal('CAD-08', 'maxLandedUnitCostNet', 'reason'),
  'incomplete_landed_cost',
  'so the cost signal is unknown, not a comparison against a base cost'
);
select is(
  pg_temp.ec_signal('CAD-08', 'minGrossMarginRatio', 'reason'),
  'incomplete_landed_cost',
  'and so is the margin that was derived from it'
);
select is(
  pg_temp.ec_signal('CAD-08', 'maxLandedUnitCostNet', 'score'),
  null,
  'neither is worth zero: unknown is excluded, not penalised'
);
select is(
  (
    select item.value ->> 'economyScore'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99c90000-0000-4000-8000-000000000078', null, 'balanced', 10, null
      ) -> 'items'
    ) item
  ),
  '0.350000',
  'incomplete freight leaves the economy dimension neutral'
);
select is(
  (
    select item.value ->> 'evidenceQuality'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99c90000-0000-4000-8000-000000000078', null, 'balanced', 10, null
      ) -> 'items'
    ) item
  ),
  'partial',
  'and incomplete freight can never be labelled complete evidence'
);
select is(
  (
    select item.value ->> 'evidenceScore'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99c90000-0000-4000-8000-000000000078', null, 'balanced', 10, null
      ) -> 'items'
    ) item
  ),
  '0.600000',
  'catalog price does not earn the profitability evidence reward when freight is incomplete'
);

-- **Moneda distinta: precedencia sobre todo lo demás, y jamás se convierte.**
select is(
  pg_temp.ec_signal('CAD-09', 'maxLandedUnitCostNet', 'reason'),
  'currency_mismatch_no_fx',
  'a cost in another currency than the target ceiling is unknown'
);
select is(
  pg_temp.ec_signal('CAD-09', 'minGrossMarginRatio', 'reason'),
  'currency_mismatch_no_fx',
  'and a margin whose cost and catalog price are in different currencies too'
);
select is(
  (
    select item.value ->> 'catalogSalePriceCurrency'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-09'
  ),
  'CLP',
  'the catalog price currency is published so the client can audit the verdict'
);
select is(
  (
    select item.value ->> 'currency'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-09'
  ),
  'USD',
  'next to the currency the candidate itself is denominated in'
);

-- La gama no se cuenta dos veces: entra al kernel y aquí sólo se declara.
select is(
  pg_temp.ec_signal('CAD-01', 'gama', 'score'),
  null,
  'gama carries no signal score: it is already a quarter of the kernel weight'
);

-- ═══════════════ 7 · la matemática: 75/25 sobre las conocidas ════════════
select is(
  (
    select item.value -> 'requestMatch' ->> 'knownSignalCount'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-08'
  ),
  '1',
  'only the known signals are counted: two unknowns do not enter the average'
);
select is(
  (
    select item.value -> 'requestMatch' ->> 'knownSignalAverage'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-03'
  ),
  '0.583333',
  'and the average is over those alone: (0.75 + 1 + 0) / 3'
);
select is(
  (
    select item.value ->> 'rankingScore'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-03'
  ),
  '0.738139',
  'the blend is 0.75 * legacy + 0.25 * average, rounded once at the end'
);

-- **Near tie:** el valor completo gobierna el orden y el round pertenece sólo
-- a la proyección. La primera aserción ata la propiedad a la función real; la
-- segunda deja visible el caso que un round previo convertiría en empate.
select ok(
  position(
    'else round(' in lower(substring(
      pg_get_functiondef(
        'public.supply_need_external_candidates_internal_v1(uuid,uuid,integer,integer,integer,integer,integer)'::regprocedure
      ) from 'blended as \(.*?ranked as'
    ))
  ) = 0,
  'the blend is not rounded before ranking'
);
select is(
  (
    select string_agg(label, ',' order by raw_score desc, tie_break asc)
    from (values
      ('raw-winner'::text, 0.50000049::numeric, 2),
      ('tie-break-winner'::text, 0.50000041::numeric, 1)
    ) sample(label, raw_score, tie_break)
  ),
  'raw-winner,tie-break-winner',
  'a sub-six-decimal difference remains decisive before output rounding'
);
select is(
  (
    select round(
      0.75 * (item.value ->> 'baseRankingScore')::numeric
      + 0.25 * (item.value -> 'requestMatch' ->> 'knownSignalAverage')::numeric,
      6
    )::text
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-01'
  ),
  '0.917420',
  'and it reproduces exactly from the two numbers the item publishes'
);

-- **La mezcla es monótona.** Como el puntaje del kernel vive en [0,1], una
-- señal cumplida nunca baja a un candidato y una fallada nunca lo sube. Sin
-- esa propiedad, «premiar» un objetivo podría castigar y nadie lo notaría.
select cmp_ok(
  (
    select (item.value ->> 'rankingScore')::numeric
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-01'
  ),
  '>',
  (
    select (item.value ->> 'baseRankingScore')::numeric
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-01'
  ),
  'a candidate that meets everything is raised above its kernel score'
);
select cmp_ok(
  (
    select (item.value ->> 'rankingScore')::numeric
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-02'
  ),
  '<',
  (
    select (item.value ->> 'baseRankingScore')::numeric
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-02'
  ),
  'and one that misses everything is lowered below it'
);

-- El rango del kernel se conserva con nombre propio: sin él nadie podría ver
-- cuánto movió el objetivo.
select is(
  (
    select item.value ->> 'baseRank'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-08'
  ),
  '8',
  'baseRank survives the rerank'
);
select is(
  (
    select count(distinct item.value ->> 'overallRank')::integer
    from jsonb_array_elements(
      (public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items')
      || (public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'unverifiedItems')
    ) item
  ),
  8,
  'overallRank spans both groups without collisions'
);
select is(
  (
    select item.value ->> 'rank'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'unverifiedItems'
    ) item
  ),
  '1',
  'while rank restarts inside each group, which is what a list renders'
);
select is(
  (
    select item.value ->> 'rankingVersion'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    limit 1
  ),
  'supply-need-external-candidates-v1',
  'a reranked item declares a new ranking version, not the kernel one'
);

-- ════ 8 · todo desconocido conserva el legado; y el objetivo rescata ══════
--
-- El parche limpia los dos rangos y deja sólo la marca. Con eso, un candidato
-- sin marca de ninguna clase no tiene **ninguna** señal conocida.
select lives_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99c90000-0000-4000-8000-0000000000c1',
      (select need.version from public.supply_needs need
        where need.id = '99c90000-0000-4000-8000-0000000000c1'),
      (select revision.revision_no
        from public.supply_need_commercial_revisions revision
        where revision.supply_need_id = '99c90000-0000-4000-8000-0000000000c1'
        order by revision.revision_no desc limit 1),
      jsonb_build_object(
        'preferredBrandId', '99c90000-0000-4000-8000-000000000062',
        'maxLandedUnitCostNet', null,
        'minGrossMarginRatio', null
      ),
      'ec-target-brand-only'
    )$$,
  'the target is patched down to a single preference'
);
select is(
  (
    select item.value ->> 'rankingScore'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-04'
  ),
  (
    select item.value ->> 'baseRankingScore'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-04'
  ),
  'a candidate whose every requested signal is unknown keeps the kernel score, byte for byte'
);
select is(
  (
    select item.value -> 'requestMatch' ->> 'knownSignalCount'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 20, 0, 20, 0
      ) -> 'items'
    ) item
    where item.value ->> 'productSku' = 'CAD-04'
  ),
  '0',
  'because nothing known was left to average'
);

-- **El objetivo cambia al ganador, y el ganador venía fuera de la primera
-- página.** Es la prueba de que se puntúa el conjunto entero antes de cortar:
-- una implementación que recortara a uno antes de puntuar sólo podría devolver
-- el primero del kernel, pase lo que pase con el objetivo.
select is(
  (
    select item.value ->> 'productSku'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 1, 0, 20, 0
      ) -> 'items'
    ) item
  ),
  'CAD-02',
  'with the target, the single-item page is the candidate that matches it'
);
select is(
  (
    select item.value ->> 'baseRank'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 1, 0, 20, 0
      ) -> 'items'
    ) item
  ),
  '4',
  'and the kernel had it in fourth place: the cut happened after scoring'
);
select isnt(
  (
    select item.value ->> 'productSku'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000c1', 1, 0, 20, 0
      ) -> 'items'
    ) item
  ),
  'CAD-01',
  'the kernel winner is no longer the winner, which is the whole point of a target'
);

-- ═════ 9 · el wrapper histórico: CLP intacto, cross-currency corregido ════
--
-- `rank_purchase_candidates_v1` no se tocó. Lo que cambió es que su kernel ya
-- no trata una resta entre monedas como margen. El arnés golden es CLP puro,
-- así que su salida es idéntica; estas dos pruebas son lo que demuestra que la
-- corrección igual muerde donde hay dos monedas.
select isnt(
  (
    select item.value -> 'projectedGrossMarginRatio'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99c90000-0000-4000-8000-000000000071', null, 'balanced', 10, null
      ) -> 'items'
    ) item
  ),
  'null'::jsonb,
  'a same-currency candidate still publishes its projected margin'
);
select is(
  (
    select item.value -> 'projectedGrossMarginRatio'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99c90000-0000-4000-8000-000000000079', null, 'balanced', 10, null
      ) -> 'items'
    ) item
  ),
  'null'::jsonb,
  'a cost in USD minus a catalog price in CLP is not a margin: it is unknown'
);
select is(
  (
    select item.value -> 'projectedUnitGrossProfit'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99c90000-0000-4000-8000-000000000079', null, 'balanced', 10, null
      ) -> 'items'
    ) item
  ),
  'null'::jsonb,
  'and neither is the raw subtraction that produced it'
);
select isnt(
  (
    select item.value -> 'catalogSalePriceNet'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99c90000-0000-4000-8000-000000000079', null, 'balanced', 10, null
      ) -> 'items'
    ) item
  ),
  'null'::jsonb,
  'the catalog price itself is real and still published: what is unknown is the comparison'
);
select is(
  (
    select item.value ->> 'economyScore'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99c90000-0000-4000-8000-000000000079', null, 'balanced', 10, null
      ) -> 'items'
    ) item
  ),
  '0.350000',
  'the economy dimension takes its neutral value, the same one an absent margin took'
);
select is(
  (
    select item.value ->> 'evidenceQuality'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99c90000-0000-4000-8000-000000000079', null, 'balanced', 10, null
      ) -> 'items'
    ) item
  ),
  'partial',
  'cross-currency evidence is never labelled complete'
);
select is(
  (
    select item.value ->> 'evidenceScore'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99c90000-0000-4000-8000-000000000079', null, 'balanced', 10, null
      ) -> 'items'
    ) item
  ),
  '0.800000',
  'and catalog price earns no profitability evidence reward across currencies'
);
-- **Ninguna clave nueva en el item del kernel.** El golden compara el JSON
-- entero: una clave más lo rompería aunque no cambiara un número, y por eso la
-- moneda del precio de catálogo la publica la RPC nueva y no ésta.
select ok(
  not (
    select item.value ? 'catalogSalePriceCurrency'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99c90000-0000-4000-8000-000000000071', null, 'balanced', 10, null
      ) -> 'items'
    ) item
  ),
  'the historical ranking item gained no key: its golden output is untouched'
);
select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99c90000-0000-4000-8000-000000000071', null, 'balanced', 10, null
      ) -> 'items'
    ) item, jsonb_object_keys(item.value) key
  ),
  43,
  'and it still publishes exactly the 43 keys the golden harness froze'
);

-- ═══ 10 · price_currency no es tenants.currency, y se nota ═══════════════
--
-- El taller opera en CLP. Esta rueda se vende en USD y se compró en USD: las
-- dos puntas de la resta comparten moneda, así que el margen **sí** es
-- computable. Sustituir `price_currency` por la moneda del taller declararía
-- desconocido un margen perfectamente válido — y ese era el atajo disponible
-- antes de que la vista publicara la columna.
select lives_ok(
  $$select public.set_supply_need_commercial_target_v1(
      '99c90000-0000-4000-8000-0000000000ca', 1, 0,
      jsonb_build_object(
        'maxLandedUnitCostNet', 5000,
        'minGrossMarginRatio', 0.50
      ),
      'ec-target-usd-catalog'
    )$$,
  'a target in the shop currency is set over a catalog priced in another one'
);
select is(
  (
    public.get_supply_need_external_candidates_v1(
      '99c90000-0000-4000-8000-0000000000ca'
    ) ->> 'targetCurrencyCode'
  ),
  'CLP',
  'the target is denominated in the shop currency, as the revision recorded it'
);
select is(
  (
    select item.value ->> 'catalogSalePriceCurrency'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000ca'
      ) -> 'items'
    ) item
  ),
  'USD',
  'while the catalog price of this candidate is not'
);
select is(
  (
    select item.value -> 'requestMatch' -> 'signals'
      -> 'minGrossMarginRatio' ->> 'status'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000ca'
      ) -> 'items'
    ) item
  ),
  'met',
  'the margin is KNOWN: cost and catalog price share a currency, which is all a ratio needs'
);
select is(
  (
    select item.value -> 'requestMatch' -> 'signals'
      -> 'maxLandedUnitCostNet' ->> 'reason'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000ca'
      ) -> 'items'
    ) item
  ),
  'currency_mismatch_no_fx',
  'and the cost ceiling is UNKNOWN in the same candidate: a denominated amount needs the target currency'
);
select isnt(
  (
    select item.value -> 'projectedGrossMarginRatio'
    from jsonb_array_elements(
      public.get_supply_need_external_candidates_v1(
        '99c90000-0000-4000-8000-0000000000ca'
      ) -> 'items'
    ) item
  ),
  'null'::jsonb,
  'and the kernel kept the margin too: same-currency is same-currency, whatever the shop uses'
);

select * from finish();
rollback;
