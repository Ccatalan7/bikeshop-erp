-- Read-back of 20261024030000: the catalog search understands the workshop's
-- words, the spec sheet and the visitor's measures. Plain SQL: a missing
-- invariant divides by zero after printing what it found.

select count(*) as shared_concepts
  from public.catalog_search_terms
 where tenant_id is null;
select 1 / (case when (select count(*) from public.catalog_search_terms where tenant_id is null) >= 70 then 1 else 0 end)
  as afirma_vocabulario_sembrado;

select public.catalog_search_normalize_v1('Cámara 29x2.25 11 velocidades 1x12 29er 700c') as normalized;
select 1 / (case when public.catalog_search_normalize_v1('Cámara 29x2.25 11 velocidades 1x12 29er 700c')
  = 'camara 29 2 25 11v 12v 29 700' then 1 else 0 end) as afirma_normaliza_medidas_y_velocidades;

select 1 / (case when position('catalog_search_terms' in pg_get_functiondef(
    'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure)) > 0
  and position('required_tokens' in pg_get_functiondef(
    'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure)) > 0
  then 1 else 0 end) as afirma_busqueda_lee_vocabulario;

select 1 / (case when not has_table_privilege('anon', 'public.catalog_search_terms', 'select')
  and not has_table_privilege('authenticated', 'public.catalog_search_terms', 'select') then 1 else 0 end)
  as afirma_vocabulario_cerrado;

-- With Viñabike's real catalog: what failed on 2026-10-24.
select t.term, count(r.id) as found, string_agg(left(r.name, 50), ' | ' order by r.name) as some
  from unnest(array['camara fv', 'cadena 11v', '29x2.25', 'camara av']) as t(term)
  left join lateral public.get_public_products_without_inventory_reservations(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, t.term, null, false, 'name', 5, 0
  ) r on true
 group by t.term;
select 1 / (case when (select count(*) from public.get_public_products_without_inventory_reservations(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, 'camara fv', null, false, 'name', 100, 0)) >= 1
  then 1 else 0 end) as afirma_fv_es_francesa;
select 1 / (case when (select count(*) from public.get_public_products_without_inventory_reservations(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, 'cadena 11v', null, false, 'name', 100, 0)) >= 1
  then 1 else 0 end) as afirma_11v_es_11_velocidades;
select 1 / (case when (select count(*) from public.get_public_products_without_inventory_reservations(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid, null, null, null, '29x2.25', null, false, 'name', 100, 0)) >= 1
  then 1 else 0 end) as afirma_medida_sin_espacios;
