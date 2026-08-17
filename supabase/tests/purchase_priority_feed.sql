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

select * from finish();
rollback;
