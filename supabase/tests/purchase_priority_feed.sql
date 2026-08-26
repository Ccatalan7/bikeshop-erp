begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- La prioridad la levanta el sistema. La brecha más grande de alguien sin
-- experiencia no es «qué proveedor», es **que hay que comprar**.

select has_function(
  'public', 'purchase_priority_feed_v1',
  array['integer', 'integer'],
  'la prioridad de compra es un RPC versionado y acotado por tenant'
);

select has_function(
  'public', 'take_purchase_priority_batch_v1',
  array['jsonb', 'integer', 'text'],
  'la búsqueda conjunta tiene un comando versionado y replay-safe'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.purchase_priority_feed_v1(integer,integer)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.purchase_priority_feed_v1(integer,integer)',
    'execute'
  ),
  'la prioridad es para personal autenticado, nunca anónimo'
);

-- Falla cerrado por autoridad antes que por argumentos.
select throws_ok(
  $$select public.purchase_priority_feed_v1(40, 120)$$,
  '42501',
  null,
  'sin tenant no se propone ninguna compra'
);

select throws_ok(
  $$select public.take_purchase_priority_batch_v1(
    '[{"source":"workshop","entityId":"99c20000-0000-4000-8000-000000000071"}]'::jsonb,
    120,
    'priority-no-authority'
  )$$,
  '42501',
  null,
  'sin tenant tampoco se puede tomar un lote de prioridades'
);

-- La rotación es una ventana declarada, no un número escondido en el código.
select matches(
  pg_get_functiondef('public.purchase_priority_feed_v1(integer,integer)'::regprocedure),
  'p_rotation_days not between 7 and 730',
  'la ventana de rotación se valida y viaja como parámetro'
);

-- El filtro que hace útil la lista: sin venta reciente, un quiebre no es
-- urgencia. Sin este join la lista pasa de ~100 filas a más de 1.100.
select matches(
  pg_get_functiondef('public.purchase_priority_feed_v1(integer,integer)'::regprocedure),
  'join rotation on rotation.product_id = product.id',
  'un quiebre sólo entra si el producto realmente rota'
);

-- Nunca se propone lo que la persona ya tomó.
select matches(
  pg_get_functiondef('public.purchase_priority_feed_v1(integer,integer)'::regprocedure),
  'not in \(select product_id from already_needed\)',
  'lo que ya está en una necesidad abierta no se vuelve a proponer'
);

-- Cada fila explica por qué está ahí: es la transferencia de experiencia.
select matches(
  pg_get_functiondef('public.purchase_priority_feed_v1(integer,integer)'::regprocedure),
  '''reason'', reason',
  'toda fila de la prioridad viaja con su razón en palabras'
);

-- El taller manda sobre el quiebre, y el quiebre sobre el mínimo.
select matches(
  pg_get_functiondef('public.purchase_priority_feed_v1(integer,integer)'::regprocedure),
  'order by urgency_rank',
  'el orden es por urgencia, no por proveedor ni por nombre'
);

-- La fila de taller no es una idea de producto: ya existe como necesidad y
-- debe transportar el trabajo y su alcance físico exactos.
insert into public.tenants(id, shop_name) values
  ('99c20000-0000-4000-8000-000000000001', 'Priority context tenant');

-- El bootstrap del tenant puede dejar claims transitorios al sembrar defaults.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99c20000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'priority-context@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(user_id, tenant_id, role) values (
  '99c20000-0000-4000-8000-000000000099',
  '99c20000-0000-4000-8000-000000000001',
  'admin'
);
insert into public.customers(id, tenant_id, name) values (
  '99c20000-0000-4000-8000-000000000011',
  '99c20000-0000-4000-8000-000000000001',
  'Priority context customer'
);
insert into public.bikes(
  id, tenant_id, customer_id, brand, model, year, serial_number
) values (
  '99c20000-0000-4000-8000-000000000012',
  '99c20000-0000-4000-8000-000000000001',
  '99c20000-0000-4000-8000-000000000011',
  'Best', 'Otis 29', 2024, 'CTX-29'
);
insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, workflow_kind,
  intake_kind, status
) values (
  '99c20000-0000-4000-8000-000000000041',
  '99c20000-0000-4000-8000-000000000001',
  '99c20000-0000-4000-8000-000000000011',
  'PG-CONTEXT', 'item_service', 'service', 'bike', 'REPUESTOS'
);
insert into public.mechanic_job_bikes(
  id, tenant_id, job_id, bike_id, order_index
) values (
  '99c20000-0000-4000-8000-000000000051',
  '99c20000-0000-4000-8000-000000000001',
  '99c20000-0000-4000-8000-000000000041',
  '99c20000-0000-4000-8000-000000000012',
  0
);
insert into public.products(
  id, tenant_id, name, sku, price, cost, inventory_qty,
  stock_quantity, min_stock_level, track_stock,
  is_active, is_service, product_type
) values
  (
    '99c20000-0000-4000-8000-000000000061',
    '99c20000-0000-4000-8000-000000000001',
    'Disco de contexto', 'PRIORITY-CONTEXT', 20000, 8000, 0,
    0, 0, true, true, false, 'product'
  ),
  (
    '99c20000-0000-4000-8000-000000000062',
    '99c20000-0000-4000-8000-000000000001',
    'Neumático de lote', 'PRIORITY-BATCH', 24000, 9000, 0,
    0, 2, true, true, false, 'product'
  );

insert into public.stock_movements(
  id, tenant_id, product_id, date, type, movement_type, quantity, created_at
) values (
  '99c20000-0000-4000-8000-000000000063',
  '99c20000-0000-4000-8000-000000000001',
  '99c20000-0000-4000-8000-000000000062',
  clock_timestamp(), 'OUT', 'sale', 2, clock_timestamp()
);
insert into public.supply_needs(
  id, tenant_id, origin_kind, mechanic_job_id, job_bike_id,
  original_description, product_id, quantity, unit,
  identity_state, supply_state, usage_state
) values
  (
    '99c20000-0000-4000-8000-000000000071',
    '99c20000-0000-4000-8000-000000000001',
    'mechanic_job', '99c20000-0000-4000-8000-000000000041',
    '99c20000-0000-4000-8000-000000000051',
    'Disco para bicicleta exacta',
    '99c20000-0000-4000-8000-000000000061',
    1, 'unit', 'confirmed', 'open', 'pending'
  ),
  (
    '99c20000-0000-4000-8000-000000000072',
    '99c20000-0000-4000-8000-000000000001',
    'mechanic_job', '99c20000-0000-4000-8000-000000000041',
    null,
    'Disco para todo el trabajo',
    '99c20000-0000-4000-8000-000000000061',
    1, 'unit', 'confirmed', 'open', 'pending'
  );

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99c20000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99c20000-0000-4000-8000-000000000099',
  true
);

create temporary table purchase_priority_context_result as
select public.purchase_priority_feed_v1(40, 120) as payload;

select is(
  (
    select item.value->'jobContext'->>'jobNumber'
    from purchase_priority_context_result result
    cross join lateral jsonb_array_elements(result.payload->'items') item
    where item.value->>'entityId' =
      '99c20000-0000-4000-8000-000000000071'
  ),
  'PG-CONTEXT',
  'the workshop priority row names its exact job'
);
select is(
  (
    select item.value->'jobContext'->>'jobBikeId'
    from purchase_priority_context_result result
    cross join lateral jsonb_array_elements(result.payload->'items') item
    where item.value->>'entityId' =
      '99c20000-0000-4000-8000-000000000071'
  ),
  '99c20000-0000-4000-8000-000000000051',
  'the workshop priority row keeps the exact job-bike link'
);
select is(
  (
    select concat_ws(
      ' ',
      item.value->'jobContext'->>'bikeBrand',
      item.value->'jobContext'->>'bikeModel'
    )
    from purchase_priority_context_result result
    cross join lateral jsonb_array_elements(result.payload->'items') item
    where item.value->>'entityId' =
      '99c20000-0000-4000-8000-000000000071'
  ),
  'Best Otis 29',
  'the assigned bicycle carries its real human identity'
);
select is(
  (
    select item.value->'jobContext'->>'scope'
    from purchase_priority_context_result result
    cross join lateral jsonb_array_elements(result.payload->'items') item
    where item.value->>'entityId' =
      '99c20000-0000-4000-8000-000000000072'
  ),
  'whole_job',
  'a NULL job-bike link remains intentional whole-job scope'
);
select is(
  (
    select item.value->'jobContext'->>'jobBikeId'
    from purchase_priority_context_result result
    cross join lateral jsonb_array_elements(result.payload->'items') item
    where item.value->>'entityId' =
      '99c20000-0000-4000-8000-000000000072'
  ),
  null,
  'whole-job scope never invents a primary bicycle'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.take_purchase_priority_batch_v1(jsonb,integer,text)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.take_purchase_priority_batch_v1(jsonb,integer,text)',
    'execute'
  ),
  'el lote sólo se ejecuta con una sesión autenticada'
);

create temporary table purchase_priority_batch_result as
select public.take_purchase_priority_batch_v1(
  jsonb_build_array(
    jsonb_build_object(
      'source', 'workshop',
      'entityId', '99c20000-0000-4000-8000-000000000071'
    ),
    jsonb_build_object(
      'source', 'stockout',
      'entityId', '99c20000-0000-4000-8000-000000000062'
    )
  ),
  120,
  'priority-context-batch-1'
) as payload;

select is(
  (select payload->>'needCount' from purchase_priority_batch_result),
  '2',
  'una selección mixta devuelve sus dos necesidades en un lote'
);
select is(
  (select payload->'needs'->0->>'id' from purchase_priority_batch_result),
  '99c20000-0000-4000-8000-000000000071',
  'la fila de taller conserva la necesidad original'
);
select is(
  (
    select count(*)::text
    from public.supply_needs need
    where need.tenant_id = '99c20000-0000-4000-8000-000000000001'
      and need.product_id = '99c20000-0000-4000-8000-000000000062'
      and need.origin_kind = 'ad_hoc'
      and need.supply_state = 'open'
  ),
  '1',
  'la señal de stock crea una sola necesidad directa'
);
select is(
  (
    select revision.source
    from public.supply_need_interpretation_revisions revision
    join public.supply_needs need on need.id = revision.supply_need_id
    where need.product_id = '99c20000-0000-4000-8000-000000000062'
    order by revision.revision_no desc
    limit 1
  ),
  'manual',
  'una prioridad automática no falsifica procedencia de IA'
);

create temporary table purchase_priority_batch_replay as
select public.take_purchase_priority_batch_v1(
  jsonb_build_array(
    jsonb_build_object(
      'source', 'workshop',
      'entityId', '99c20000-0000-4000-8000-000000000071'
    ),
    jsonb_build_object(
      'source', 'stockout',
      'entityId', '99c20000-0000-4000-8000-000000000062'
    )
  ),
  120,
  'priority-context-batch-1'
) as payload;

select is(
  (select payload->>'replay' from purchase_priority_batch_replay),
  'true',
  'reintentar el mismo lote relee su recibo'
);
select is(
  (
    select count(*)::text
    from public.supply_needs need
    where need.tenant_id = '99c20000-0000-4000-8000-000000000001'
      and need.product_id = '99c20000-0000-4000-8000-000000000062'
      and need.origin_kind = 'ad_hoc'
  ),
  '1',
  'el replay no duplica la necesidad de stock'
);

select throws_ok(
  $$select public.take_purchase_priority_batch_v1(
    '[{"source":"stockout","entityId":"99c20000-0000-4000-8000-000000000099"}]'::jsonb,
    120,
    'priority-context-stale'
  )$$,
  '40001',
  null,
  'una identidad ausente del feed falla cerrada como selección obsoleta'
);

select * from finish();
rollback;
