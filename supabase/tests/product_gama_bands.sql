begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- La gama dejó de ser una frase que el modelo interpreta: es un dato derivado
-- del historial de compras, corregible por el dueño, y una dimensión del
-- ranking que ORDENA sin eliminar.

select has_table(
  'public', 'product_gama_overrides',
  'la corrección explícita del operador tiene dónde vivir'
);
select has_view(
  'public', 'product_gama_bands_v1',
  'la banda derivada del historial es un read model propio'
);
select has_view(
  'public', 'product_gama_v1',
  'la banda vigente resuelve derivada contra corrección'
);

-- La firma incorpora la gama sin dejar una segunda candidata ambigua.
select has_function(
  'public', 'rank_purchase_candidates_v1',
  array['text', 'uuid', 'uuid', 'text', 'integer', 'text'],
  'el ranking acepta la gama pedida'
);
select is(
  (select count(*)::int from pg_proc where proname = 'rank_purchase_candidates_v1'),
  1,
  'queda una sola función: PostgREST no puede quedar ante dos candidatas'
);

-- El override es único por marca dentro de la categoría.
select col_is_unique(
  'public', 'product_gama_overrides',
  array['tenant_id', 'category_id', 'brand'],
  'una marca tiene una sola banda corregida por categoría'
);

-- Sólo tres bandas, y ninguna otra palabra.
select throws_ok(
  $$insert into public.product_gama_overrides (tenant_id, category_id, brand, band)
    values (gen_random_uuid(), gen_random_uuid(), 'X', 'premium')$$,
  '23514',
  null,
  'una banda fuera de económica/media/alta se rechaza'
);

-- RLS encendido: la banda corregida es de un tenant, no del sistema.
select is(
  (select relrowsecurity
     from pg_class
    where oid = 'public.product_gama_overrides'::regclass),
  true,
  'la corrección de gama está aislada por tenant'
);

-- La banda derivada nunca inventa una posición cuando no hay con qué comparar.
select is(
  (select count(*)::int
     from public.product_gama_bands_v1
    where brands_in_category < 2 and price_position is not null),
  0,
  'con una sola marca no se declara posición de precio'
);
select is(
  (select count(*)::int
     from public.product_gama_bands_v1
    where band_is_confident and purchase_count < 3),
  0,
  'una marca con menos de tres compras no se presenta como banda confiable'
);

-- Sin tenant no se rankea nada: la autoridad se comprueba ANTES que los
-- argumentos, así que una gama inválida ni siquiera llega a evaluarse.
select throws_ok(
  $$select public.rank_purchase_candidates_v1('rayos', null, null, 'balanced', 10, 'barata')$$,
  '42501',
  null,
  'el ranking falla cerrado por autoridad antes de mirar la gama'
);

-- Y con tenant, el vocabulario de gama es cerrado dentro de la propia función.
select matches(
  pg_get_functiondef('public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)'::regprocedure),
  'p_gama not in \(''economica'', ''media'', ''alta''\)',
  'la gama pedida se valida contra un vocabulario cerrado'
);

-- La gama ordena, nunca elimina: no aparece en ningún filtro del WHERE.
select isnt_empty(
  $$select 1 where pg_get_functiondef(
      'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)'::regprocedure
    ) like '%0.25 * gama_score%'$$,
  'la gama entra como peso del puntaje, no como criterio de exclusión'
);

select * from finish();
rollback;
