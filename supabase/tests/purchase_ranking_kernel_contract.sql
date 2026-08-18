begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- El contrato entre `rank_purchase_candidates_v1` y su kernel de scoring.
--
-- El arnés golden de `manual_checks/verification` demuestra la extracción **el
-- día que se hace**, comparando salidas antes y después. Esto es lo otro: las
-- tres propiedades que tienen que seguir siendo ciertas para siempre, sin
-- depender de que alguien recuerde correr una comparación manual.
--
-- Ninguna de estas pruebas recalcula un puntaje. La fórmula tiene un solo
-- dueño y aquí sólo se afirma **qué universo entra** y **cuándo se corta**.

select has_function(
  'public', 'purchase_candidate_scores_internal_v1',
  array['uuid', 'uuid[]', 'text', 'text'],
  'scoring has one owner, and it consumes candidate identities'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.purchase_candidate_scores_internal_v1(uuid,uuid[],text,text)',
    'execute'
  ),
  'the kernel is internal: only the governed wrappers reach it'
);
select has_function(
  'public', 'rank_purchase_candidates_v1',
  array['text', 'uuid', 'uuid', 'text', 'integer', 'text'],
  'the public ranking keeps its signature'
);
select has_column(
  'public', 'purchase_candidate_metrics_v1', 'brand_id',
  'candidates publish the brand identity a commercial preference matches on'
);

-- ───────────────────────────── datos de prueba ─────────────────────────────
--
-- La forma mínima que hace visibles las tres propiedades: un producto comprado
-- a DOS proveedores —dos candidatos, un solo `product_id`— y un proveedor cuyo
-- nombre no aparece en ningún producto.
insert into public.tenants(id, shop_name, currency, timezone) values (
  '99f60000-0000-4000-8000-000000000001',
  'Ranking Kernel Tenant', 'CLP', 'America/Santiago'
);
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99f60000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'ranking-kernel@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(
  user_id, tenant_id, role, permissions, is_active
) values (
  '99f60000-0000-4000-8000-000000000099',
  '99f60000-0000-4000-8000-000000000001',
  'admin', '{}'::jsonb, true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99f60000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99f60000-0000-4000-8000-000000000099',
  true
);

insert into public.product_categories(
  id, tenant_id, name, full_path, level, is_active
) values (
  '99f60000-0000-4000-8000-000000000011',
  '99f60000-0000-4000-8000-000000000001',
  'Cadenas', 'Transmisión / Cadenas', 1, true
);
insert into public.product_brands(id, tenant_id, name, is_active) values (
  '99f60000-0000-4000-8000-000000000021',
  '99f60000-0000-4000-8000-000000000001', 'KMC', true
);
insert into public.products(
  id, tenant_id, name, sku, category_id, brand_id, is_active, price,
  tax_rate, track_stock, stock_quantity
) values (
  '99f60000-0000-4000-8000-000000000031',
  '99f60000-0000-4000-8000-000000000001',
  'Cadena KMC X10 116L', 'KMC-X10',
  '99f60000-0000-4000-8000-000000000011',
  '99f60000-0000-4000-8000-000000000021', true, 24990, 19, true, 5
);

-- «Zafiro» no aparece en el nombre, sku, marca ni categoría del producto: la
-- única forma de que una consulta por ese texto encuentre algo es el blob que
-- incluye `supplier_name`.
insert into public.suppliers(id, tenant_id, name, comuna, city) values
  (
    '99f60000-0000-4000-8000-000000000041',
    '99f60000-0000-4000-8000-000000000001',
    'Distribuidora Andes', 'Providencia', 'Santiago'
  ),
  (
    '99f60000-0000-4000-8000-000000000042',
    '99f60000-0000-4000-8000-000000000001',
    'Importadora Zafiro', 'Ñuñoa', 'Santiago'
  );

insert into public.purchase_invoices(
  id, tenant_id, supplier_id, supplier_name, invoice_number, date, status,
  tax_treatment
) values
  (
    '99f60000-0000-4000-8000-000000000051',
    '99f60000-0000-4000-8000-000000000001',
    '99f60000-0000-4000-8000-000000000041', 'Distribuidora Andes',
    'KC-0001', current_date - 30, 'paid', 'no_tax'
  ),
  (
    '99f60000-0000-4000-8000-000000000052',
    '99f60000-0000-4000-8000-000000000001',
    '99f60000-0000-4000-8000-000000000042', 'Importadora Zafiro',
    'KC-0002', current_date - 200, 'received', 'no_tax'
  );
insert into public.purchase_invoice_lines(
  id, tenant_id, purchase_invoice_id, line_number, product_id, description,
  quantity, net_amount, line_kind, line_nature, classification_status,
  currency_code
) values
  (
    '99f60000-0000-4000-8000-000000000061',
    '99f60000-0000-4000-8000-000000000001',
    '99f60000-0000-4000-8000-000000000051', 1,
    '99f60000-0000-4000-8000-000000000031',
    'Cadena KMC X10 116L', 4, 40000,
    'item', 'inventory', 'classified', 'CLP'
  ),
  (
    '99f60000-0000-4000-8000-000000000062',
    '99f60000-0000-4000-8000-000000000001',
    '99f60000-0000-4000-8000-000000000052', 1,
    '99f60000-0000-4000-8000-000000000031',
    'Cadena KMC X10 116L', 3, 33000,
    'item', 'inventory', 'classified', 'CLP'
  );

-- Punto de partida: un producto, dos candidatos.
select is(
  (
    select count(*)::integer
    from public.purchase_candidate_metrics_v1 metric
    where metric.tenant_id = '99f60000-0000-4000-8000-000000000001'
  ),
  2,
  'one product bought from two suppliers is two candidates, not one'
);

-- ── 1 · una consulta que sólo casa por proveedor no reexpande el producto ──
--
-- Ésta es la propiedad que hace imposible colapsar el universo a `product_ids`:
-- «zafiro» selecciona el candidato de ESE proveedor. Si alguien colapsara a
-- producto y volviera a expandir, aparecería también Distribuidora Andes.
select is(
  (
    public.rank_purchase_candidates_v1(
      'zafiro', null, null, 'balanced', 10, null
    ) ->> 'resultCount'
  )::integer,
  1,
  'a supplier-only query returns that supplier candidate and no sibling'
);
select is(
  (
    select item.value ->> 'supplierName'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        'zafiro', null, null, 'balanced', 10, null
      ) -> 'items'
    ) item
  ),
  'Importadora Zafiro',
  'and it is exactly the supplier the text matched'
);
-- Contraste: por producto sí vienen los dos.
select is(
  (
    public.rank_purchase_candidates_v1(
      null, '99f60000-0000-4000-8000-000000000031', null, 'balanced', 10, null
    ) ->> 'resultCount'
  )::integer,
  2,
  'the exact-product path still sees both suppliers'
);

-- ── 2 · el corte se aplica DESPUÉS de puntuar ─────────────────────────────
--
-- Con `limit 1` sobre dos candidatos, el que sobrevive tiene que ser el de
-- `rank` 1. Recortar antes de la fórmula dejaría el que la base devolviera
-- primero, que es otro.
select is(
  (
    select item.value ->> 'candidateId'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99f60000-0000-4000-8000-000000000031', null, 'balanced', 1, null
      ) -> 'items'
    ) item
  ),
  (
    select item.value ->> 'candidateId'
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99f60000-0000-4000-8000-000000000031', null, 'balanced', 10, null
      ) -> 'items'
    ) item
    where (item.value ->> 'rank')::integer = 1
  ),
  'p_limit keeps the top-ranked candidate, so the cut happens after scoring'
);
select is(
  (
    public.rank_purchase_candidates_v1(
      null, '99f60000-0000-4000-8000-000000000031', null, 'balanced', 1, null
    ) ->> 'hasMore'
  )::boolean,
  true,
  'and the truncation is declared instead of hidden'
);

-- ── 3 · el item del wrapper es exactamente el del kernel ──────────────────
--
-- La proyección tiene un solo dueño. Si alguien vuelve a armarla en el
-- wrapper, esta prueba lo dice.
select is(
  (
    select jsonb_agg(item.value order by (item.value ->> 'rank')::integer)
    from jsonb_array_elements(
      public.rank_purchase_candidates_v1(
        null, '99f60000-0000-4000-8000-000000000031', null, 'balanced', 10, null
      ) -> 'items'
    ) item
  ),
  (
    select jsonb_agg(scored.item order by scored.rank)
    from public.purchase_candidate_scores_internal_v1(
      '99f60000-0000-4000-8000-000000000001',
      (
        select array_agg(metric.candidate_id)
        from public.purchase_candidate_metrics_v1 metric
        where metric.tenant_id = '99f60000-0000-4000-8000-000000000001'
          and metric.product_id = '99f60000-0000-4000-8000-000000000031'
      ),
      'balanced', null
    ) scored
  ),
  'the wrapper publishes the kernel item verbatim: one projection, one owner'
);

-- La gama viaja hasta el kernel y cambia el puntaje sin cambiar el universo.
select is(
  (
    select count(*)::integer
    from public.purchase_candidate_scores_internal_v1(
      '99f60000-0000-4000-8000-000000000001',
      (
        select array_agg(metric.candidate_id)
        from public.purchase_candidate_metrics_v1 metric
        where metric.tenant_id = '99f60000-0000-4000-8000-000000000001'
      ),
      'balanced', 'alta'
    )
  ),
  2,
  'asking for a band orders the set, it never removes a candidate'
);

-- Un universo vacío no es un error: es un conjunto sin filas.
select is(
  (
    select count(*)::integer
    from public.purchase_candidate_scores_internal_v1(
      '99f60000-0000-4000-8000-000000000001',
      array[]::uuid[], 'balanced', null
    )
  ),
  0,
  'an empty candidate set scores nothing and raises nothing'
);
select is(
  (
    public.rank_purchase_candidates_v1(
      'texto que no existe', null, null, 'balanced', 10, null
    ) ->> 'status'
  ),
  'verifiedEmpty',
  'and the public path reports it as a verified empty result'
);

-- Aislamiento: el kernel no puede puntuar candidatos de otro tenant.
select is(
  (
    select count(*)::integer
    from public.purchase_candidate_scores_internal_v1(
      '99f60000-0000-4000-8000-000000000001',
      (
        select array_agg(metric.candidate_id)
        from public.purchase_candidate_metrics_v1 metric
      ),
      'balanced', null
    )
  ),
  2,
  'the kernel scopes to its tenant even when handed foreign identities'
);

select * from finish();
rollback;
